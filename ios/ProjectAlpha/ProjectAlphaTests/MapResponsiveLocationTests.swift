//
//  MapResponsiveLocationTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/10/26.
//

import Foundation
import MapKit
import SwiftUI
import Testing
@testable import ProjectAlpha

/// P-06, AC-37, U-07/U-10, D-01/D-03: approved 30-second session reuse.
/// Provider continuations and an injected clock establish ordering without GPS or sleeps.
@MainActor
struct MapResponsiveLocationTests {
    /// AC-37: 30 seconds is inclusive; a future timestamp or older session fix
    /// cannot remove loading before the one-shot provider responds.
    @Test(arguments: [0.0, 30.0, 30.001, -0.001])
    func sessionReuseHasInclusiveNonfutureThirtySecondBoundary(age: Double) async throws {
        let (model, service, cached) = try await seededModel(age: age)
        let candidate = try makeCandidate()
        model.selectSearchCandidate(candidate)
        let candidateCamera = try #require(model.cameraPosition.region)
        let request = Task { await model.recenter() }
        await service.waitForPositionRequest(2)

        let reusable = age >= 0 && age <= 30
        #expect(model.isLocating == !reusable)
        #expect(model.visiblePlace?.id == (reusable ? .currentPosition : .searchCandidate(candidate.id)))
        if reusable {
            #expect(model.locationFocus?.coordinate == cached.coordinate)
            applyFocusAsMapView(model)
            #expect(model.cameraPosition.region?.center.latitude == cached.coordinate.latitude)
        } else {
            #expect(model.cameraPosition.region?.center.latitude == candidateCamera.center.latitude)
        }

        let refreshed = try makePosition(latitude: 12, age: 0)
        service.complete(2, with: .success(refreshed))
        #expect(await request.value == nil)
        #expect(model.visiblePlace?.coordinate == refreshed.coordinate)
        #expect(!model.isLocating)
    }

