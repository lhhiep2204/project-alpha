//
//  DeviceLocationServiceTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import CoreLocation
import Foundation
import Testing
@testable import ProjectAlpha

private enum PositionFixture {
    static let now = Date(timeIntervalSinceReferenceDate: 1_000)
    static func authorization(_ status: LocationAuthorizationStatus = .authorizedWhenInUse,
                              reduced: Bool = false, enabled: Bool = true) -> LocationAuthorization {
        LocationAuthorization(status: status, accuracy: reduced ? .reduced : .full, servicesEnabled: enabled)
    }
    static func fix(age: TimeInterval = 0, reduced: Bool = false) throws -> DevicePosition {
        try DevicePosition(coordinate: Coordinate(latitude: 10, longitude: 20),
                           timestamp: now.addingTimeInterval(-age), horizontalAccuracyMetres: 350,
                           authorization: authorization(reduced: reduced))
    }
}

/// Event-driven fake; no live location manager, polling or wall-clock waits.
@MainActor
private final class PositionDriver: DeviceLocationDriver {
    var authorization: LocationAuthorization
    var onEvent: (@MainActor (DeviceLocationDriverEvent) -> Void)?
    var prompts = 0
    var starts = 0
    var stops = 0
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var promptWaiter: CheckedContinuation<Void, Never>?

    init(_ authorization: LocationAuthorization = PositionFixture.authorization()) { self.authorization = authorization }
    func requestWhenInUseAuthorization() { prompts += 1; promptWaiter?.resume(); promptWaiter = nil }
    func startUpdatingLocation() {
        starts += 1
        let ready = startWaiters.filter { $0.0 <= starts }
        startWaiters.removeAll { $0.0 <= starts }
        for (_, waiter) in ready { waiter.resume() }
    }
    func stop() { stops += 1; onEvent = nil }
    func waitForPrompt() async {
        if prompts > 0 { return }
        await withCheckedContinuation { promptWaiter = $0 }
    }
    func waitForStart(_ minimum: Int = 1) async {
        if starts >= minimum { return }
        await withCheckedContinuation { startWaiters.append((minimum, $0)) }
    }
    /// Uses the exact production delegate batch traversal without creating a live manager.
    func deliverBatch(_ locations: [CLLocation]) -> [DevicePosition] {
        var delivered: [DevicePosition] = []
        CoreLocationDriver.deliverLocations(locations, authorization: authorization,
            isStopped: { self.stops > 0 }, onEvent: { event in
                if case .position(let fix) = event { delivered.append(fix) }
                self.onEvent?(event)
            })
        return delivered
    }
    func grant(reduced: Bool = false) {
        authorization = PositionFixture.authorization(reduced: reduced)
        onEvent?(.authorizationChanged(authorization))
    }
}

