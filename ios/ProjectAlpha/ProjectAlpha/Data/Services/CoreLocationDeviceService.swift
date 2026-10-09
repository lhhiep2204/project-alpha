//
//  CoreLocationDeviceService.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import CoreLocation
import Foundation

/// SDK objects belong to one acquisition, so callbacks cannot leak into a later request.
@MainActor
protocol DeviceLocationDriver: AnyObject {
    var authorization: LocationAuthorization { get }
    func authorizationSnapshot() async -> LocationAuthorization
    var onEvent: (@MainActor (DeviceLocationDriverEvent) -> Void)? { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
    func stop()
}

nonisolated enum DeviceLocationDriverEvent: Sendable {
    case authorizationChanged(LocationAuthorization)
    case position(DevicePosition)
    case failure(LocationServiceError)
}

@MainActor
final class CoreLocationDeviceService: DeviceLocationService {
    private let makeDriver: @MainActor () -> any DeviceLocationDriver
    private let clock: any ServiceClock
    private let onConsumerCountChanged: @MainActor (Int) -> Void
    private var driver: (any DeviceLocationDriver)?
    private var generation: UUID?
    private var waiters: [UUID: CheckedContinuation<DevicePosition, any Error>] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var acquiring = false
    private var authorizationRequested = false
    private var startTask: Task<Void, Never>?

    init(
        clock: any ServiceClock = SystemServiceClock(),
        onConsumerCountChanged: @escaping @MainActor (Int) -> Void = { _ in },
        makeDriver: @escaping @MainActor () -> any DeviceLocationDriver = { CoreLocationDriver() }
    ) {
        self.clock = clock
        self.onConsumerCountChanged = onConsumerCountChanged
        self.makeDriver = makeDriver
    }

    @MainActor func authorization() async -> LocationAuthorization {
        if let driver { return await driver.authorizationSnapshot() }
        // Construct only on explicit inspection, never during app/container initialization.
        let probe = makeDriver()
        let result = await probe.authorizationSnapshot()
        probe.stop()
        return result
    }

    @MainActor func currentPosition() async throws(LocationServiceError) -> DevicePosition {
        let waiterID = UUID()
        do {
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    waiters[waiterID] = continuation
                    onConsumerCountChanged(waiters.count)
                    if driver == nil { begin() }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancel(waiterID) }
            }
            guard !Task.isCancelled else { throw LocationServiceError.cancelled }
            return result
        } catch let error as LocationServiceError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .positionUnavailable
        }
    }

    private func begin() {
        let requestID = UUID()
        generation = requestID
        let newDriver = makeDriver()
        driver = newDriver
        startTask = Task { @MainActor [weak self] in
            let authorization = await newDriver.authorizationSnapshot()
            guard !Task.isCancelled, let self, self.generation == requestID else { return }
            newDriver.onEvent = { [weak self] event in
                guard let self, self.generation == requestID else { return }
                self.receive(event)
            }
            self.handleAuthorization(authorization)
        }
    }

    private func handleAuthorization(_ authorization: LocationAuthorization) {
        guard authorization.servicesEnabled else { finish(.failure(.servicesDisabled)); return }
        switch authorization.status {
        case .notDetermined:
            guard !authorizationRequested else { return }
            authorizationRequested = true
            driver?.requestWhenInUseAuthorization()
        case .denied:
            finish(.failure(.permissionDenied))
        case .restricted:
            finish(.failure(.permissionRestricted))
        case .authorizedWhenInUse, .authorizedAlways:
            guard !acquiring, let requestID = generation else { return }
            acquiring = true
            let clock = clock
            timeoutTask = Task { @MainActor [weak self] in
                do { try await clock.sleep(for: CurrentPositionPolicy.acquisitionTimeout) }
                catch { return }
                guard !Task.isCancelled, self?.generation == requestID else { return }
                self?.finish(.failure(.timedOut))
            }
            driver?.requestLocation()
        }
    }

    private func receive(_ event: DeviceLocationDriverEvent) {
        switch event {
        case let .authorizationChanged(authorization): handleAuthorization(authorization)
        case let .position(position):
            do {
                try CurrentPositionPolicy.validate(position, now: clock.now())
                finish(.success(position))
            } catch {
                // An invalid fix does not complete acquisition; await another fix until timeout.
                driver?.requestLocation()
            }
        case let .failure(error):
            finish(.failure(error))
        }
    }

    private func cancel(_ waiterID: UUID) {
        if let continuation = waiters.removeValue(forKey: waiterID) {
            onConsumerCountChanged(waiters.count)
            continuation.resume(throwing: LocationServiceError.cancelled)
        }
        if waiters.isEmpty { cleanup() }
    }

    private func finish(_ result: Result<DevicePosition, LocationServiceError>) {
        let pending = waiters.values
        waiters.removeAll()
        onConsumerCountChanged(0)
        cleanup()
        for continuation in pending {
            switch result {
            case let .success(position): continuation.resume(returning: position)
            case let .failure(error): continuation.resume(throwing: error)
            }
        }
    }

    private func cleanup() {
        generation = nil
        startTask?.cancel()
        startTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        driver?.stop()
        driver = nil
        acquiring = false
        authorizationRequested = false
    }
}

