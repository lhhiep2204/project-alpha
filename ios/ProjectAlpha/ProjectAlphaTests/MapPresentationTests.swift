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
import UIKit
import Vision
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

    /// AC-67, U-32, D-21: a first valid device fix uses a street-level scale.
    @Test func firstPositionFocusUsesPointScale() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        service.immediateResult = .success(try makePosition())
        let model = makeModel(service)
        _ = await model.activate()
        model.focusCamera(on: try #require(model.locationFocus))
        let first = try #require(model.cameraPosition.region)
        #expect(first.span.latitudeDelta > 0)
        #expect(first.span.latitudeDelta < 0.1)
        #expect(first.center.latitude == model.currentPosition?.coordinate.latitude)
    }

    /// AC-67, U-32, D-21: each newly selected place applies its own scale,
    /// including after a user manually zoomed the preceding selection.
    @Test func selectedPlaceScaleTracksGeographicKindAfterManualZoom() throws {
        let model = makeModel(MapPresentationLocationService())
        let point = try makeCandidate(kind: .point)
        model.selectSearchCandidate(point)
        let pointSpan = try #require(model.cameraPosition.region?.span.latitudeDelta)
        model.cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30, longitude: 40),
            span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
        ))
        model.userDidChangeCamera()
        #expect(model.cameraPosition.region?.span.latitudeDelta == 2)

        let city = try makeCandidate(kind: .city)
        model.selectSearchCandidate(city)
        let citySpan = try #require(model.cameraPosition.region?.span.latitudeDelta)
        let region = try makeCandidate(kind: .region)
        model.selectSearchCandidate(region)
        let regionSpan = try #require(model.cameraPosition.region?.span.latitudeDelta)
        #expect(pointSpan < citySpan && citySpan < regionSpan)
        #expect(model.visiblePlace?.id == .searchCandidate(region.id))

        model.selectSearchCandidate(point)
        #expect(model.cameraPosition.region?.span.latitudeDelta == pointSpan)
        #expect(model.visiblePlace?.id == .searchCandidate(point.id))
    }

    /// AC-67, U-32, D-21: a regional 8-degree camera is too far out for a
    /// newly selected place whose kind is unknown, so focus returns to near.
    @Test func unknownSelectionAfterRegionFocusFallsBackToNearScale() throws {
        let model = makeModel(MapPresentationLocationService())
        model.selectSearchCandidate(try makeCandidate(kind: .region))
        let regionSpan = try #require(model.cameraPosition.region?.span.latitudeDelta)
        #expect(regionSpan > 2)

        let unknown = try makeCandidate(kind: .unknown)
        model.selectSearchCandidate(unknown)
        let focused = try #require(model.cameraPosition.region)
        #expect(focused.span.latitudeDelta > 0 && focused.span.latitudeDelta < 0.1)
        #expect(focused.span.longitudeDelta > 0 && focused.span.longitudeDelta < 0.1)
        #expect(focused.center.latitude == unknown.coordinate.latitude)
        #expect(model.visiblePlace?.id == .searchCandidate(unknown.id))
    }

    /// AC-67, U-32, D-21: an unclassified result moves into view without
    /// discarding a useful user scale; the initial world view gains a near scale.
    @Test func unknownPlaceRetainsUsefulZoomAndWorldViewFallsNear() throws {
        let model = makeModel(MapPresentationLocationService())
        let candidate = try makeCandidate(kind: .unknown)
        model.cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30, longitude: 40),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.3)
        ))
        model.userDidChangeCamera()
        model.selectSearchCandidate(candidate)
        #expect(model.cameraPosition.region?.span.latitudeDelta == 0.2)
        #expect(model.cameraPosition.region?.span.longitudeDelta == 0.3)
        #expect(model.cameraPosition.region?.center.latitude == candidate.coordinate.latitude)

        let world = makeModel(MapPresentationLocationService())
        world.selectSearchCandidate(candidate)
        let fallback = try #require(world.cameraPosition.region?.span.latitudeDelta)
        #expect(fallback > 0 && fallback < 0.1)

        let continent = makeModel(MapPresentationLocationService())
        continent.cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30, longitude: 40),
            span: MKCoordinateSpan(latitudeDelta: 25, longitudeDelta: 25)
        ))
        continent.selectSearchCandidate(candidate)
        #expect((continent.cameraPosition.region?.span.latitudeDelta ?? .infinity) < 0.1)
    }

    /// AC-67, D-21: MapKit can expose the last user viewport separately from
    /// the camera binding, so an unknown place still keeps that useful scale.
    @Test func unknownPlaceUsesLastRecordedVisibleRegionWhenCameraHasNoRegion() throws {
        let model = makeModel(MapPresentationLocationService())
        let visible = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30, longitude: 40),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.3)
        )
        model.recordVisibleRegion(visible)
        #expect(model.cameraPosition.region == nil)
        let candidate = try makeCandidate(kind: .unknown)
        model.selectSearchCandidate(candidate)
        #expect(model.cameraPosition.region?.span.latitudeDelta == visible.span.latitudeDelta)
        #expect(model.cameraPosition.region?.span.longitudeDelta == visible.span.longitudeDelta)
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
    }

    @Test func passiveEntryDoesNotRepeatDeniedPermissionOrShowAlert() async {
        let service = MapPresentationLocationService()
        let model = makeModel(service)
        #expect(await model.activate() == nil)
        #expect(service.positionCalls == 0)
        #expect(!model.permissionAlertPresented)
        #expect(!model.showsUserLocation)
        #expect(model.visiblePlace == nil)
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
        #expect(model.visiblePlace == nil)
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
        model.cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: 80),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
        ))
        model.userDidChangeCamera()
        let updated = try makePosition(latitude: 11)
        service.immediateResult = .success(updated)

        #expect(await model.recenter() == nil)
        #expect(service.positionCalls == 2)
        #expect(model.locationFocus?.coordinate == updated.coordinate)
        #expect(model.locationFocus != previousFocus)
        model.focusCamera(on: try #require(model.locationFocus))
        #expect((model.cameraPosition.region?.span.latitudeDelta ?? .infinity) < 0.1)
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
        #expect(model.visiblePlace?.coordinate == fresh.coordinate)
        #expect(model.visiblePlace?.id == .currentPosition)
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
        #expect(model.visiblePlace == nil)
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
        #expect(model.visiblePlace == nil)
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

    /// AC-37/24, INV-09: a valid first fix publishes a persistent quick card even
    /// when a user pan prevents the passive camera jump.
    @Test func initialFixPublishesCurrentCardAfterUserPan() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let model = makeModel(service)
        let acquisition = Task { await model.activate() }
        await service.waitForPositionRequest(1)
        let retainedCamera = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: 80),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.3)
        )
        model.cameraPosition = .region(retainedCamera)
        model.userDidChangeCamera()
        let fix = try makePosition(accuracy: .reduced)
        service.complete(1, with: .success(fix))

        #expect(await acquisition.value == nil)
        let card = try #require(model.visiblePlace)
        #expect(card.id == .currentPosition)
        #expect(card.coordinate == fix.coordinate)
        #expect(card.timestamp == fix.timestamp)
        #expect(card.horizontalAccuracyMetres == fix.horizontalAccuracyMetres)
        #expect(card.isCurrentPosition)
        #expect(model.locationFocus == nil)
        #expect(model.cameraPosition.region?.center.latitude == retainedCamera.center.latitude)
        model.showDetails()
        #expect(model.selectedDetail == card)
    }

    /// AC-18/24/37, INV-09: Search X restores the latest current-position card
    /// and requests camera focus on that exact fix without reacquiring GPS.
    @Test func dismissingCandidateRestoresCurrentCardAndCameraFocus() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let fix = try makePosition()
        service.immediateResult = .success(fix)
        let model = makeModel(service)
        _ = await model.activate()
        let candidate = try makeCandidate()
        model.selectSearchCandidate(candidate)
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(model.visiblePlace?.name == MapCardFixture.name)
        #expect(model.visiblePlace?.address == MapCardFixture.address)
        #expect(model.visiblePlace?.coordinate == candidate.coordinate)
        model.showDetails()
        #expect(model.selectedDetail?.id == .searchCandidate(candidate.id))

        model.dismissSearchCandidate()
        #expect(model.selectedCandidate == nil)
        #expect(model.visiblePlace?.id == .currentPosition)
        #expect(model.visiblePlace?.coordinate == fix.coordinate)
        #expect(model.locationFocus?.coordinate == fix.coordinate)
        model.focusCamera(on: try #require(model.locationFocus))
        #expect((model.cameraPosition.region?.span.latitudeDelta ?? .infinity) < 0.1)
        #expect(model.selectedDetail == nil)
        #expect(service.positionCalls == 1)
    }

    /// AC-18/24: without a valid current fix, Search X removes the card and
    /// leaves the user's current camera untouched.
    @Test func dismissingCandidateWithoutFixHidesCardAndRetainsCamera() throws {
        let model = makeModel(MapPresentationLocationService())
        let candidate = try makeCandidate()
        model.selectSearchCandidate(candidate)
        let camera = model.cameraPosition.region
        model.dismissSearchCandidate()

        #expect(model.visiblePlace == nil)
        #expect(model.locationFocus == nil)
        #expect(model.cameraPosition.region?.center.latitude == camera?.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == camera?.center.longitude)
    }

    /// AC-24/37, INV-09: an explicit failed recenter preserves the candidate;
    /// a later successful request replaces it with the new current-position card.
    @Test func recenterReplacesCandidateOnlyAfterSuccessfulFix() async throws {
        let service = MapPresentationLocationService(status: .authorizedWhenInUse)
        let first = try makePosition()
        service.immediateResult = .success(first)
        let model = makeModel(service)
        _ = await model.activate()
        let candidate = try makeCandidate()
        model.selectSearchCandidate(candidate)
        let retainedCamera = model.cameraPosition.region
        service.immediateResult = .failure(.timedOut)

        #expect(await model.recenter() == .toast(.timedOut))
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(model.currentPosition == first)
        #expect(model.cameraPosition.region?.center.latitude == retainedCamera?.center.latitude)

        let second = try makePosition(latitude: 11)
        service.immediateResult = .success(second)
        #expect(await model.recenter() == nil)
        #expect(model.selectedCandidate == nil)
        #expect(model.visiblePlace?.id == .currentPosition)
        #expect(model.visiblePlace?.coordinate == second.coordinate)
        #expect(model.locationFocus?.coordinate == second.coordinate)
        #expect(service.positionCalls == 3)
    }

    /// AC-24/37, D-03: address enrichment is metadata for the exact GPS fix;
    /// a candidate selected before the response remains the visible card.
    @Test func lateAddressEnrichmentCannotReplaceSelectedCandidate() async throws {
        let location = MapPresentationLocationService(status: .authorizedWhenInUse)
        let fix = try makePosition()
        location.immediateResult = .success(fix)
        let geocoder = MapCardReverseGeocoder()
        let model = MapViewModel(router: .init(root: .root), deviceLocationService: location,
                                 reverseGeocodingService: geocoder)
        _ = await model.activate()
        let request = await geocoder.waitForRequest(1)
        #expect(request.coordinate == fix.coordinate)
        let candidate = try makeCandidate()
        model.selectSearchCandidate(candidate)
        await geocoder.complete(1, address: MapCardFixture.address)
        await model.awaitPendingAddressEnrichment()

        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(model.visiblePlace?.address == candidate.address)
        #expect(model.currentPosition == fix)
    }

    /// AC-24/37, D-03: a superseded reverse-geocode result cannot assign the
    /// old address to a newer fix, even when the provider ignores cancellation.
    @Test func lateOldAddressCannotReplaceNewCurrentPosition() async throws {
        let location = MapPresentationLocationService(status: .authorizedWhenInUse)
        let first = try makePosition()
        location.immediateResult = .success(first)
        let geocoder = MapCardReverseGeocoder()
        let model = MapViewModel(router: .init(root: .root), deviceLocationService: location,
                                 reverseGeocodingService: geocoder)
        _ = await model.activate()
        let oldRequest = await geocoder.waitForRequest(1)
        #expect(oldRequest.coordinate == first.coordinate)

        let second = try makePosition(latitude: 11)
        location.immediateResult = .success(second)
        #expect(await model.recenter() == nil)
        let newRequest = await geocoder.waitForRequest(2)
        #expect(newRequest.coordinate == second.coordinate)
        #expect(newRequest.generation != oldRequest.generation)
        await geocoder.complete(1, address: MapCardFixture.oldAddress)
        await geocoder.complete(2, address: MapCardFixture.newAddress)
        await model.awaitPendingAddressEnrichment()

        #expect(model.visiblePlace?.id == .currentPosition)
        #expect(model.visiblePlace?.coordinate == second.coordinate)
        #expect(model.visiblePlace?.address == MapCardFixture.newAddress)
        #expect(model.currentAddress == MapCardFixture.newAddress)
    }

    /// AC-24/37/60, D-03: a locale switch immediately removes old-language
    /// metadata from both visible surfaces; lookup failure leaves it absent.
    @Test func localeChangeClearsOpenCurrentDetailAddressEvenWhenLookupFails() async throws {
        let location = MapPresentationLocationService(status: .authorizedWhenInUse)
        location.immediateResult = .success(try makePosition())
        let geocoder = MapCardReverseGeocoder()
        let model = MapViewModel(router: .init(root: .root), deviceLocationService: location,
                                 reverseGeocodingService: geocoder)
        model.updateAddressLocale(MapCardFixture.firstLocale)
        _ = await model.activate()
        let initialRequest = await geocoder.waitForRequest(1)
        #expect(initialRequest.localeIdentifier == MapCardFixture.firstLocale)
        await geocoder.complete(1, address: MapCardFixture.oldAddress)
        await model.awaitPendingAddressEnrichment()
        model.showDetails()
        #expect(model.selectedDetail?.address == MapCardFixture.oldAddress)

        model.updateAddressLocale(MapCardFixture.secondLocale)
        #expect(model.visiblePlace?.address == nil)
        #expect(model.selectedDetail?.address == nil)
        let nextRequest = await geocoder.waitForRequest(2)
        #expect(nextRequest.localeIdentifier == MapCardFixture.secondLocale)
        await geocoder.fail(2, with: .providerUnavailable)
        await model.awaitPendingAddressEnrichment()
        #expect(model.currentAddress == nil)
        #expect(model.selectedDetail?.address == nil)
        #expect(model.selectedDetail?.id == .currentPosition)
    }

    /// AC-24/57/58, INV-09: the selected coordinate remains clear of a leading
    /// card on either physical side when the available scene space changes.
    @Test func cameraFocusOffsetsAwayFromPhysicalCardSideInLTRAndRTL() throws {
        let candidate = try makeCandidate()
        let leftCard = makeModel(MapPresentationLocationService())
        leftCard.setFocusViewport(
            width: 1_000, height: 600, cardWidth: 300, cardHeight: 200,
            cardAtLeading: true, leadingIsPhysicalLeft: true
        )
        leftCard.selectSearchCandidate(candidate)
        let leftCenter = try #require(leftCard.cameraPosition.region?.center.longitude)
        #expect(leftCenter < candidate.coordinate.longitude)
        #expect(leftCard.visiblePlace?.id == .searchCandidate(candidate.id))

        let rightCard = makeModel(MapPresentationLocationService())
        rightCard.setFocusViewport(
            width: 1_000, height: 600, cardWidth: 300, cardHeight: 200,
            cardAtLeading: true, leadingIsPhysicalLeft: false
        )
        rightCard.selectSearchCandidate(candidate)
        let rightCenter = try #require(rightCard.cameraPosition.region?.center.longitude)
        #expect(rightCenter > candidate.coordinate.longitude)
        #expect(rightCard.visiblePlace?.id == .searchCandidate(candidate.id))
    }

    /// AC-67/58, D-21, INV-09: card padding near the antimeridian keeps the
    /// selected point within the wrapped visible region across a wide layout.
    @Test func wideCardOffsetWrapsAcrossAntimeridianWithoutLosingSelection() throws {
        let model = makeModel(MapPresentationLocationService())
        model.setFocusViewport(width: 1_000, height: 600, cardWidth: 300,
                               cardHeight: 200, cardAtLeading: true,
                               leadingIsPhysicalLeft: true)
        let coordinate = try Coordinate(latitude: 10, longitude: -179.9)
        let candidate = PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: nil,
            name: MapCardFixture.name, address: nil, category: nil,
            coordinate: coordinate, geographicKind: .region
        )
        model.selectSearchCandidate(candidate)
        let camera = try #require(model.cameraPosition.region)
        let wrappedDifference = abs((camera.center.longitude - coordinate.longitude + 540)
            .truncatingRemainder(dividingBy: 360) - 180)
        #expect(camera.center.longitude >= -180 && camera.center.longitude < 180)
        #expect(wrappedDifference < camera.span.longitudeDelta / 2)
        #expect(model.selectedCandidate?.id == candidate.id)
    }

    /// AC-24/60: default-size full-template measurement determines the card
    /// height, rather than all unused map height. Actual font/content rendering
    /// and sharing the measurement across card types are UI/device gates.
    @Test func mapCardUsesMeasuredFullTemplateHeightWithoutExtraEmptySpace() {
        let layout = MapCardLayout(
            size: CGSize(width: 400, height: 700), regularWidth: false,
            leadingIsPhysicalLeft: true,
            referenceCardHeight: MapCardTestMetrics.fullTemplateHeight
        )

        #expect(layout.cardHeight == MapCardTestMetrics.fullTemplateHeight)
        #expect(!layout.cardAtLeading)
        #expect(layout.cardWidth == layout.size.width - 2 * MapCardLayout.edgePadding)
        assertCardClearsMapChrome(layout)
    }

    /// AC-24/58/60: resize may constrain the same full-template height, then
    /// restore it on expansion; bottom attribution clearance never yields to
    /// content. This validates the layout budget, not the actual legal-row gap.
    @Test func referenceTemplateHeightRecalculatesForCollapseAndExpansion() {
        let portrait = MapCardLayout(
            size: CGSize(width: 400, height: 700), regularWidth: false,
            leadingIsPhysicalLeft: true,
            referenceCardHeight: MapCardTestMetrics.fullTemplateHeight
        )
        let landscape = MapCardLayout(
            size: CGSize(width: 600, height: 300), regularWidth: false,
            leadingIsPhysicalLeft: true,
            referenceCardHeight: MapCardTestMetrics.fullTemplateHeight
        )
        let expanded = MapCardLayout(
            size: portrait.size, regularWidth: portrait.regularWidth,
            leadingIsPhysicalLeft: portrait.leadingIsPhysicalLeft,
            referenceCardHeight: MapCardTestMetrics.fullTemplateHeight
        )

        #expect(landscape.cardAtLeading)
        #expect(landscape.cardHeight > 0)
        #expect(landscape.cardHeight < portrait.cardHeight)
        #expect(landscape.cardBottomInset == portrait.cardBottomInset)
        #expect(expanded == portrait)
        assertCardClearsMapChrome(portrait)
        assertCardClearsMapChrome(landscape)
    }

    /// AC-24/58, D-17: regular-width placement is leading in both text
    /// directions, with identical height, width and bottom clearance.
    @Test func referenceTemplatePlacementMirrorsWithoutChangingCardGeometry() {
        let left = MapCardLayout(
            size: CGSize(width: 1_000, height: 650), regularWidth: true,
            leadingIsPhysicalLeft: true,
            referenceCardHeight: MapCardTestMetrics.fullTemplateHeight
        )
        let right = MapCardLayout(
            size: left.size, regularWidth: true, leadingIsPhysicalLeft: false,
            referenceCardHeight: MapCardTestMetrics.fullTemplateHeight
        )

        #expect(left.cardAtLeading && right.cardAtLeading)
        #expect(left.cardWidth == right.cardWidth)
        #expect(left.cardHeight == right.cardHeight)
        #expect(left.cardHeight == MapCardTestMetrics.fullTemplateHeight)
        #expect(left.cardBottomInset == right.cardBottomInset)
        #expect(left.cardWidth + 2 * MapCardLayout.edgePadding <= left.size.width)
        assertCardClearsMapChrome(left)
        assertCardClearsMapChrome(right)
    }

    /// AC-24/60: when layout receives its default-text-size measurement,
    /// replace the provisional height with that measurement, retaining placement
    /// and bottom clearance rather than growing to fill the available map.
    @Test func fullTemplateMeasurementUpdatesOnlyCardHeight() {
        let provisional = MapCardLayout(
            size: CGSize(width: 400, height: 700), regularWidth: false,
            leadingIsPhysicalLeft: true
        )
        let measured = provisional.withReferenceCardHeight(MapCardTestMetrics.fullTemplateHeight)

        #expect(measured.cardHeight == MapCardTestMetrics.fullTemplateHeight)
        #expect(measured.cardWidth == provisional.cardWidth)
        #expect(measured.cardAtLeading == provisional.cardAtLeading)
        #expect(measured.cardBottomInset == provisional.cardBottomInset)
        assertCardClearsMapChrome(measured)
    }

    /// AC-24/58/60, INV-09: changing between compact, short and regular
    /// card geometries and RTL cannot replace the selected place, sheet data,
    /// camera center or zoom. Geometry alone must never present another sheet.
    @Test func repeatedCardGeometryChangesPreserveSelectionDetailAndCamera() throws {
        let model = makeModel(MapPresentationLocationService())
        let candidate = try makeCandidate()
        model.selectSearchCandidate(candidate)
        model.showDetails()
        let selected = try #require(model.visiblePlace)
        let camera = try #require(model.cameraPosition.region)
        let geometries: [(CGSize, Bool, Bool)] = [
            (CGSize(width: 400, height: 700), false, true),
            (CGSize(width: 600, height: 180), false, true),
            (CGSize(width: 600, height: 110), false, false),
            (CGSize(width: 1_000, height: 650), true, false),
            (CGSize(width: 400, height: 700), false, true),
        ]

        for (size, regularWidth, leadingIsPhysicalLeft) in geometries {
            let layout = MapCardLayout(
                size: size, regularWidth: regularWidth,
                leadingIsPhysicalLeft: leadingIsPhysicalLeft,
                referenceCardHeight: MapCardTestMetrics.fullTemplateHeight
            )
            model.setFocusViewport(
                width: size.width, height: size.height,
                cardWidth: layout.cardWidth + 2 * MapCardLayout.edgePadding,
                cardHeight: layout.cardHeight + layout.cardBottomInset,
                cardAtLeading: layout.cardAtLeading,
                leadingIsPhysicalLeft: leadingIsPhysicalLeft
            )
            #expect(model.visiblePlace == selected)
            #expect(model.selectedDetail == selected)
            #expect(model.selectedCandidate?.id == candidate.id)
            #expect(model.cameraPosition.region?.center.latitude == camera.center.latitude)
            #expect(model.cameraPosition.region?.center.longitude == camera.center.longitude)
            #expect(model.cameraPosition.region?.span.latitudeDelta == camera.span.latitudeDelta)
            #expect(model.cameraPosition.region?.span.longitudeDelta == camera.span.longitudeDelta)
        }
    }

    /// AC-24/37/60, D-17: at normal text size the short card must render
    /// coordinates, both position facts and both actions for the reported address.
    /// This is offscreen content evidence; glass, hit targets and map placement
    /// still require the independent device gate.
    @Test func shortCurrentPositionCardRendersAllFactsAndActions() throws {
        try assertCurrentPositionCardContent(height: MapCardRenderingFixture.shortHeight)
    }

    /// AC-24/37/60: adding a compact facts layout must preserve the ordinary
    /// portrait card's complete information and actions.
    @Test func ordinaryCurrentPositionCardStillRendersAllFactsAndActions() throws {
        try assertCurrentPositionCardContent(height: MapCardRenderingFixture.ordinaryHeight)
    }

    /// AC-24/37/60, D-17: the measured default-size template must fit two
    /// complete title lines, two address lines and three inline metadata rows
    /// while exposing more map than the previous ordinary 320-point card.
    /// Offscreen rendering does not prove legal clearance or interactive targets.
    @Test func measuredInlineTemplateFitsTwoLineSummaryAndAllMetadata() throws {
        let place = MapQuickPlace(
            id: .currentPosition, name: MapCardRenderingFixture.twoLineName,
            address: MapCardRenderingFixture.twoLineAddress,
            coordinate: try Coordinate(latitude: 10.780696, longitude: 106.674196),
            horizontalAccuracyMetres: 10,
            timestamp: MapCardRenderingFixture.timestamp
        )
        var referenceHeight: CGFloat?
        let measuringCard = MapQuickPlaceCard(
            place: place, width: MapCardRenderingFixture.width,
            height: MapCardRenderingFixture.ordinaryHeight,
            onClose: {}, onOpenInMaps: {}, onViewDetails: {},
            onReferenceHeightChange: { referenceHeight = $0 }
        )
        .environment(\.dynamicTypeSize, .large)
        .environment(\.locale, MapCardRenderingFixture.locale)
        .environment(\.timeZone, MapCardRenderingFixture.timeZone)
        let host = UIHostingController(rootView: measuringCard)
        let bounds = CGRect(
            origin: .zero,
            size: CGSize(width: MapCardRenderingFixture.width,
                         height: MapCardRenderingFixture.ordinaryHeight)
        )
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.setNeedsLayout()
        window.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // onGeometryChange needs an attached render transaction. Flush screen
        // updates synchronously instead of sleeping or polling for the callback.
        _ = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let height = try #require(referenceHeight)
        #expect(height > 0)
        #expect(height < MapCardRenderingFixture.ordinaryHeight)
        try assertCurrentPositionCardContent(
            height: height, name: MapCardRenderingFixture.twoLineName,
            address: MapCardRenderingFixture.twoLineAddress,
            summaryText: MapCardRenderingFixture.twoLineSummaryText
        )
    }

    private func assertCurrentPositionCardContent(
        height: CGFloat,
        name: String? = nil,
        address: String = MapCardRenderingFixture.address,
        summaryText: [String] = MapCardRenderingFixture.defaultSummaryText
    ) throws {
        let place = MapQuickPlace(
            id: .currentPosition, name: name, address: address,
            coordinate: try Coordinate(latitude: 10.780696, longitude: 106.674196),
            horizontalAccuracyMetres: 10,
            timestamp: MapCardRenderingFixture.timestamp
        )
        let card = MapQuickPlaceCard(
            place: place, width: MapCardRenderingFixture.width, height: height,
            onClose: {}, onOpenInMaps: {}, onViewDetails: {},
            onReferenceHeightChange: { _ in }
        )
        .environment(\.dynamicTypeSize, .large)
        .environment(\.locale, MapCardRenderingFixture.locale)
        .environment(\.timeZone, MapCardRenderingFixture.timeZone)
        .environment(\.colorScheme, .light)
        .foregroundStyle(.black)
        .background(.white)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(MapCardRenderingFixture.width * renderer.scale))
        #expect(abs(CGFloat(image.height) - height * renderer.scale) <= 1)
        let png = try #require(UIImage(cgImage: image).pngData())
        let imageName = height == MapCardRenderingFixture.shortHeight
            ? MapCardRenderingFixture.shortImageName
            : MapCardRenderingFixture.ordinaryImageName
        Attachment.record(Array(png), named: imageName)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [MapCardRenderingFixture.recognitionLanguage]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observations = request.results ?? []
        let visibleText = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: MapCardRenderingFixture.textSeparator)
        // Measurement formatting can select the simulator's system unit
        // preference independently of the supplied text locale. Both rounded
        // representations must still express the fixture's ten-metre accuracy.
        let accuracyIsVisible = MapCardRenderingFixture.allowedAccuracyText
            .contains { visibleText.contains($0) }
        var diagnostic = visibleText
        let expectedVisibleText = summaryText + MapCardRenderingFixture.expectedVisibleText
        if !accuracyIsVisible || expectedVisibleText.contains(where: { !visibleText.contains($0) }) {
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                MapCardRenderingFixture.failureImagePrefix + UUID().uuidString
                    + MapCardRenderingFixture.imageExtension
            )
            try png.write(to: outputURL, options: .atomic)
            diagnostic += MapCardRenderingFixture.textSeparator + outputURL.path
        }
        for expected in expectedVisibleText {
            #expect(visibleText.contains(expected), Comment(rawValue: diagnostic))
        }
        #expect(accuracyIsVisible, Comment(rawValue: diagnostic))
        let accuracyText = try #require(MapCardRenderingFixture.allowedAccuracyText.first {
            visibleText.contains($0)
        })
        let metadataPairs = [
            (MapCardRenderingFixture.coordinateLabel, MapCardRenderingFixture.latitudeText),
            (MapCardRenderingFixture.accuracyLabel, accuracyText),
            (MapCardRenderingFixture.timeLabel, MapCardRenderingFixture.timeText),
        ]
        for (label, value) in metadataPairs {
            let labelBounds = try recognizedBounds(of: label, in: observations, height: height)
            let valueBounds = try recognizedBounds(of: value, in: observations, height: height)
            // Glyph descenders and the two semantic font sizes can differ by a
            // few points; separate stacked lines cannot satisfy this tolerance.
            #expect(abs(labelBounds.maxY - valueBounds.maxY) <= MapCardRenderingFixture.baselineTolerance,
                    Comment(rawValue: diagnostic))
            #expect(valueBounds.minX > labelBounds.minX, Comment(rawValue: diagnostic))
        }
        if summaryText == MapCardRenderingFixture.twoLineSummaryText {
            let lines = try summaryText.map {
                try recognizedBounds(of: $0, in: observations, height: height)
            }
            for (upper, lower) in zip(lines, lines.dropFirst()) {
                #expect(upper.maxY < lower.minY, Comment(rawValue: diagnostic))
            }
        }
    }

    private func recognizedBounds(
        of text: String, in observations: [VNRecognizedTextObservation], height: CGFloat
    ) throws -> CGRect {
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first,
                  let range = candidate.string.range(of: text),
                  let box = try candidate.boundingBox(for: range)?.boundingBox else { continue }
            return CGRect(
                x: box.minX * MapCardRenderingFixture.width,
                y: (1 - box.maxY) * height,
                width: box.width * MapCardRenderingFixture.width,
                height: box.height * height
            )
        }
        Issue.record(Comment(rawValue: text))
        throw MapCardRenderingFailure.missingRecognizedText
    }

    private func assertCardClearsMapChrome(_ layout: MapCardLayout) {
        let cardTop = layout.size.height - layout.cardBottomInset - layout.cardHeight
        if layout.cardAtLeading || layout.omitsCompassForCard {
            #expect(cardTop >= MapCardLayout.edgePadding)
        } else {
            #expect(cardTop >= MapCardLayout.upperControlHeight + 2 * MapCardLayout.edgePadding)
        }
        #expect(layout.cardHeight >= 0)
        #expect(layout.size.height - layout.cardHeight >= layout.cardBottomInset)
    }

    private func makeCandidate(kind: PlaceGeographicKind = .unknown) throws -> PlaceCandidate {
        PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: nil,
            name: MapCardFixture.name, address: MapCardFixture.address, category: nil,
            coordinate: try Coordinate(latitude: 21, longitude: 105), geographicKind: kind
        )
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