    /// AC-37: when no previous fix exists, keep acquisition feedback until a
    /// provider fix arrives; session reuse does not impose an age filter on it.
    @Test func noKnownFixLoadsAndAcceptsOtherwiseValidOldProviderFix() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let model = makeModel(service)
        let request = Task { await model.activate() }
        await service.waitForPositionRequest(1)
        #expect(model.isLocating)
        #expect(model.visiblePlace == nil)
        let oldProviderFix = try makePosition(age: 3_600)
        service.complete(1, with: .success(oldProviderFix))
        #expect(await request.value == nil)
        #expect(model.currentPosition == oldProviderFix)
        #expect(model.visiblePlace?.timestamp == oldProviderFix.timestamp)
        #expect(!model.isLocating)
    }

    /// AC-37/D-03: an earlier pan does not prevent a new explicit action; a pan
    /// or zoom after that action preserves the user's camera when refresh arrives.
    @Test(arguments: [false, true])
    func refreshUpdatesCardAndPreservesOnlyPostActionCameraMovement(panAfterAction: Bool) async throws {
        let (model, service, cached) = try await seededModel(age: 10)
        model.cameraPosition = .region(Self.userCamera)
        model.userDidChangeCamera()
        let request = Task { await model.recenter() }
        await service.waitForPositionRequest(2)
        #expect(model.locationFocus?.coordinate == cached.coordinate)
        applyFocusAsMapView(model)
        #expect(model.cameraPosition.region?.center.latitude == cached.coordinate.latitude)
        #expect(!model.isLocating)
        model.showDetails()
        if panAfterAction {
            model.cameraPosition = .region(Self.userCamera)
            model.userDidChangeCamera()
        }
        let focusBeforeRefresh = model.locationFocus
        let updated = try makePosition(latitude: 12, age: 0, accuracy: 75, reduced: true)
        service.complete(2, with: .success(updated))
        #expect(await request.value == nil)
        #expect(model.currentPosition == updated)
        #expect(model.visiblePlace?.id == .currentPosition)
        #expect(model.visiblePlace?.coordinate == updated.coordinate)
        #expect(model.visiblePlace?.timestamp == updated.timestamp)
        #expect(model.visiblePlace?.horizontalAccuracyMetres == updated.horizontalAccuracyMetres)
        #expect(model.selectedDetail?.coordinate == updated.coordinate)
        #expect(model.selectedDetail?.timestamp == updated.timestamp)
        if panAfterAction {
            #expect(model.locationFocus == focusBeforeRefresh)
            assertCamera(model, matches: Self.userCamera)
        } else {
            #expect(model.locationFocus?.coordinate == updated.coordinate)
        }
    }

    /// AC-37: timeout is visible feedback without discarding the already usable
    /// position card or reactivating loading after immediate session reuse.
    @Test func timeoutKeepsReusablePositionAndCameraWithToast() async throws {
        let (model, service, cached) = try await seededModel(age: 30)
        model.selectSearchCandidate(try makeCandidate())
        let request = Task { await model.recenter() }
        await service.waitForPositionRequest(2)
        applyFocusAsMapView(model)
        let camera = try #require(model.cameraPosition.region)
        #expect(!model.isLocating)
        model.showDetails()
        service.complete(2, with: .failure(.timedOut))
        #expect(await request.value == .toast(.timedOut))
        #expect(model.currentPosition == cached)
        #expect(model.visiblePlace?.id == .currentPosition)
        #expect(model.selectedDetail?.coordinate == cached.coordinate)
        #expect(model.showsUserLocation)
        #expect(!model.isLocating)
        assertCamera(model, matches: camera)
    }

    /// AC-37: current permission/services take precedence over a fresh cached
    /// fix. A failed preflight cannot replace a selected candidate or camera.
    @Test(arguments: [LocationAuthorizationStatus.denied, .restricted, .authorizedWhenInUse])
    func unavailableAuthorizationPreventsReuseAndProviderRequest(status: LocationAuthorizationStatus) async throws {
        let (model, service, cached) = try await seededModel(age: 0)
        let candidate = try makeCandidate()
        model.selectSearchCandidate(candidate)
        let camera = try #require(model.cameraPosition.region)
        service.snapshot = LocationAuthorization(
            status: status, accuracy: .full, servicesEnabled: status != .authorizedWhenInUse
        )
        let expected: MapLocationOutcome = switch status {
        case .denied: .permissionDenied
        case .restricted: .toast(.restricted)
        default: .toast(.servicesDisabled)
        }
        #expect(await model.recenter() == expected)
        #expect(service.positionCalls == 1)
        #expect(service.authorizationCalls == 2)
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(model.currentPosition == cached)
        #expect(!model.showsUserLocation)
        #expect(!model.isLocating)
        assertCamera(model, matches: camera)
    }

    /// AC-37/D-01: a nonloading cache refresh still coalesces repeated actions;
    /// the next action becomes available only after the pending request ends.
    @Test func repeatedActionsCoalesceWhileNonloadingRefreshIsPending() async throws {
        let (model, service, _) = try await seededModel(age: 0)
        let request = Task { await model.recenter() }
        await service.waitForPositionRequest(2)
        #expect(!model.isLocating)
        model.requestRecenter()
        model.requestRecenter()
        #expect(!model.hasPendingRecenterRequest)
        #expect(await model.recenter() == nil)
        #expect(service.positionCalls == 2)
        service.complete(2, with: .success(try makePosition(latitude: 12)))
        #expect(await request.value == nil)
        model.requestRecenter()
        #expect(model.hasPendingRecenterRequest)
        service.immediateResult = .success(try makePosition(latitude: 13))
        #expect(await model.performPendingRecenter() == nil)
        #expect(service.positionCalls == 3)
        #expect(!model.hasPendingRecenterRequest)
        #expect(model.currentPosition?.coordinate.latitude == 13)
    }

    /// AC-37/D-03: a newly selected candidate supersedes an in-flight cache
    /// refresh even when its provider ignores cancellation.
    @Test func selectedCandidateSuppressesLateRefresh() async throws {
        let (model, service, cached) = try await seededModel(age: 0)
        let request = Task { await model.recenter() }
        await service.waitForPositionRequest(2)
        let candidate = try makeCandidate()
        model.selectSearchCandidate(candidate)
        model.showDetails()
        let camera = try #require(model.cameraPosition.region)
        service.complete(2, with: .success(try makePosition(latitude: 12)))
        #expect(await request.value == nil)
        #expect(model.currentPosition == cached)
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(model.selectedDetail?.id == .searchCandidate(candidate.id))
        #expect(!model.isLocating)
        assertCamera(model, matches: camera)
    }

    /// AC-37/D-03: departure invalidates refresh. A later action can succeed,
    /// and the older completion cannot overwrite it or expose stale feedback.
    @Test func cancelledRefreshCannotOverwriteReplacementAfterReactivation() async throws {
        let (model, service, _) = try await seededModel(age: 0)
        let obsolete = Task { await model.recenter() }
        await service.waitForPositionRequest(2)
        obsolete.cancel()
        model.deactivate()
        #expect(!model.showsUserLocation)
        #expect(await model.activate() == nil)
        let replacement = Task { await model.recenter() }
        await service.waitForPositionRequest(3)
        let fresh = try makePosition(latitude: 12)
        service.complete(3, with: .success(fresh))
        #expect(await replacement.value == nil)
        let camera = try #require(model.cameraPosition.region)
        service.complete(2, with: .success(try makePosition(latitude: 13)))
        #expect(await obsolete.value == nil)
        #expect(model.currentPosition == fresh)
        #expect(model.visiblePlace?.coordinate == fresh.coordinate)
        #expect(model.showsUserLocation)
        #expect(!model.isLocating)
        assertCamera(model, matches: camera)
    }

    /// AC-37/58, INV-09: repeated compact/regular and RTL geometry changes
    /// during cache refresh preserve the current card, detail and logical camera.
    @Test func resizingDuringCacheRefreshPreservesCardDetailAndCamera() async throws {
        let (model, service, cached) = try await seededModel(age: 0)
        let request = Task { await model.recenter() }
        await service.waitForPositionRequest(2)
        applyFocusAsMapView(model)
        model.showDetails()
        let camera = try #require(model.cameraPosition.region)
        for (width, height, leading) in [(400.0, 700.0, true), (1000.0, 600.0, false), (400.0, 700.0, true)] {
            model.setFocusViewport(
                width: width, height: height, cardWidth: 300, cardHeight: 250,
                cardAtLeading: false, leadingIsPhysicalLeft: leading
            )
            #expect(model.visiblePlace?.coordinate == cached.coordinate)
            #expect(model.selectedDetail?.id == .currentPosition)
            #expect(!model.isLocating)
            assertCamera(model, matches: camera)
        }
        service.complete(2, with: .failure(.timedOut))
        #expect(await request.value == .toast(.timedOut))
    }

    /// AC-37/INV-09: authorization preflight on return or explicit fresh reuse
    /// does not flash acquisition feedback over an already usable card.
    @Test(arguments: [false, true])
    func delayedAuthorizationPreservesUsableCardWithoutSpinner(explicit: Bool) async throws {
        let (model, service, cached) = try await seededModel(age: 0)
        let camera = try #require(model.cameraPosition.region)
        service.suspendsAuthorization = true
        let request = Task { explicit ? await model.recenter() : await model.activate() }
        await service.waitForAuthorization(2)
        #expect(!model.isLocating)
        #expect(model.visiblePlace?.id == .currentPosition)
        #expect(model.currentPosition == cached)
        assertCamera(model, matches: camera)
        #expect(service.positionCalls == 1)
        #expect(await model.recenter() == nil) // Preflight itself reserves the request.
        #expect(service.authorizationCalls == 2)
        service.completeAuthorization(2)
        if explicit {
            await service.waitForPositionRequest(2)
            #expect(!model.isLocating)
            service.complete(2, with: .success(try makePosition(latitude: 12)))
        }
        #expect(await request.value == nil)
        #expect(service.positionCalls == (explicit ? 2 : 1))
        #expect(!model.isLocating)
    }

    /// AC-37/INV-09: deactivation during preflight cancels its ownership; a late
    /// authorization response cannot acquire location or replace a retained card.
    @Test func deactivationDuringAuthorizationRejectsLatePreflight() async throws {
        let (model, service, cached) = try await seededModel(age: 0)
        service.suspendsAuthorization = true
        let request = Task { await model.recenter() }
        await service.waitForAuthorization(2)
        model.deactivate()
        service.completeAuthorization(2)
        #expect(await request.value == nil)
        #expect(service.positionCalls == 1)
        #expect(model.currentPosition == cached)
        #expect(!model.isLocating)
        #expect(!model.showsUserLocation)
    }

    private static let now = Date(timeIntervalSinceReferenceDate: 10_000)
    private static let candidateName = "Responsive Location Candidate"
    private static let userCamera = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40, longitude: 80),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.3)
    )

    private func makeModel(_ service: MapPresentationLocationService) -> MapViewModel {
        MapViewModel(
            deviceLocationService: service,
            positionClock: { Self.now }
        )
    }

    private func seededModel(age: Double) async throws -> (MapViewModel, MapPresentationLocationService, DevicePosition) {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let position = try makePosition(age: age)
        service.immediateResult = .success(position)
        let model = makeModel(service)
        #expect(await model.activate() == nil)
        applyFocusAsMapView(model)
        service.immediateResult = nil
        return (model, service, position)
    }

    private func makePosition(latitude: Double = 10, age: Double = 0, accuracy: Double = 10, reduced: Bool = false) throws -> DevicePosition {
        try DevicePosition(
            coordinate: Coordinate(latitude: latitude, longitude: 106),
            timestamp: Self.now.addingTimeInterval(-age), horizontalAccuracyMetres: accuracy,
            authorization: LocationAuthorization(
                status: .authorizedWhenInUse, accuracy: reduced ? .reduced : .full, servicesEnabled: true
            )
        )
    }

    private func makeCandidate() throws -> PlaceCandidate {
        PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: nil,
            name: Self.candidateName, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 21, longitude: 105)
        )
    }

    private func assertCamera(_ model: MapViewModel, matches camera: MKCoordinateRegion) {
        #expect(model.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == camera.center.longitude)
        #expect(model.cameraPosition.region?.span.latitudeDelta == camera.span.latitudeDelta)
        #expect(model.cameraPosition.region?.span.longitudeDelta == camera.span.longitudeDelta)
    }

    /// MapView consumes this public focus intent in onChange. This models that
    /// boundary deterministically; first-frame/animation timing needs UI evidence.
    private func applyFocusAsMapView(_ model: MapViewModel) {
        if let focus = model.locationFocus { model.focusCamera(on: focus) }
    }
}