/// CLLocationManager is created on demand on its delegate's actor/run loop.
@MainActor
final class CoreLocationDriver: NSObject, DeviceLocationDriver, @MainActor CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var servicesEnabled = false
    private var stopped = false
    private var authorizationTask: Task<Void, Never>?
    var onEvent: (@MainActor (DeviceLocationDriverEvent) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var authorization: LocationAuthorization {
        let status: LocationAuthorizationStatus
        switch manager.authorizationStatus {
        case .notDetermined: status = .notDetermined
        case .restricted: status = .restricted
        case .denied: status = .denied
        case .authorizedWhenInUse: status = .authorizedWhenInUse
        case .authorizedAlways: status = .authorizedAlways
        @unknown default: status = .restricted
        }
        return LocationAuthorization(
            status: status,
            accuracy: manager.accuracyAuthorization == .fullAccuracy ? .full : .reduced,
            servicesEnabled: servicesEnabled
        )
    }

    func authorizationSnapshot() async -> LocationAuthorization {
        servicesEnabled = await Self.queryServicesEnabled()
        return authorization
    }

    @concurrent private static func queryServicesEnabled() async -> Bool {
        CLLocationManager.locationServicesEnabled()
    }

    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestLocation() { manager.requestLocation() }
    func stop() {
        stopped = true
        authorizationTask?.cancel()
        authorizationTask = nil
        onEvent = nil
        manager.delegate = nil
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationTask?.cancel()
        authorizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.authorizationSnapshot()
            guard !Task.isCancelled, !self.stopped else { return }
            self.onEvent?(.authorizationChanged(snapshot))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !stopped else { return }
        for location in locations.reversed() {
            guard let coordinate = try? Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ), let position = try? DevicePosition(
                coordinate: coordinate,
                timestamp: location.timestamp,
                horizontalAccuracyMetres: location.horizontalAccuracy,
                authorization: authorization
            ) else { continue }
            onEvent?(.position(position))
            return
        }
        // Core Location has completed a one-shot request without a valid fix.
        requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard !stopped else { return }
        if let error = error as? CLError {
            switch error.code {
            case .denied:
                onEvent?(.failure(authorization.servicesEnabled ? .permissionDenied : .servicesDisabled))
            case .locationUnknown:
                // This is transient; the acquisition deadline remains authoritative.
                requestLocation()
            default:
                onEvent?(.failure(.positionUnavailable))
            }
        } else {
            onEvent?(.failure(.positionUnavailable))
        }
    }
}

nonisolated struct SystemServiceClock: ServiceClock {
    func now() -> Date { Date() }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

@MainActor
extension DeviceLocationDriver {
    func authorizationSnapshot() async -> LocationAuthorization { authorization }
}
