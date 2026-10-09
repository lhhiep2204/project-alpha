//
//  DeviceLocationServiceTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

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
    var requests = 0
    var stops = 0
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var promptWaiter: CheckedContinuation<Void, Never>?

    init(_ authorization: LocationAuthorization = PositionFixture.authorization()) { self.authorization = authorization }
    func requestWhenInUseAuthorization() { prompts += 1; promptWaiter?.resume(); promptWaiter = nil }
    func requestLocation() {
        requests += 1
        let ready = requestWaiters.filter { $0.0 <= requests }
        requestWaiters.removeAll { $0.0 <= requests }
        for (_, waiter) in ready { waiter.resume() }
    }
    func stop() { stops += 1; onEvent = nil }
    func waitForPrompt() async {
        if prompts > 0 { return }
        await withCheckedContinuation { promptWaiter = $0 }
    }
    func waitForRequests(_ minimum: Int = 1) async {
        if requests >= minimum { return }
        await withCheckedContinuation { requestWaiters.append((minimum, $0)) }
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
        #expect(driver.prompts == 0 && driver.requests == 0)
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
            #expect(driver.prompts == 0 && driver.requests == 0)
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
        #expect(driver.requests == 0)
        driver.onEvent?(.authorizationChanged(driver.authorization))
        driver.onEvent?(.authorizationChanged(driver.authorization))
        #expect(driver.prompts == 1)
        await clock.deadline.expire() // Advancing the acquisition clock during the prompt has no effect.
        driver.grant(reduced: true)
        await driver.waitForRequests()
        await clock.deadline.waitForStart()
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
            await driver.waitForRequests()
            let late = driver.onEvent
            let fix = try PositionFixture.fix(age: age)
            driver.onEvent?(.position(fix))
            #expect(try await task.value == fix)
            #expect(driver.stops == 1)
            late?(.position(try PositionFixture.fix()))
            #expect(driver.stops == 1)
        }
    }

    /// AC-37: future timestamps are rejected; a later valid past fix completes the request.
    @Test func futureCallbackWaitsForValidPastFix() async throws {
        let driver = PositionDriver()
        let clock = PositionClock()
        let service = CoreLocationDeviceService(clock: clock, makeDriver: { driver })
        let task = Task { try await service.currentPosition() }
        await driver.waitForRequests()
        driver.onEvent?(.position(try PositionFixture.fix(age: -0.001)))
        await driver.waitForRequests(2)
        #expect(driver.stops == 0)
        let fix = try PositionFixture.fix(age: 10 * 365 * 24 * 60 * 60)
        driver.onEvent?(.position(fix))
        #expect(try await task.value == fix)
        #expect(driver.stops == 1)
    }

    /// AC-37: exact acquisition deadline yields timeout and stops the provider once.
    @Test func noFixTimesOutAndLateCallbacksCannotReviveAcquisition() async throws {
        let driver = PositionDriver()
        let clock = PositionClock()
        let service = CoreLocationDeviceService(clock: clock, makeDriver: { driver })
        let task = Task { try await service.currentPosition() }
        await driver.waitForRequests()
        await clock.deadline.waitForStart()
        #expect(await clock.deadline.durations == [.seconds(10)])
        let late = driver.onEvent
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
        await driver.waitForRequests()
        let second = Task { try await service.currentPosition() }
        if consumers < 2 { await withCheckedContinuation { registration = $0 } }
        #expect(creations == 1 && driver.requests == 1)
        first.cancel()
        await #expect(throws: LocationServiceError.cancelled) { try await first.value }
        #expect(consumers == 1 && driver.stops == 0)
        let fix = try PositionFixture.fix()
        driver.onEvent?(.position(fix))
        #expect(try await second.value == fix)
        #expect(consumers == 0 && driver.stops == 1)
    }

    /// AC-37: provider failure completes once; cancellation stops the final consumer.
    @Test func failureAndCancellationCleanUpExactlyOnce() async {
        for cancel in [false, true] {
            let driver = PositionDriver()
            let service = CoreLocationDeviceService(clock: PositionClock(), makeDriver: { driver })
            let task = Task { try await service.currentPosition() }
            await driver.waitForRequests()
            let late = driver.onEvent
            if cancel { task.cancel() } else { driver.onEvent?(.failure(.positionUnavailable)) }
            await #expect(throws: cancel ? LocationServiceError.cancelled : .positionUnavailable) { try await task.value }
            #expect(driver.stops == 1)
            late?(.failure(.positionUnavailable))
            #expect(driver.stops == 1)
        }
    }
}
