//
//  MapPOISelectionTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 15/10/26.
//

import Foundation
import MapKit
import SwiftUI
import Testing
@testable import ProjectAlpha

/// P-06: docs 06 exact selected-POI resolution; AC-19/24/37/67, D-03/21,
/// INV-09. Each controlled completion is joined through the owned task, including
/// cancelled requests. No live location/provider service or wall-clock delay runs.
@MainActor
struct MapPOISelectionTests {
    /// AC-24: POI resolution uses the candidate card, with full detail by explicit action.
    /// Exact primary/alternate identity survives transfer; no editor is opened.
    @Test func resolvedPOIRetainsExactCandidateAndExplicitDetail() async throws {
        let model = await makeActiveModel()
        let resolver = POIControlledResolution()
        let candidate = try makeCandidate()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        #expect(model.visiblePlace == nil)
        resolver.complete(.success(candidate))
        await task?.value

        #expect(model.selectedCandidate == candidate)
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(model.visiblePlace?.name == candidate.name)
        #expect(model.visiblePlace?.address == candidate.address)
        #expect(model.visiblePlace?.coordinate == candidate.coordinate)
        #expect(model.visiblePlace?.placeIdentity == candidate.placeIdentity)
        #expect(model.selectedDetail == nil)
        let camera = try #require(model.cameraPosition.region)
        #expect(camera.center.latitude == candidate.coordinate.latitude)
        #expect(camera.center.longitude == candidate.coordinate.longitude)

        model.showDetails()
        #expect(model.selectedDetail == model.visiblePlace)
        model.selectedDetail = nil
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        assertCamera(model, equals: camera)
    }