private actor PositionDeadline {
    private var sleepers: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private(set) var durations: [Duration] = []
    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = continuation
                durations.append(duration)
                startedWaiter?.resume()
                startedWaiter = nil
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func waitForStart() async {
        if !durations.isEmpty { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }
    func expire() {
        let pending = Array(sleepers.values)
        sleepers.removeAll()
        for continuation in pending { continuation.resume() }
    }
    private func cancel(_ id: UUID) { sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
}

private nonisolated struct PositionClock: ServiceClock {
    let deadline = PositionDeadline()
    func now() -> Date { PositionFixture.now }
    func sleep(for duration: Duration) async throws { try await deadline.sleep(duration) }
}

@MainActor
struct DeviceLocationServiceTests {
    /// AC-37, D-01: construction/inspection never prompts or starts acquisition.
    @Test func constructionAndInspectionHaveNoLocationSideEffects() async {
        let driver = PositionDriver()
        var creations = 0
        let service = CoreLocationDeviceService(makeDriver: { creations += 1; return driver })
        #expect(creations == 0)
        #expect(await service.authorization() == driver.authorization)
        #expect(driver.prompts == 0 && driver.starts == 0)
        #expect(driver.stops == 1)
    }

    /// AC-37: denial/restriction/disabled errors are typed, with no permission re-prompt.
    @Test func unavailableAuthorizationNeverPrompts() async {
        for (authorization, expected) in [
            (PositionFixture.authorization(.denied), LocationServiceError.permissionDenied),
            (PositionFixture.authorization(.restricted), .permissionRestricted),
            (PositionFixture.authorization(enabled: false), .servicesDisabled)
        ] {
            let driver = PositionDriver(authorization)
            let service = CoreLocationDeviceService(makeDriver: { driver })
            await #expect(throws: expected) { try await service.currentPosition() }
            await #expect(throws: expected) { try await service.currentPosition() }
            #expect(driver.prompts == 0 && driver.starts == 0)
            #expect(driver.stops == 2)
        }
    }

    /// AC-37: no acquisition deadline runs while the system prompt is unresolved.
    @Test func promptWaitIsExcludedAndReducedFixIsReturnedUnchanged() async throws {
        let driver = PositionDriver(PositionFixture.authorization(.notDetermined))
        let clock = PositionClock()
        let service = CoreLocationDeviceService(clock: clock, makeDriver: { driver })
        let task = Task { try await service.currentPosition() }
        await driver.waitForPrompt()
        #expect(await clock.deadline.durations.isEmpty)
        #expect(driver.starts == 0)
        driver.onEvent?(.authorizationChanged(driver.authorization))
        driver.onEvent?(.authorizationChanged(driver.authorization))
        #expect(driver.prompts == 1)
        await clock.deadline.expire() // Advancing the acquisition clock during the prompt has no effect.
        driver.grant(reduced: true)
        await driver.waitForStart()
        await clock.deadline.waitForStart()
        driver.grant(reduced: true)
        driver.grant(reduced: true)
        #expect(driver.starts == 1 && driver.prompts == 1)
        #expect(await clock.deadline.durations == [.seconds(10)])
        // AC-37: a past fix is accepted; acquisition timeout bounds waiting, not fix age.
        let fix = try PositionFixture.fix(age: 30, reduced: true)
        let late = driver.onEvent
        driver.onEvent?(.position(fix))
        #expect(try await task.value == fix)
        #expect(driver.stops == 1)
        late?(.failure(.positionUnavailable))
        late?(.position(fix))
        #expect(driver.stops == 1)
    }

    /// AC-37: a valid past fix is returned immediately regardless of age; terminal callbacks stay ignored.
    @Test func pastFixesAreAcceptedRegardlessOfAgeAndLateCallbacksAreIgnored() async throws {
        let oldFixAges: [TimeInterval] = [30.001, 10 * 365 * 24 * 60 * 60]
        for age in oldFixAges {
            let driver = PositionDriver()
            let service = CoreLocationDeviceService(clock: PositionClock(), makeDriver: { driver })
            let task = Task { try await service.currentPosition() }
            await driver.waitForStart()
            let late = driver.onEvent
            let fix = try PositionFixture.fix(age: age)
            driver.onEvent?(.position(fix))
            #expect(try await task.value == fix)
            #expect(driver.stops == 1)
            late?(.position(try PositionFixture.fix()))
            #expect(driver.stops == 1)
        }
    }

    /// AC-37, U-10: invalid/transient callbacks retain one stream until the first valid fix.
    @Test func invalidAndTransientCallbacksKeepOneStreamUntilValidPastFix() async throws {
        let driver = PositionDriver()
        let clock = PositionClock()
        let service = CoreLocationDeviceService(clock: clock, makeDriver: { driver })
        let task = Task { try await service.currentPosition() }
        await driver.waitForStart()
        await clock.deadline.waitForStart()
        for _ in 0..<3 {
            driver.onEvent?(.position(try PositionFixture.fix(age: -0.001)))
            driver.onEvent?(.locationUnknown)
            driver.grant()
        }
        #expect(driver.starts == 1 && driver.stops == 0)
        #expect(await clock.deadline.durations == [.seconds(10)])
        let fix = try PositionFixture.fix(age: 10 * 365 * 24 * 60 * 60)
        driver.onEvent?(.position(fix))
        #expect(try await task.value == fix)
        #expect(driver.stops == 1)
    }

    /// AC-37/U-10: the real batch traversal continues after broker rejection of
    /// a future newest fix, then stops immediately after the first accepted past fix.
    @Test func realDelegateBatchSkipsRejectedNewestAndStopsAfterAcceptedFix() async throws {
        let driver = PositionDriver()
        let clock = PositionClock()
        let service = CoreLocationDeviceService(clock: clock, makeDriver: { driver })
        let request = Task { try await service.currentPosition() }
        await driver.waitForStart()
        await clock.deadline.waitForStart()
        let older = batchLocation(age: 7_200, latitude: 9)
        let valid = batchLocation(age: 3_600, latitude: 10)
        let future = batchLocation(age: -1, latitude: 11)
        let delivered = driver.deliverBatch([older, valid, future])
        let result = try await request.value
        #expect(result.coordinate.latitude == 10)
        #expect(result.timestamp == valid.timestamp)
        #expect(delivered.map(\.timestamp) == [future.timestamp, valid.timestamp])
        #expect(driver.starts == 1 && driver.stops == 1)
        #expect(await clock.deadline.durations == [.seconds(10)])
    }

    /// AC-37/U-10: a batch with only unusable samples preserves acquisition and
    /// its original deadline, rather than completing or restarting the timeout.
    @Test func realDelegateAllInvalidBatchKeepsOriginalDeadlineUntilTimeout() async throws {
        let driver = PositionDriver()
        let clock = PositionClock()
        let service = CoreLocationDeviceService(clock: clock, makeDriver: { driver })
        let request = Task { try await service.currentPosition() }
        await driver.waitForStart()
        await clock.deadline.waitForStart()
        let structurallyInvalid = batchLocation(age: 0, latitude: 10, accuracy: -1)
        let delivered = driver.deliverBatch([structurallyInvalid, batchLocation(age: -1, latitude: 11)])
        #expect(delivered.count == 1)
        #expect(driver.starts == 1 && driver.stops == 0)
        #expect(await clock.deadline.durations == [.seconds(10)])
        await clock.deadline.expire()
        await #expect(throws: LocationServiceError.timedOut) { try await request.value }
        #expect(driver.stops == 1)
    }

    private func batchLocation(age: TimeInterval, latitude: Double, accuracy: Double = 10) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 20),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10,
                   timestamp: PositionFixture.now.addingTimeInterval(-age))
    }

    /// AC-37: exact acquisition deadline yields timeout and stops the provider once.
    @Test func noFixTimesOutAndLateCallbacksCannotReviveAcquisition() async throws {
        let driver = PositionDriver()
        let clock = PositionClock()
        let service = CoreLocationDeviceService(clock: clock, makeDriver: { driver })
        let task = Task { try await service.currentPosition() }
        await driver.waitForStart()
        await clock.deadline.waitForStart()
        #expect(await clock.deadline.durations == [.seconds(10)])
        let late = driver.onEvent
        for _ in 0..<3 {
            driver.onEvent?(.locationUnknown)
            driver.onEvent?(.position(try PositionFixture.fix(age: -0.001)))
            driver.grant()
        }
        #expect(driver.starts == 1 && driver.stops == 0)
        #expect(await clock.deadline.durations == [.seconds(10)])
        await clock.deadline.expire()
        await #expect(throws: LocationServiceError.timedOut) { try await task.value }
        #expect(driver.stops == 1)
        late?(.position(try PositionFixture.fix()))
        #expect(driver.stops == 1)
    }

    /// AC-37, D-01: cancelling one coalesced consumer leaves the other acquisition alive.
    @Test func coalescedConsumersCancelIndependently() async throws {
        let driver = PositionDriver()
        var registration: CheckedContinuation<Void, Never>?
        var consumers = 0
        var creations = 0
        let service = CoreLocationDeviceService(clock: PositionClock(), onConsumerCountChanged: { count in
            consumers = count
            if count == 2 { registration?.resume(); registration = nil }
        }, makeDriver: { creations += 1; return driver })
        let first = Task { try await service.currentPosition() }
        await driver.waitForStart()
        let second = Task { try await service.currentPosition() }
        if consumers < 2 { await withCheckedContinuation { registration = $0 } }
        #expect(creations == 1 && driver.starts == 1)
        first.cancel()
        await #expect(throws: LocationServiceError.cancelled) { try await first.value }
        #expect(consumers == 1 && driver.stops == 0)
        let fix = try PositionFixture.fix()
        driver.onEvent?(.position(fix))
        #expect(try await second.value == fix)
        #expect(consumers == 0 && driver.stops == 1)
    }

    /// AC-37, U-10: cancelling permission wait starts neither updates nor a deadline.
    @Test func cancellationDuringPermissionIgnoresLateGrant() async throws {
        let driver = PositionDriver(PositionFixture.authorization(.notDetermined))
        let clock = PositionClock()
        let service = CoreLocationDeviceService(clock: clock, makeDriver: { driver })
        let task = Task { try await service.currentPosition() }
        await driver.waitForPrompt()
        let late = driver.onEvent
        task.cancel()
        await #expect(throws: LocationServiceError.cancelled) { try await task.value }
        late?(.authorizationChanged(PositionFixture.authorization()))
        late?(.locationUnknown)
        late?(.position(try PositionFixture.fix()))
        #expect(driver.prompts == 1 && driver.starts == 0 && driver.stops == 1)
        #expect(await clock.deadline.durations.isEmpty)
    }

    /// AC-37, D-03: coalesced consumers share one fix/stream; only final cancellation stops it.
    @Test func coalescedConsumersShareSuccessOrCancelTogether() async throws {
        for cancel in [false, true] {
            let driver = PositionDriver()
            let clock = PositionClock()
            var registration: CheckedContinuation<Void, Never>?
            var consumers = 0
            var creations = 0
            let service = CoreLocationDeviceService(clock: clock, onConsumerCountChanged: { count in
                consumers = count
                if count == 2 { registration?.resume(); registration = nil }
            }, makeDriver: { creations += 1; return driver })
            let first = Task { try await service.currentPosition() }
            await driver.waitForStart()
            let second = Task { try await service.currentPosition() }
            if consumers < 2 { await withCheckedContinuation { registration = $0 } }
            await clock.deadline.waitForStart()
            let late = driver.onEvent
            #expect(creations == 1 && driver.starts == 1)
            #expect(await clock.deadline.durations == [.seconds(10)])
            if cancel {
                first.cancel()
                await #expect(throws: LocationServiceError.cancelled) { try await first.value }
                #expect(consumers == 1 && driver.stops == 0)
                second.cancel()
                await #expect(throws: LocationServiceError.cancelled) { try await second.value }
            } else {
                let fix = try PositionFixture.fix()
                driver.onEvent?(.position(fix))
                #expect(try await first.value == fix)
                #expect(try await second.value == fix)
            }
            #expect(consumers == 0 && driver.starts == 1 && driver.stops == 1)
            late?(.position(try PositionFixture.fix()))
            late?(.locationUnknown)
            #expect(driver.starts == 1 && driver.stops == 1)
        }
    }

    /// AC-37, D-03: prior generations cannot stop or complete a later acquisition.
    @Test func oldCallbacksCannotChangeNextAcquisition() async throws {
        let firstDriver = PositionDriver()
        let nextDriver = PositionDriver()
        var creations = 0
        var consumers = 0
        let service = CoreLocationDeviceService(clock: PositionClock(), onConsumerCountChanged: { consumers = $0 },
                                                makeDriver: {
            creations += 1
            return creations == 1 ? firstDriver : nextDriver
        })
        let first = Task { try await service.currentPosition() }
        await firstDriver.waitForStart()
        let late = firstDriver.onEvent
        first.cancel()
        await #expect(throws: LocationServiceError.cancelled) { try await first.value }
        let next = Task { try await service.currentPosition() }
        await nextDriver.waitForStart()
        late?(.authorizationChanged(PositionFixture.authorization(.denied)))
        late?(.failure(.positionUnavailable))
        late?(.locationUnknown)
        late?(.position(try PositionFixture.fix(age: 20)))
        #expect(consumers == 1 && creations == 2)
        #expect(firstDriver.starts == 1 && firstDriver.stops == 1)
        #expect(nextDriver.starts == 1 && nextDriver.stops == 0)
        let fix = try PositionFixture.fix()
        nextDriver.onEvent?(.position(fix))
        #expect(try await next.value == fix)
        #expect(consumers == 0 && nextDriver.stops == 1)
    }

    /// AC-37: provider failure completes once; cancellation stops the final consumer.
    @Test func failureAndCancellationCleanUpExactlyOnce() async {
        for cancel in [false, true] {
            let driver = PositionDriver()
            let service = CoreLocationDeviceService(clock: PositionClock(), makeDriver: { driver })
            let task = Task { try await service.currentPosition() }
            await driver.waitForStart()
            let late = driver.onEvent
            if cancel { task.cancel() } else { driver.onEvent?(.failure(.positionUnavailable)) }
            await #expect(throws: cancel ? LocationServiceError.cancelled : .positionUnavailable) { try await task.value }
            #expect(driver.starts == 1 && driver.stops == 1)
            late?(.failure(.positionUnavailable))
            #expect(driver.stops == 1)
        }
    }
}