private enum MapCardFixture {
    static let name = "Card Search Result"
    static let address = "Card Address"
    static let oldAddress = "Old GPS Address"
    static let newAddress = "New GPS Address"
    static let firstLocale = "vi"
    static let secondLocale = "en"
}

private enum MapCardTestMetrics {
    static let fullTemplateHeight: CGFloat = 304
}

private enum MapCardRenderingFixture {
    static let twoLineName = "Northern Riverside Museum\nand Botanical Garden"
    static let twoLineAddress = "457 Cach Mang Thang 8\nHoa Hung, Ho Chi Minh City"
    static let twoLineSummaryText = [
        "Northern Riverside Museum", "and Botanical Garden",
        "457 Cach Mang Thang 8", "Hoa Hung, Ho Chi Minh City",
    ]
    static let defaultSummaryText = ["My Location", "Alley 457", "Vietnam"]
    static let coordinateLabel = "Coordinates"
    static let accuracyLabel = "Horizontal Accuracy"
    static let timeLabel = "Position Time"
    static let latitudeText = "10.780696"
    static let timeText = "07:31"
    static let baselineTolerance: CGFloat = 4
    static let address = "Alley 457 Cach Mang Thang 8, Hoa Hung, Ho Chi Minh City, Vietnam"
    static let timestamp = Date(timeIntervalSince1970: 1_791_851_460)
    static let width: CGFloat = 360
    static let shortHeight: CGFloat = 218
    static let ordinaryHeight: CGFloat = 320
    static let locale = Locale(identifier: "en_GB")
    static let timeZone = TimeZone(secondsFromGMT: 7 * 60 * 60)!
    static let recognitionLanguage = "en-US"
    static let textSeparator = " "
    static let failureImagePrefix = "projectalpha-map-card-failure-"
    static let imageExtension = ".png"
    static let shortImageName = "current-position-short-card.png"
    static let ordinaryImageName = "current-position-ordinary-card.png"
    static let allowedAccuracyText = ["10 m", "33 ft"]
    static let expectedVisibleText = [
        "Coordinates",
        "10.780696", "106.674196", "Horizontal Accuracy",
        "Position Time", "2026", "07:31", "View Details", "Open in Maps",
    ]
}