    /// AC-19: a provider that ignores task cancellation cannot replace newer selection.
    @Test func olderPOISuccessCannotReplaceNewerPOICardDetailOrCamera() async throws {
        let model = await makeActiveModel()
        let older = POIControlledResolution()
        let newer = POIControlledResolution()
        let oldCandidate = try makeCandidate(latitude: 11)
        let newCandidate = try makeCandidate(latitude: 22)
        let oldTask = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await older.resolve()
        }
        await older.waitUntilRequested()
        let newTask = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await newer.resolve()
        }
        await newer.waitUntilRequested()
        newer.complete(.success(newCandidate))
        await newTask?.value
        model.showDetails()
        let camera = try #require(model.cameraPosition.region)

        older.complete(.success(oldCandidate))
        await oldTask?.value
        #expect(model.selectedCandidate == newCandidate)
        #expect(model.selectedDetail?.id == .searchCandidate(newCandidate.id))
        #expect(model.mapFeatureResolutionFailureID == 0)
        assertCamera(model, equals: camera)
    }

    /// AC-19/24: stale failures are silent, while a current failure preserves prior content.
    @Test func currentFailureRetainsPriorCardAndCameraAndOnlyCurrentFailureEmitsEvent() async throws {
        let model = await makeActiveModel()
        let retained = try makeCandidate()
        model.selectSearchCandidate(retained)
        let camera = try #require(model.cameraPosition.region)
        let older = POIControlledResolution()
        let newer = POIControlledResolution()
        let oldTask = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await older.resolve()
        }
        await older.waitUntilRequested()
        let newTask = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await newer.resolve()
        }
        await newer.waitUntilRequested()

        older.complete(.failure(.providerUnavailable))
        await oldTask?.value
        #expect(model.mapFeatureResolutionFailureID == 0)
        newer.complete(.failure(.networkUnavailable))
        await newTask?.value
        #expect(model.mapFeatureResolutionFailureID == 1)
        #expect(model.selectedCandidate == retained)
        #expect(model.selectedDetail == nil)
        assertCamera(model, equals: camera)
    }

    /// AC-19/D-03: provider cancellation is normal and does not create error feedback.
    @Test func cancelledResolutionDoesNotEmitFailureOrRemoveCard() async throws {
        let model = await makeActiveModel()
        let candidate = try makeCandidate()
        model.selectSearchCandidate(candidate)
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        resolver.complete(.failure(.cancelled))
        await task?.value
        #expect(model.mapFeatureResolutionFailureID == 0)
        #expect(model.selectedCandidate == candidate)
    }

    /// AC-19: Search's newer presentation remains owned when an old POI finishes.
    @Test func openingSearchSupersedesPendingPOIWithoutDismissingSearch() async throws {
        let model = await makeActiveModel()
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        let search = model.openPlaceSearch()
        let generation = model.placeSearchGeneration
        resolver.complete(.success(try makeCandidate()))
        await task?.value
        #expect(model.placeSearch === search)
        #expect(model.placeSearchGeneration == generation)
        #expect(model.selectedCandidate == nil)
        #expect(model.selectedDetail == nil)
    }

    /// AC-19: successful Search selection wins against an earlier POI request.
    @Test func searchCandidateSupersedesPendingPOI() async throws {
        let model = await makeActiveModel()
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        let searched = try makeCandidate(latitude: 23)
        model.selectSearchCandidate(searched)
        let camera = try #require(model.cameraPosition.region)
        resolver.complete(.success(try makeCandidate(latitude: 12)))
        await task?.value
        #expect(model.selectedCandidate == searched)
        assertCamera(model, equals: camera)
    }

    /// AC-19/24: X dismisses the card and its pending replacement.
    @Test func candidateDismissalInvalidatesPendingPOIAndRetainsCameraWithoutPosition() async throws {
        let model = await makeActiveModel()
        let retained = try makeCandidate()
        model.selectSearchCandidate(retained)
        let camera = try #require(model.cameraPosition.region)
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        model.dismissSearchCandidate()
        resolver.complete(.success(try makeCandidate(latitude: 12)))
        await task?.value
        #expect(model.visiblePlace == nil)
        #expect(model.selectedDetail == nil)
        assertCamera(model, equals: camera)
    }

    /// AC-24/37/67: X after successful POI selection restores the latest position.
    @Test func resolvedPOICardDismissalRestoresCurrentPosition() async throws {
        let service = POILocationService()
        let position = try makePosition()
        service.immediatePosition = position
        let model = MapViewModel(deviceLocationService: service)
        _ = await model.activate()
        let candidate = try makeCandidate()
        let task = model.beginMapFeatureSelection { candidate }
        await task?.value
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        model.dismissSearchCandidate()
        #expect(model.visiblePlace?.id == .currentPosition)
        #expect(model.visiblePlace?.coordinate == position.coordinate)
        let focus = try #require(model.locationFocus)
        #expect(focus.coordinate == position.coordinate)
        model.focusCamera(on: focus)
        #expect(model.cameraPosition.region?.center.latitude == position.coordinate.latitude)
    }

    /// AC-19/D-03: lifecycle cancellation rejects late success without destroying prior card.
    @Test func deactivationRejectsLatePOISuccess() async throws {
        let model = await makeActiveModel()
        let retained = try makeCandidate()
        model.selectSearchCandidate(retained)
        let camera = try #require(model.cameraPosition.region)
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        model.deactivate()
        resolver.complete(.success(try makeCandidate(latitude: 12)))
        await task?.value
        #expect(model.selectedCandidate == retained)
        #expect(model.mapFeatureResolutionFailureID == 0)
        assertCamera(model, equals: camera)
    }

    /// AC-19/D-03: leaving before request startup avoids unnecessary provider work.
    @Test func deactivationBeforeTaskStartsSkipsProviderRequest() async throws {
        let model = await makeActiveModel()
        let candidate = try makeCandidate()
        var requests = 0
        let task = model.beginMapFeatureSelection {
            requests += 1
            return candidate
        }
        // Both mutations run on MainActor before the owned task can begin.
        model.deactivate()
        await task?.value
        #expect(requests == 0)
        #expect(model.selectedCandidate == nil)
        #expect(model.mapFeatureResolutionFailureID == 0)
    }

    /// AC-19/24: opening the existing card's detail supersedes pending replacement.
    @Test func explicitDetailSupersedesPendingPOIAndKeepsItsSelectedIdentity() async throws {
        let model = await makeActiveModel()
        let retained = try makeCandidate()
        model.selectSearchCandidate(retained)
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        model.showDetails()
        resolver.complete(.success(try makeCandidate(latitude: 12)))
        await task?.value
        #expect(model.selectedCandidate == retained)
        #expect(model.selectedDetail?.id == .searchCandidate(retained.id))
        #expect(model.selectedDetail?.placeIdentity == retained.placeIdentity)
    }

    /// AC-37/19: explicit current position supersedes a pending POI immediately.
    @Test func recenterRequestSupersedesPendingPOIBeforePositionCompletes() async throws {
        let service = POILocationService(status: .denied)
        let model = MapViewModel(deviceLocationService: service)
        _ = await model.activate()
        let resolver = POIControlledResolution()
        let poiTask = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        service.status = .authorizedWhenInUse
        model.requestRecenter()
        let locationTask = Task { await model.performPendingRecenter() }
        await service.waitUntilRequested()
        resolver.complete(.success(try makeCandidate()))
        await poiTask?.value
        #expect(model.selectedCandidate == nil)
        let position = try makePosition()
        service.complete(position)
        _ = await locationTask.value
        #expect(model.visiblePlace?.id == .currentPosition)
        #expect(model.locationFocus?.coordinate == position.coordinate)
    }

    /// AC-37/19: the tap supersedes initial position before the POI has resolved.
    @Test func initialPositionCannotRefocusWhilePOIIsResolving() async throws {
        let service = POILocationService()
        let model = MapViewModel(deviceLocationService: service)
        let activation = Task { await model.activate() }
        await service.waitUntilRequested()
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        service.complete(try makePosition())
        _ = await activation.value
        #expect(model.locationFocus == nil)
        let candidate = try makeCandidate()
        resolver.complete(.success(candidate))
        await task?.value
        #expect(model.selectedCandidate == candidate)
        #expect(model.cameraPosition.region?.center.latitude == candidate.coordinate.latitude)
    }

    /// AC-67/INV-09: later manual camera changes survive resolution and layout changes.
    @Test func panZoomDuringPOIResolutionKeepsUserCameraAndShowsCandidate() async throws {
        let model = await makeActiveModel()
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        let camera = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: 80),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.6)
        )
        model.cameraPosition = .region(camera)
        model.userDidChangeCamera()
        let candidate = try makeCandidate()
        resolver.complete(.success(candidate))
        await task?.value
        #expect(model.selectedCandidate == candidate)
        assertCamera(model, equals: camera)
        for width in [CGFloat(320), 1024, 400, 900] {
            model.setFocusViewport(width: width, height: 600, cardWidth: 300,
                                   cardHeight: 280, cardAtLeading: width > 600)
            #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
            #expect(model.selectedDetail == nil)
            assertCamera(model, equals: camera)
        }
    }

    /// AC-24 / approved 2026-10-16 refinement: provider-rendered POIs need no
    /// second app annotation; Search retains its app annotation after a POI.
    @Test func nativePOISuppressesCustomAnnotationAndSearchRestoresIt() async throws {
        let model = await makeActiveModel()
        let native = try makeCandidate()
        let first = model.beginMapFeatureSelection { native }
        await first?.value
        #expect(model.selectedCandidateSource == .nativePOI)
        #expect(model.selectedCandidate == native)
        #expect(model.candidateForCustomAnnotation == nil)

        let searched = try makeCandidate(latitude: 22)
        model.selectSearchCandidate(searched)
        #expect(model.selectedCandidateSource == .search)
        #expect(model.candidateForCustomAnnotation == searched)
        #expect(model.visiblePlace?.id == .searchCandidate(searched.id))

        let second = model.beginMapFeatureSelection { native }
        await second?.value
        #expect(model.selectedCandidateSource == .nativePOI)
        #expect(model.candidateForCustomAnnotation == nil)
        #expect(model.visiblePlace?.id == .searchCandidate(native.id))
    }

    /// AC-24/37/67: native unfocus retains the card/camera despite an available
    /// session position. Only the subsequent X restores that position.
    @Test(arguments: POIDeselectionValue.allCases)
    func nativeDeselectionRetainsCardUntilXRestoresSessionPosition(deselection: POIDeselectionValue) async throws {
        let service = POILocationService()
        let position = try makePosition()
        service.immediatePosition = position
        let model = MapViewModel(deviceLocationService: service)
        _ = await model.activate()
        let native = try makeCandidate()
        let task = model.beginMapFeatureSelection { native }
        await task?.value
        let camera = try #require(model.cameraPosition.region)
        #expect(service.positionRequests == 1)

        model.updateMapSelection(deselection.selection)
        assertUnfocusedNativeCard(model, candidate: native, retainedCamera: camera)
        #expect(service.positionRequests == 1)
        model.dismissSearchCandidate()
        assertNativeDismissal(model, position: position, retainedCamera: camera)
        #expect(service.positionRequests == 1)
    }

    /// AC-24/67: without a position, unfocus retains the card while X hides it.
    @Test(arguments: POIDeselectionValue.allCases)
    func nativeDeselectionWithoutPositionRetainsCardAndCameraUntilX(deselection: POIDeselectionValue) async throws {
        let service = POILocationService(status: .denied)
        let model = MapViewModel(deviceLocationService: service)
        _ = await model.activate()
        let native = try makeCandidate()
        let task = model.beginMapFeatureSelection { native }
        await task?.value
        let camera = try #require(model.cameraPosition.region)
        model.updateMapSelection(deselection.selection)
        assertUnfocusedNativeCard(model, candidate: native, retainedCamera: camera)
        model.dismissSearchCandidate()
        assertNativeDismissal(model, position: nil, retainedCamera: camera)
        #expect(service.positionRequests == 0)
        assertCamera(model, equals: camera)
    }

    /// An explicit unfocus must not be undone by Details, Search or tab return.
    /// A tagged SDK selection supplies a deterministic non-nil ownership token;
    /// candidate resolution still uses the native-resolution seam, not live Maps.
    @Test(arguments: POIPresentationInterruption.allCases, POIDeselectionValue.allCases)
    func unfocusedNativeCardSurvivesLifecycleWithoutRestoringMarkerFocus(
        interruption: POIPresentationInterruption, deselection: POIDeselectionValue
    ) async throws {
        let model = await makeActiveModel()
        let native = try makeCandidate()
        model.updateMapSelection(MapSelection(native.id))
        let task = model.beginMapFeatureSelection { native }
        await task?.value
        #expect(model.mapSelection?.value == native.id)
        model.cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: 80),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.6)
        ))
        model.userDidChangeCamera()
        let camera = try #require(model.cameraPosition.region)
        model.updateMapSelection(deselection.selection)
        assertUnfocusedNativeCard(model, candidate: native, retainedCamera: camera)

        switch interruption {
        case .detail:
            model.showDetails()
            #expect(model.selectedDetail?.id == .searchCandidate(native.id))
            model.selectedDetail = nil
            model.resumeNativeMapSelection()
        case .search:
            _ = model.openPlaceSearch()
            model.dismissPlaceSearch()
        case .tab:
            model.deactivate()
            _ = await model.activate()
        }
        assertUnfocusedNativeCard(model, candidate: native, retainedCamera: camera)

        // A new explicit selection after unfocus remains a normal replacement.
        let replacement = try makeCandidate(latitude: 22)
        let replacementTask = model.beginMapFeatureSelection { replacement }
        await replacementTask?.value
        #expect(model.selectedCandidate == replacement)
        #expect(model.cameraPosition.region?.center.latitude == replacement.coordinate.latitude)
    }

    /// Losing focus while B resolves preserves accepted A and never returns to
    /// an available position. Even a cancellation-ignoring B cannot change it.
    @Test(arguments: [false, true], POIDeselectionValue.allCases)
    func pendingReplacementUnfocusRetainsAcceptedCardAndCamera(
        fails: Bool, deselection: POIDeselectionValue
    ) async throws {
        let service = POILocationService()
        let position = try makePosition()
        service.immediatePosition = position
        let model = MapViewModel(deviceLocationService: service)
        _ = await model.activate()
        let accepted = try makeCandidate()
        let acceptedTask = model.beginMapFeatureSelection { accepted }
        await acceptedTask?.value
        let camera = try #require(model.cameraPosition.region)
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        model.updateMapSelection(deselection.selection)
        assertUnfocusedNativeCard(model, candidate: accepted, retainedCamera: camera)
        resolver.complete(fails ? .failure(.providerUnavailable) : .success(try makeCandidate(latitude: 22)))
        await task?.value
        assertUnfocusedNativeCard(model, candidate: accepted, retainedCamera: camera)
        #expect(model.mapFeatureResolutionFailureID == 0)
        #expect(service.positionRequests == 1)
        model.dismissSearchCandidate()
        assertNativeDismissal(model, position: position, retainedCamera: camera)
        #expect(service.positionRequests == 1)
    }

    /// AC-19/24: deselecting while resolution is pending invalidates both a late
    /// provider success and failure, even when the provider ignores cancellation.
    @Test(arguments: [false, true], POIDeselectionValue.allCases)
    func pendingNativeDeselectionRejectsLateCompletion(fails: Bool, deselection: POIDeselectionValue) async throws {
        let model = await makeActiveModel()
        let candidate = try makeCandidate()
        model.cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: 80),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.6)
        ))
        let camera = try #require(model.cameraPosition.region)
        let resolver = POIControlledResolution()
        let task = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        model.updateMapSelection(deselection.selection)
        #expect(model.visiblePlace == nil)
        resolver.complete(fails ? .failure(.providerUnavailable) : .success(candidate))
        await task?.value
        #expect(model.visiblePlace == nil)
        #expect(model.selectedCandidateSource == nil)
        #expect(model.candidateForCustomAnnotation == nil)
        #expect(model.mapFeatureResolutionFailureID == 0)
        assertCamera(model, equals: camera)
    }

    /// AC-24: nil native selection events outside an active native POI are harmless,
    /// including programmatic events after switching to a Search candidate.
    @Test(arguments: POIDeselectionValue.allCases)
    func nativeNilEventDoesNotDismissSearchCandidateOrRequestPosition(deselection: POIDeselectionValue) async throws {
        let service = POILocationService(status: .denied)
        let model = MapViewModel(deviceLocationService: service)
        _ = await model.activate()
        model.updateMapSelection(deselection.selection)
        #expect(model.visiblePlace == nil)
        let native = try makeCandidate()
        let task = model.beginMapFeatureSelection { native }
        await task?.value
        let searched = try makeCandidate(latitude: 22)
        model.selectSearchCandidate(searched)
        model.updateMapSelection(MapSelection(searched.id))
        #expect(model.mapSelection?.value == searched.id)
        let camera = try #require(model.cameraPosition.region)
        model.updateMapSelection(deselection.selection)
        #expect(model.selectedCandidate == searched)
        #expect(model.selectedCandidateSource == .search)
        #expect(model.candidateForCustomAnnotation == searched)
        #expect(service.positionRequests == 0)
        assertCamera(model, equals: camera)
    }

    /// AC-24/37/67 / INV-09: presentation events and a later explicit native
    /// unfocus retain the card/camera. Only X restores the current position.
    @Test(arguments: POIPresentationInterruption.allCases, [false, true])
    func nativeCardAndMarkerSourceSurviveDetailSearchAndTabLifecycle(
        interruption: POIPresentationInterruption, hasPosition: Bool
    ) async throws {
        let service = POILocationService(status: hasPosition ? .authorizedWhenInUse : .denied)
        let position = hasPosition ? try makePosition() : nil
        service.immediatePosition = position
        let model = MapViewModel(deviceLocationService: service)
        _ = await model.activate()
        let native = try makeCandidate()
        let task = model.beginMapFeatureSelection { native }
        await task?.value
        let camera = try #require(model.cameraPosition.region)
        switch interruption {
        case .detail:
            model.showDetails()
            model.updateMapSelection(POIDeselectionValue.emptyFeature.selection)
            #expect(model.selectedDetail?.id == .searchCandidate(native.id))
            model.selectedDetail = nil
        case .search:
            _ = model.openPlaceSearch()
            model.updateMapSelection(POIDeselectionValue.emptyFeature.selection)
            #expect(model.placeSearch != nil)
            model.dismissPlaceSearch()
        case .tab:
            model.deactivate()
            model.updateMapSelection(POIDeselectionValue.emptyFeature.selection)
            _ = await model.activate()
        }
        #expect(model.visiblePlace?.id == .searchCandidate(native.id))
        #expect(model.selectedCandidateSource == .nativePOI)
        #expect(model.candidateForCustomAnnotation == nil)
        assertCamera(model, equals: camera)
        model.updateMapSelection(POIDeselectionValue.emptyFeature.selection)
        assertUnfocusedNativeCard(model, candidate: native, retainedCamera: camera)
        model.dismissSearchCandidate()
        assertNativeDismissal(model, position: position, retainedCamera: camera)
        #expect(service.positionRequests == (hasPosition ? 1 : 0))
    }

    /// AC-19/24/67: accepted A remains the native selection when B fails or is
    /// paused; later unfocusing keeps A's card, and X explicitly dismisses it.
    @Test(arguments: POIReplacementInterruption.allCases, [false, true])
    func retainedNativePOIAfterReplacementInterruptionSurvivesUnfocusUntilX(
        interruption: POIReplacementInterruption, hasPosition: Bool
    ) async throws {
        let service = POILocationService(status: hasPosition ? .authorizedWhenInUse : .denied)
        let position = hasPosition ? try makePosition() : nil
        service.immediatePosition = position
        let model = MapViewModel(deviceLocationService: service)
        _ = await model.activate()
        let accepted = try makeCandidate()
        let acceptedTask = model.beginMapFeatureSelection { accepted }
        await acceptedTask?.value
        let camera = try #require(model.cameraPosition.region)
        let replacement = try makeCandidate(latitude: 22)
        let resolver = POIControlledResolution()
        let replacementTask = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        switch interruption {
        case .failure:
            resolver.complete(.failure(.providerUnavailable))
            await replacementTask?.value
        case .detail:
            model.showDetails()
            model.updateMapSelection(POIDeselectionValue.emptyFeature.selection)
            resolver.complete(.success(replacement))
            await replacementTask?.value
            #expect(model.selectedDetail?.id == .searchCandidate(accepted.id))
            model.selectedDetail = nil
        case .search:
            _ = model.openPlaceSearch()
            model.updateMapSelection(POIDeselectionValue.emptyFeature.selection)
            resolver.complete(.success(replacement))
            await replacementTask?.value
            model.dismissPlaceSearch()
        case .tab:
            model.deactivate()
            model.updateMapSelection(POIDeselectionValue.emptyFeature.selection)
            resolver.complete(.success(replacement))
            await replacementTask?.value
            _ = await model.activate()
        }
        #expect(model.selectedCandidate == accepted)
        #expect(model.selectedCandidateSource == .nativePOI)
        #expect(model.candidateForCustomAnnotation == nil)
        #expect(model.selectedDetail == nil)
        #expect(model.mapFeatureResolutionFailureID == (interruption == .failure ? 1 : 0))
        assertCamera(model, equals: camera)
        model.updateMapSelection(POIDeselectionValue.emptyFeature.selection)
        assertUnfocusedNativeCard(model, candidate: accepted, retainedCamera: camera)
        model.dismissSearchCandidate()
        assertNativeDismissal(model, position: position, retainedCamera: camera)
        #expect(service.positionRequests == (hasPosition ? 1 : 0))
    }

    /// AC-19/67: direct native A-to-B replacement keeps A's card/camera until B
    /// resolves and never temporarily focuses the available current position.
    @Test func nativeReplacementDoesNotIntermediatelyRestoreCurrentPosition() async throws {
        let service = POILocationService()
        service.immediatePosition = try makePosition()
        let model = MapViewModel(deviceLocationService: service)
        _ = await model.activate()
        let firstCandidate = try makeCandidate()
        let firstTask = model.beginMapFeatureSelection { firstCandidate }
        await firstTask?.value
        let camera = try #require(model.cameraPosition.region)
        let secondCandidate = try makeCandidate(latitude: 22)
        let resolver = POIControlledResolution()
        let secondTask = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
            try await resolver.resolve()
        }
        await resolver.waitUntilRequested()
        #expect(model.visiblePlace?.id == .searchCandidate(firstCandidate.id))
        #expect(model.locationFocus == nil)
        #expect(model.candidateForCustomAnnotation == nil)
        assertCamera(model, equals: camera)
        resolver.complete(.success(secondCandidate))
        await secondTask?.value
        #expect(model.visiblePlace?.id == .searchCandidate(secondCandidate.id))
        #expect(model.selectedCandidateSource == .nativePOI)
        #expect(model.candidateForCustomAnnotation == nil)
        #expect(model.cameraPosition.region?.center.latitude == secondCandidate.coordinate.latitude)
        #expect(service.positionRequests == 1)
    }

    private func makeActiveModel() async -> MapViewModel {
        let model = MapViewModel(deviceLocationService: POILocationService(status: .denied))
        _ = await model.activate()
        return model
    }

    private func makeCandidate(latitude: Double = 21) throws -> PlaceCandidate {
        PlaceCandidate(
            id: UUID(), source: .appleMaps,
            placeIdentity: try PlaceIdentity(primaryID: POIFixture.primaryID, alternateIDs: [POIFixture.alternateID]),
            name: POIFixture.name, address: POIFixture.address, category: nil,
            coordinate: try Coordinate(latitude: latitude, longitude: 105), geographicKind: .point
        )
    }

    private func makePosition() throws -> DevicePosition {
        try DevicePosition(
            coordinate: Coordinate(latitude: 10, longitude: 106),
            timestamp: Date(timeIntervalSinceReferenceDate: 100), horizontalAccuracyMetres: 10,
            authorization: POILocationService.allowed
        )
    }

    private func assertCamera(_ model: MapViewModel, equals expected: MKCoordinateRegion) {
        #expect(model.cameraPosition.region?.center.latitude == expected.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == expected.center.longitude)
        #expect(model.cameraPosition.region?.span.latitudeDelta == expected.span.latitudeDelta)
        #expect(model.cameraPosition.region?.span.longitudeDelta == expected.span.longitudeDelta)
    }

    private func assertUnfocusedNativeCard(
        _ model: MapViewModel, candidate: PlaceCandidate, retainedCamera: MKCoordinateRegion
    ) {
        #expect(model.mapSelection == nil)
        #expect(model.selectedCandidate == candidate)
        #expect(model.selectedCandidateSource == .nativePOI)
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(model.candidateForCustomAnnotation == nil)
        #expect(model.selectedDetail == nil)
        #expect(model.locationFocus == nil)
        assertCamera(model, equals: retainedCamera)
    }

    private func assertNativeDismissal(
        _ model: MapViewModel, position: DevicePosition?, retainedCamera: MKCoordinateRegion
    ) {
        #expect(model.selectedCandidate == nil)
        #expect(model.selectedCandidateSource == nil)
        #expect(model.candidateForCustomAnnotation == nil)
        #expect(model.selectedDetail == nil)
        if let position {
            #expect(model.visiblePlace?.id == .currentPosition)
            #expect(model.visiblePlace?.coordinate == position.coordinate)
            #expect(model.locationFocus?.coordinate == position.coordinate)
            if let focus = model.locationFocus {
                model.focusCamera(on: focus)
                #expect(model.cameraPosition.region?.center.latitude == position.coordinate.latitude)
            }
        } else {
            #expect(model.visiblePlace == nil)
            assertCamera(model, equals: retainedCamera)
        }
    }
}

