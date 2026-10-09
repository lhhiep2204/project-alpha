//
//  MapPresentationTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 7/10/26.
//

import Foundation
import MapKit
import SwiftUI
import Testing
@testable import ProjectAlpha

/// AC-37 / INV-09: permission, camera and lifecycle behavior without live GPS.
@MainActor
struct MapPresentationTests {
    @Test func constructionDoesNotInspectOrRequestLocation() {
        let service = MapPresentationLocationService()
        _ = makeModel(service)
        #expect(service.authorizationCalls == 0)
        #expect(service.positionCalls == 0)
    }

    @Test func firstEntryRequestsUndeterminedPositionAndFocusesAfterGrant() async throws {
        let service = MapPresentationLocationService(status: .notDetermined)
        service.authorizationAfterRequest = MapPresentationLocationService.allowed
        let position = try makePosition()
        service.immediateResult = .success(position)
        let model = makeModel(service)

        #expect(await model.activate() == nil)
        #expect(service.positionCalls == 1)
        #expect(model.locationFocus?.coordinate == position.coordinate)
        #expect(model.showsUserLocation)
        #expect(!model.isLocating)
    }

    @Test func passiveEntryDoesNotRepeatDeniedPermissionOrShowAlert() async {
        let service = MapPresentationLocationService()
        let model = makeModel(service)
        #expect(await model.activate() == nil)
        #expect(service.positionCalls == 0)
        #expect(!model.permissionAlertPresented)
        #expect(!model.showsUserLocation)
        #expect(await model.recenter() == .permissionDenied)
        #expect(service.positionCalls == 0)
    }

    @Test func denialOfInitialPromptRemainsSilentUntilExplicitRecenter() async {
        let service = MapPresentationLocationService(status: .notDetermined)
        service.authorizationAfterRequest = MapPresentationLocationService.denied
        service.immediateResult = .failure(.permissionDenied)
        let model = makeModel(service)

        #expect(await model.activate() == nil)
        #expect(service.positionCalls == 1)
        #expect(!model.permissionAlertPresented)
        #expect(await model.recenter() == .permissionDenied)
        #expect(service.positionCalls == 1)
    }