private enum MapCardRenderingFailure: Error {
    case missingRecognizedText
}

/// The fake deliberately ignores cancellation; every suspension is released by
/// the test so stale-result rejection is attributable to the presentation model.
private actor MapCardReverseGeocoder: ReverseGeocodingService {
    private var requests: [ReverseGeocodeRequest] = []
    private var pending: [Int: CheckedContinuation<Result<ReverseGeocodedAddress, PlaceServiceError>, Never>] = [:]
    private var requestWaiters: [(Int, CheckedContinuation<ReverseGeocodeRequest, Never>)] = []

    func reverseGeocode(_ request: ReverseGeocodeRequest) async throws(PlaceServiceError) -> ReverseGeocodedAddress {
        requests.append(request)
        let index = requests.count
        let ready = requestWaiters.filter { $0.0 <= index }
        requestWaiters.removeAll { $0.0 <= index }
        for (count, waiter) in ready { waiter.resume(returning: requests[count - 1]) }
        let result: Result<ReverseGeocodedAddress, PlaceServiceError> = await withCheckedContinuation {
            pending[index] = $0
        }
        return try result.get()
    }

    func waitForRequest(_ count: Int) async -> ReverseGeocodeRequest {
        if requests.count >= count { return requests[count - 1] }
        return await withCheckedContinuation { requestWaiters.append((count, $0)) }
    }

    func complete(_ index: Int, address: String?) {
        guard let continuation = pending.removeValue(forKey: index) else { return }
        continuation.resume(returning: .success(ReverseGeocodedAddress(
            request: requests[index - 1], address: address
        )))
    }

    func fail(_ index: Int, with error: PlaceServiceError) {
        pending.removeValue(forKey: index)?.resume(returning: .failure(error))
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