/// Both forms are SDK-supported: a cleared Optional and an empty MapSelectable.
enum POIDeselectionValue: CaseIterable, Sendable {
    case optionalNil, emptyFeature

    @MainActor var selection: MapSelection<UUID>? {
        switch self {
        case .optionalNil: nil
        case .emptyFeature: MapSelection<UUID>(nil as MapFeature?)
        }
    }
}

enum POIPresentationInterruption: CaseIterable, Equatable, Sendable {
    case detail, search, tab
}

enum POIReplacementInterruption: CaseIterable, Equatable, Sendable {
    case failure, detail, search, tab
}

private enum POIFixture {
    static let primaryID = "poi-primary"
    static let alternateID = "poi-alternate"
    static let name = "Selected Museum"
    static let address = "Authoritative Museum Address"
}

/// Ignores cancellation intentionally; task joining proves stale publication is rejected.
@MainActor
private final class POIControlledResolution {
    private var continuation: CheckedContinuation<Result<PlaceCandidate, PlaceServiceError>, Never>?
    private var requested = false
    private var waiter: CheckedContinuation<Void, Never>?

    func resolve() async throws(PlaceServiceError) -> PlaceCandidate {
        let result: Result<PlaceCandidate, PlaceServiceError> = await withCheckedContinuation {
            continuation = $0
            requested = true
            waiter?.resume()
            waiter = nil
        }
        return try result.get()
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func complete(_ result: Result<PlaceCandidate, PlaceServiceError>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// Isolated test service; pending position deliberately completes despite cancellation.
@MainActor
private final class POILocationService: DeviceLocationService {
    static let allowed = LocationAuthorization(status: .authorizedWhenInUse, accuracy: .full, servicesEnabled: true)
    var status: LocationAuthorizationStatus
    var immediatePosition: DevicePosition?
    private(set) var positionRequests = 0
    private var continuation: CheckedContinuation<DevicePosition, Never>?
    private var requested = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(status: LocationAuthorizationStatus = .authorizedWhenInUse) { self.status = status }

    @MainActor func authorization() async -> LocationAuthorization {
        LocationAuthorization(status: status, accuracy: .full, servicesEnabled: true)
    }

    @MainActor func currentPosition() async throws(LocationServiceError) -> DevicePosition {
        positionRequests += 1
        if let immediatePosition { return immediatePosition }
        return await withCheckedContinuation {
            continuation = $0
            requested = true
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func complete(_ position: DevicePosition) {
        continuation?.resume(returning: position)
        continuation = nil
    }
}