    @Test func returnToMapPreservesCameraAndDoesNotAcquireAgain() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        service.immediateResult = .success(try makePosition())
        let model = makeModel(service)
        _ = await model.activate()
        let focus = try #require(model.locationFocus)
        model.focusCamera(on: focus)
        let camera = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: 80),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.3)
        )
        model.cameraPosition = .region(camera)
        model.userDidChangeCamera()
        model.deactivate()

        #expect(await model.activate() == nil)
        #expect(service.positionCalls == 1)
        #expect(model.locationFocus == focus)
        #expect(model.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(model.cameraPosition.region?.span.longitudeDelta == camera.span.longitudeDelta)
        #expect(model.showsUserLocation)
    }

    @Test func explicitRecenterAcquiresAgainAndOverridesUserPan() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        service.immediateResult = .success(try makePosition())
        let model = makeModel(service)
        _ = await model.activate()
        let previousFocus = model.locationFocus
        model.userDidChangeCamera()
        let updated = try makePosition(latitude: 11)
        service.immediateResult = .success(updated)

        #expect(await model.recenter() == nil)
        #expect(service.positionCalls == 2)
        #expect(model.locationFocus?.coordinate == updated.coordinate)
        #expect(model.locationFocus != previousFocus)
    }

    @Test func panWhileInitialFixIsPendingPreventsLateAutomaticCameraJump() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let model = makeModel(service)
        let request = Task { await model.activate() }
        await service.waitForPositionRequest(1)
        model.userDidChangeCamera()
        service.complete(1, with: .success(try makePosition()))

        #expect(await request.value == nil)
        #expect(model.locationFocus == nil)
        #expect(model.showsUserLocation)
    }

    @Test func repeatedRecenterRequestsAreCoalescedWhileAcquiring() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let model = makeModel(service)
        let request = Task { await model.activate() }
        await service.waitForPositionRequest(1)
        model.requestRecenter()
        model.requestRecenter()
        #expect(!model.hasPendingRecenterRequest)
        #expect(await model.recenter() == nil)
        #expect(service.positionCalls == 1)
        service.complete(1, with: .success(try makePosition()))
        _ = await request.value

        model.requestRecenter()
        model.requestRecenter()
        service.immediateResult = .success(try makePosition())
        #expect(await model.performPendingRecenter() == nil)
        #expect(await model.performPendingRecenter() == nil)
        #expect(service.positionCalls == 2)
    }

    @Test func cancelledOldActivationCannotOverwriteNewActivation() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let model = makeModel(service)
        let old = Task { await model.activate() }
        await service.waitForPositionRequest(1)
        old.cancel()
        model.deactivate()
        #expect(!model.showsUserLocation)
        let replacement = Task { await model.activate() }
        await service.waitForPositionRequest(2)
        let fresh = try makePosition(latitude: 12)
        service.complete(2, with: .success(fresh))
        _ = await replacement.value
        let accepted = model.locationFocus
        service.complete(1, with: .success(try makePosition(latitude: 13)))

        #expect(await old.value == nil)
        #expect(model.locationFocus == accepted)
        #expect(model.locationFocus?.coordinate == fresh.coordinate)
        #expect(!model.isLocating)
    }

    @Test func pendingRequestAfterDepartureCannotShowFailure() async {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let model = makeModel(service)
        let request = Task { await model.activate() }
        await service.waitForPositionRequest(1)
        model.deactivate()
        service.complete(1, with: .failure(.timedOut))
        #expect(await request.value == nil)
        #expect(!model.isLocating)
        #expect(!model.showsUserLocation)
        #expect(model.locationFocus == nil)
    }

    @Test(arguments: [LocationServiceError.timedOut, .positionUnavailable, .stalePosition])
    func permittedFailureShowsToastAndKeepsAuthorizedUserAnnotation(_ error: LocationServiceError) async {
        let service = MapPresentationLocationService(status: .notDetermined)
        service.authorizationAfterRequest = MapPresentationLocationService.allowed
        service.immediateResult = .failure(error)
        let model = makeModel(service)
        let issue: MapLocationIssue = error == .timedOut ? .timedOut : .unavailable

        #expect(await model.activate() == .toast(issue))
        #expect(model.showsUserLocation)
        #expect(!model.permissionAlertPresented)
    }

    @Test func restrictedAndDisabledServicesShowDistinctToastsWithoutRequest() async {
        let restricted = MapPresentationLocationService(status: .restricted)
        #expect(await makeModel(restricted).activate() == .toast(.restricted))
        #expect(restricted.positionCalls == 0)
        let disabled = MapPresentationLocationService(status: .authorizedWhenInUse, servicesEnabled: false)
        #expect(await makeModel(disabled).activate() == .toast(.servicesDisabled))
        #expect(disabled.positionCalls == 0)
    }

    /// AC-37 / D-03: device-wide disabled services take precedence over per-app denial.
    /// A Settings permission alert cannot fix a globally disabled location service.
    @Test(arguments: [LocationAuthorizationStatus.denied, .restricted, .notDetermined, .authorizedWhenInUse])
    func disabledServicesShowToastOnEntryAndRecenterWithoutRequest(_ status: LocationAuthorizationStatus) async {
        let service = MapPresentationLocationService(status: status, servicesEnabled: false)
        let model = makeModel(service)
        let retainedCamera = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: 80),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.3)
        )
        model.cameraPosition = .region(retainedCamera)

        #expect(await model.activate() == .toast(.servicesDisabled))
        #expect(await model.recenter() == .toast(.servicesDisabled))
        #expect(service.positionCalls == 0)
        #expect(!model.permissionAlertPresented)
        #expect(!model.showsUserLocation)
        #expect(model.locationFocus == nil)
        #expect(model.cameraPosition.region?.center.latitude == retainedCamera.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == retainedCamera.center.longitude)
        #expect(model.cameraPosition.region?.span.latitudeDelta == retainedCamera.span.latitudeDelta)
        #expect(model.cameraPosition.region?.span.longitudeDelta == retainedCamera.span.longitudeDelta)
    }

    @Test func reducedAccuracyIsAcceptedForFocus() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let position = try makePosition(accuracy: .reduced)
        service.immediateResult = .success(position)
        let model = makeModel(service)
        #expect(await model.activate() == nil)
        #expect(model.locationFocus?.coordinate == position.coordinate)
        #expect(model.showsUserLocation)
    }

    private func makeModel(_ service: MapPresentationLocationService) -> MapViewModel {
        MapViewModel(router: .init(root: .root), deviceLocationService: service)
    }

    private func makePosition(
        latitude: Double = 10,
        accuracy: LocationAccuracyAuthorization = .full
    ) throws -> DevicePosition {
        try DevicePosition(
            coordinate: Coordinate(latitude: latitude, longitude: 106),
            timestamp: Date(timeIntervalSinceReferenceDate: 100),
            horizontalAccuracyMetres: 10,
            authorization: LocationAuthorization(
                status: .authorizedWhenInUse, accuracy: accuracy, servicesEnabled: true
            )
        )
    }
}

/// Intentionally ignores cancellation so tests can deterministically deliver stale completions.
@MainActor
final class MapPresentationLocationService: DeviceLocationService {
    static let allowed = LocationAuthorization(
        status: .authorizedWhenInUse, accuracy: .full, servicesEnabled: true
    )
    static let denied = LocationAuthorization(status: .denied, accuracy: .full, servicesEnabled: true)

    var snapshot: LocationAuthorization
    var authorizationAfterRequest: LocationAuthorization?
    var immediateResult: Result<DevicePosition, LocationServiceError>?
    private(set) var authorizationCalls = 0
    private(set) var positionCalls = 0
    private var pending: [Int: CheckedContinuation<Result<DevicePosition, LocationServiceError>, Never>] = [:]
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(status: LocationAuthorizationStatus = .denied, servicesEnabled: Bool = true) {
        snapshot = LocationAuthorization(status: status, accuracy: .full, servicesEnabled: servicesEnabled)
    }

    @MainActor func authorization() async -> LocationAuthorization {
        authorizationCalls += 1
        return snapshot
    }

    @MainActor func currentPosition() async throws(LocationServiceError) -> DevicePosition {
        positionCalls += 1
        if let authorizationAfterRequest { snapshot = authorizationAfterRequest }
        let waiters = requestWaiters.filter { $0.0 <= positionCalls }
        requestWaiters.removeAll { $0.0 <= positionCalls }
        if let immediateResult {
            for (_, waiter) in waiters { waiter.resume() }
            return try immediateResult.get()
        }
        let index = positionCalls
        let result: Result<DevicePosition, LocationServiceError> = await withCheckedContinuation { continuation in
            pending[index] = continuation
            for (_, waiter) in waiters { waiter.resume() }
        }
        return try result.get()
    }

    func waitForPositionRequest(_ count: Int) async {
        guard positionCalls < count else { return }
        await withCheckedContinuation { requestWaiters.append((count, $0)) }
    }

    func complete(_ request: Int, with result: Result<DevicePosition, LocationServiceError>) {
        pending.removeValue(forKey: request)?.resume(returning: result)
    }
}
