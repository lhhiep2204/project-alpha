//
//  MapSelectedPlaceRouteTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation
import MapKit
import SwiftUI
import UIKit
import Vision
import Testing
@testable import ProjectAlpha

/// AC-19/24/37/43/54, D-03: deterministic selected-place routes, never live Maps.
@MainActor
struct MapSelectedPlaceRouteTests {
    /// AC-43/54: inclusive metre boundaries use metric distance before formatting.
    @Test(arguments: [0.0, 999.999, 1_000, 1_000.001, 500_000, 500_000.001, 1_999_999.999, 2_000_000, 2_000_000.001, 20_000_000])
    func automaticModeRespectsApprovedBoundaries(distance: Double) {
        let expected: RouteMode? = distance <= 1_000 ? .walking : .driving
        #expect(MapRouteModel.automaticMode(distanceMetres: distance) == expected)
    }

    /// AC-43/54: mode follows each destination and origin without a manual override.
    @Test func automaticModeRecomputesForDestinationAndOrigin() async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = MapRouteModel(service: service)
        #expect(model.state == .idle)
        #expect(await service.requestCount == 0)
        model.setActive(true)
        model.update(origin: try origin(), destination: try place(latitude: 10.1))
        let driving = await service.waitForRequest(1)
        #expect(driving.mode == .driving)
        await service.complete(1, with: .success(try makeEstimate(driving)))
        await model.awaitPendingEstimate()
        model.update(origin: try origin(), destination: try place())
        let walking = await service.waitForRequest(2)
        #expect(walking.mode == .walking)
        await service.complete(2, with: .success(try makeEstimate(walking)))
        await model.awaitPendingEstimate()
        model.update(origin: try origin(latitude: 10.2), destination: try place())
        let changedOrigin = await service.waitForRequest(3)
        #expect(changedOrigin.mode == .driving)
        await service.complete(3, with: .success(try makeEstimate(changedOrigin)))
        await model.awaitPendingEstimate()
        #expect(await service.requestCount == 3)
    }

    /// AC-43/54: no origin is explicit; displaying a place cannot acquire GPS.
    @Test func missingOriginIsExplicitWithoutRouteRequest() async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = MapRouteModel(service: service)
        model.setActive(true)
        model.update(origin: nil, destination: try place())
        #expect(model.state == .noOrigin)
        #expect(await service.requestCount == 0)
    }

    /// AC-54: even beyond 2,000 km provider availability decides whether a
    /// driving route is shown; only failure falls back to direct distance.
    @Test(arguments: [true, false])
    func longDistanceDrivingRequiresAnAvailableProviderRoute(routeAvailable: Bool) async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = MapRouteModel(service: service)
        model.setActive(true)
        model.update(origin: try origin(), destination: try place(latitude: 30))
        let request = await service.waitForRequest(1)
        #expect(request.mode == .driving)
        guard case .loading(let directDistance, .driving) = model.state else {
            Issue.record(); return
        }
        #expect(directDistance > 2_000_000)
        if routeAvailable {
            let estimate = try RouteEstimate(
                request: request, distanceMetres: 2_400_000, duration: 86_400,
                computedAt: Fixture.date
            )
            await service.complete(1, with: .success(estimate))
            await model.awaitPendingEstimate()
            #expect(model.state == .available(distanceMetres: directDistance, estimate: estimate))
        } else {
            await service.complete(1, with: .failure(.noRoute))
            await model.awaitPendingEstimate()
            #expect(model.state == .unavailable(distanceMetres: directDistance, mode: .driving))
        }
        #expect(await service.requestCount == 1)
    }

    /// AC-24/54: successful and pending routes must not display the direct
    /// fallback. Render the actual shared view used by both card and full detail.
    @Test(arguments: [RouteMode.walking, .driving])
    func directDistanceIsRenderedOnlyWhenTheRouteIsUnavailable(mode: RouteMode) throws {
        let request = RouteRequest(
            origin: RouteEndpoint(coordinate: try origin(), savedLocationID: nil, placeIdentity: nil),
            destination: RouteEndpoint(coordinate: try origin(latitude: 10.001), savedLocationID: nil, placeIdentity: nil),
            mode: mode, generation: 1
        )
        let states: [(MapRouteState, Bool)] = [
            (.available(distanceMetres: Fixture.directDistance, estimate: try makeEstimate(request)), false),
            (.loading(distanceMetres: Fixture.directDistance, mode: mode), false),
            (.unavailable(distanceMetres: Fixture.directDistance, mode: mode), true),
        ]
        for (state, showsDirectDistance) in states {
            let view = MapRouteSummaryView(state: state, distanceUnit: .kilometre)
                .environment(\.locale, Fixture.locale)
                .environment(\.dynamicTypeSize, .large)
                .foregroundStyle(.black)
                .frame(width: Fixture.summaryWidth, height: Fixture.summaryHeight, alignment: .topLeading)
                .background(.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = Fixture.renderScale
            let image = try #require(renderer.cgImage)
            let png = try #require(UIImage(cgImage: image).pngData())
            Attachment.record(Array(png), named: Fixture.summaryImageName)
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = [Fixture.recognitionLanguage]
            recognition.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([recognition])
            let text = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: Fixture.textSeparator)
            switch state {
            case .available:
                #expect(text.contains(Fixture.routeDistanceText), Comment(rawValue: text))
            case .loading:
                #expect(text.contains(Fixture.calculatingText), Comment(rawValue: text))
            case .unavailable:
                #expect(text.contains(Fixture.directDistanceText), Comment(rawValue: text))
            default: Issue.record()
            }
            #expect(text.contains(Fixture.straightLineLabel) == showsDirectDistance, Comment(rawValue: text))
        }
    }

    /// AC-43/54: route metrics come from the service, independently of geodesic distance.
    @Test func successfulRouteUsesProviderDistanceAndDurationVerbatim() async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = try activeModel(service)
        let request = await service.waitForRequest(1)
        #expect(request.mode == .walking)
        let estimate = try makeEstimate(request)
        await service.complete(1, with: .success(estimate))
        await model.awaitPendingEstimate()
        guard case .available(let straightLine, let actual) = model.state else {
            Issue.record(); return
        }
        #expect(straightLine > 0 && straightLine < 1_000)
        #expect(actual == estimate)
        #expect(actual.distanceMetres != straightLine)
        #expect(actual.duration == Fixture.duration)
        model.update(origin: try origin(), destination: try place())
        model.setActive(false)
        model.setActive(true)
        #expect(model.state == .available(distanceMetres: straightLine, estimate: estimate))
        #expect(await service.requestCount == 1)
    }

    /// AC-43/54: offline/no-route outcomes preserve useful independent distance.
    @Test(arguments: [PlaceServiceError.networkUnavailable, .noRoute, .providerUnavailable])
    func providerFailurePreservesStraightLineDistance(error: PlaceServiceError) async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = try activeModel(service)
        _ = await service.waitForRequest(1)
        guard case .loading(let distance, let mode) = model.state else {
            Issue.record(); return
        }
        await service.complete(1, with: .failure(error))
        await model.awaitPendingEstimate()
        #expect(model.state == .unavailable(distanceMetres: distance, mode: mode))
    }

    /// AC-19/43, D-03: a provider response for a different request is not this ETA.
    @Test func mismatchedEchoCannotPublishEstimate() async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = try activeModel(service)
        let request = await service.waitForRequest(1)
        let wrong = RouteRequest(origin: request.origin, destination: request.destination,
                                 mode: .driving, generation: request.generation)
        await service.complete(1, with: .success(try makeEstimate(wrong)))
        await model.awaitPendingEstimate()
        guard case .unavailable(_, .walking) = model.state else { Issue.record(); return }
    }

    /// AC-19/43, D-03: coordinates identify manual/no-ID destinations; origin,
    /// selected ID and mode also supersede requests even if the provider ignores cancellation.
    @Test(arguments: Change.allCases)
    func obsoleteRouteCannotReplaceNewRequest(change: Change) async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = try activeModel(service)
        let oldRequest = await service.waitForRequest(1)
        let oldFinished = await capturePendingCompletion(model)
        switch change {
        case .origin: model.update(origin: try origin(latitude: 10.002), destination: try place())
        case .coordinate: model.update(origin: try origin(), destination: try place(latitude: 10.003))
        case .selectedID: model.update(origin: try origin(), destination: try place(id: Fixture.otherID))
        case .mode: model.update(origin: try origin(), destination: try place(latitude: 10.1))
        }
        let currentRequest = await service.waitForRequest(2)
        #expect(currentRequest != oldRequest)
        #expect(currentRequest.destination.placeIdentity == nil)
        let estimate = try makeEstimate(currentRequest)
        await service.complete(2, with: .success(estimate))
        await model.awaitPendingEstimate()
        let current = model.state
        await service.complete(1, with: .success(try makeEstimate(oldRequest)))
        await oldFinished.value
        #expect(model.state == current)
        guard case .available(_, let displayed) = model.state else { Issue.record(); return }
        #expect(displayed.request == currentRequest)
    }

    /// AC-19/37/43: X or recenter removes the candidate route, rejecting late work.
    @Test(arguments: [false, true])
    func removingDestinationRejectsLateEstimate(recenter: Bool) async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = try activeModel(service)
        let request = await service.waitForRequest(1)
        let finished = await capturePendingCompletion(model)
        let destination = recenter ? try place(id: .currentPosition) : nil
        model.update(origin: try origin(), destination: destination)
        #expect(model.state == .idle)
        await service.complete(1, with: .success(try makeEstimate(request)))
        await finished.value
        #expect(model.state == .idle)
    }

    /// AC-19/43: losing the usable origin invalidates an in-flight ETA rather
    /// than publishing directions from a position the session no longer has.
    @Test func missingOriginInvalidatesPendingRoute() async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = try activeModel(service)
        let request = await service.waitForRequest(1)
        let finished = await capturePendingCompletion(model)
        model.update(origin: nil, destination: try place())
        #expect(model.state == .noOrigin)
        await service.complete(1, with: .success(try makeEstimate(request)))
        await finished.value
        #expect(model.state == .noOrigin)
    }

    /// AC-19/43, D-03: inactive sessions reject late results; resume retries once.
    @Test func pauseRejectsLateEstimateAndResumeStartsFreshRequest() async throws {
        let service = ControlledSelectedPlaceRoutes()
        let model = try activeModel(service)
        let request = await service.waitForRequest(1)
        let finished = await capturePendingCompletion(model)
        model.setActive(false)
        let paused = model.state
        await service.complete(1, with: .success(try makeEstimate(request)))
        await finished.value
        #expect(model.state == paused)
        model.setActive(true)
        let resumed = await service.waitForRequest(2)
        #expect(resumed.generation != request.generation)
        model.setActive(true)
        let estimate = try makeEstimate(resumed)
        await service.complete(2, with: .success(estimate))
        await model.awaitPendingEstimate()
        #expect(await service.requestCount == 2)
        guard case .available(_, let actual) = model.state else { Issue.record(); return }
        #expect(actual == estimate)
    }

    /// AC-19/24/37/43/54/58, D-03, INV-09: search and actual resolved POI
    /// enter the same route path. An already-open detail observes that session's
    /// completion while repeated compact/regular layouts retain one selection.
    /// This model evidence cannot prove sheet rendering or first-frame timing.
    @Test(arguments: [false, true])
    func selectedPlaceDetailRetainsLiveRouteAcrossGeometryChanges(nativePOI: Bool) async throws {
        let service = ControlledSelectedPlaceRoutes()
        let (model, location) = try await activeMap(service)
        let candidate = PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: nil, name: Fixture.name,
            address: nil, category: nil, coordinate: try origin(latitude: 10.001)
        )
        if nativePOI {
            let selection = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
                candidate
            }
            await selection?.value
        } else {
            model.selectSearchCandidate(candidate)
        }
        let request = await service.waitForRequest(1)
        #expect(request.origin.coordinate == location.coordinate)
        #expect(request.destination.coordinate == candidate.coordinate)
        model.showDetails()
        let detailRoute = model.route
        let selectedID = model.selectedDetail?.id
        let camera = try #require(model.cameraPosition.region)
        for (width, height, regular) in [(400.0, 700.0, false), (1_000.0, 650.0, true),
                                         (600.0, 180.0, false), (400.0, 700.0, false)] {
            let layout = MapCardLayout(size: CGSize(width: width, height: height), regularWidth: regular,
                                       leadingIsPhysicalLeft: true, referenceCardHeight: 304)
            model.setFocusViewport(width: width, height: height, cardWidth: layout.cardWidth,
                                   cardHeight: layout.cardHeight, cardAtLeading: layout.cardAtLeading)
            #expect(model.route === detailRoute)
            #expect(model.selectedDetail?.id == selectedID)
            #expect(model.selectedCandidate?.id == candidate.id)
            #expect(model.cameraPosition.region?.center.latitude == camera.center.latitude)
            #expect(model.cameraPosition.region?.center.longitude == camera.center.longitude)
        }
        let estimate = try makeEstimate(request)
        await service.complete(1, with: .success(estimate))
        await model.route.awaitPendingEstimate()
        guard case .available(_, let displayed) = detailRoute.state else { Issue.record(); return }
        #expect(displayed == estimate)
        #expect(model.selectedDetail?.id == selectedID)
        #expect(await service.requestCount == 1)
    }

    /// AC-19/24/37/43: the real card X resets route ownership and rejects late ETA.
    @Test func candidateCardDismissalClearsPendingRouteInMapSession() async throws {
        let service = ControlledSelectedPlaceRoutes()
        let (model, _) = try await activeMap(service)
        let candidate = PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: nil, name: Fixture.name,
            address: nil, category: nil, coordinate: try origin(latitude: 10.001)
        )
        model.selectSearchCandidate(candidate)
        let request = await service.waitForRequest(1)
        let finished = await capturePendingCompletion(model.route)
        model.showDetails()
        model.dismissSearchCandidate()
        #expect(model.route.state == .idle)
        #expect(model.selectedDetail == nil)
        #expect(model.visiblePlace?.id == .currentPosition)
        await service.complete(1, with: .success(try makeEstimate(request)))
        await finished.value
        #expect(model.route.state == .idle)
        #expect(model.selectedCandidate == nil)
    }

    /// AC-19/37/43/54, D-03: returning from Settings must revalidate current
    /// authorization before reusing a retained fix for any selected-place ETA.
    /// A late response from before revocation cannot restore the obsolete route.
    @Test(arguments: AuthorizationLoss.allCases)
    func revokedAuthorizationPreventsRoutesOnReturnAndExplicitRecenter(loss: AuthorizationLoss) async throws {
        let service = ControlledSelectedPlaceRoutes()
        let location = MapPresentationLocationService(status: .authorizedWhenInUse)
        let position = try DevicePosition(coordinate: origin(), timestamp: Fixture.date,
                                          horizontalAccuracyMetres: 10,
                                          authorization: MapPresentationLocationService.allowed)
        location.immediateResult = .success(position)
        let model = MapViewModel(deviceLocationService: location, routeEstimationService: service,
                                 positionClock: { Fixture.date })
        #expect(await model.activate() == nil)
        let retained = PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: nil, name: Fixture.name,
            address: nil, category: nil, coordinate: try origin(latitude: 10.001)
        )
        model.selectSearchCandidate(retained)
        let oldRequest = await service.waitForRequest(1)
        let oldFinished = await capturePendingCompletion(model.route)
        model.showDetails()
        model.deactivate()
        let pausedRoute = model.route.state
        location.snapshot = LocationAuthorization(status: loss.status, accuracy: .full,
                                                  servicesEnabled: loss != .servicesDisabled)
        location.suspendsAuthorization = true
        let activation = Task { await model.activate() }
        await location.waitForAuthorization(2)
        // Authorization inspection can itself suspend; retained metadata is not
        // permission to resume a directions request during that interval.
        #expect(model.route.state == pausedRoute)
        #expect(await service.requestCount == 1)
        await service.complete(1, with: .success(try makeEstimate(oldRequest)))
        await oldFinished.value
        #expect(model.route.state == pausedRoute)
        location.completeAuthorization(2)
        #expect(await activation.value == nil)
        #expect(model.currentPosition == position)
        #expect(model.selectedCandidate?.id == retained.id)
        #expect(model.route.state == .noOrigin)
        #expect(location.positionCalls == 1)
        #expect(await service.requestCount == 1)

        let newer = PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: nil, name: Fixture.name,
            address: nil, category: nil, coordinate: try origin(latitude: 10.002)
        )
        model.selectSearchCandidate(newer)
        #expect(model.route.state == .noOrigin)
        location.suspendsAuthorization = false
        #expect(await model.recenter() == loss.outcome)
        #expect(model.currentPosition == position)
        #expect(model.selectedCandidate?.id == newer.id)
        #expect(model.route.state == .noOrigin)
        #expect(location.positionCalls == 1)
        #expect(await service.requestCount == 1)
        #expect(model.route.state == .noOrigin)
        #expect(model.selectedCandidate?.id == newer.id)

        // Restoring authorization makes the retained fix usable again without
        // silently adding another one-shot GPS acquisition on passive return.
        model.deactivate()
        location.snapshot = MapPresentationLocationService.allowed
        #expect(await model.activate() == nil)
        let restoredRequest = await service.waitForRequest(2)
        #expect(restoredRequest.origin.coordinate == position.coordinate)
        #expect(restoredRequest.destination.coordinate == newer.coordinate)
        #expect(location.positionCalls == 1)
        await service.complete(2, with: .success(try makeEstimate(restoredRequest)))
        await model.route.awaitPendingEstimate()
        guard case .available(_, let restored) = model.route.state else { Issue.record(); return }
        #expect(restored.request == restoredRequest)
    }

    /// AC-19/37/43/54, D-03: authorization belongs to the active scene,
    /// while a selection independently supersedes old camera/location work.
    /// The latest valid authorization enables only the newly selected route;
    /// a previous lifecycle's late authorization cannot override a newer denial.
    @Test(arguments: [false, true], AuthorizationCompletion.allCases)
    func selectionDuringAuthorizationPreservesLatestRouteEligibility(
        nativePOI: Bool, completion: AuthorizationCompletion
    ) async throws {
        let service = ControlledSelectedPlaceRoutes()
        let location = MapPresentationLocationService(status: .authorizedWhenInUse)
        let position = try DevicePosition(coordinate: origin(), timestamp: Fixture.date,
                                          horizontalAccuracyMetres: 10,
                                          authorization: MapPresentationLocationService.allowed)
        location.immediateResult = .success(position)
        let model = MapViewModel(deviceLocationService: location, routeEstimationService: service,
                                 positionClock: { Fixture.date })
        #expect(await model.activate() == nil)
        let retained = PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: nil, name: Fixture.name,
            address: nil, category: nil, coordinate: try origin(latitude: 10.001)
        )
        model.selectSearchCandidate(retained)
        let first = await service.waitForRequest(1)
        await service.complete(1, with: .success(try makeEstimate(first)))
        await model.route.awaitPendingEstimate()
        model.deactivate()
        location.suspendsAuthorization = true
        let activation = Task { await model.activate() }
        await location.waitForAuthorization(2)
        let newer = PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: nil, name: Fixture.name,
            address: nil, category: nil, coordinate: try origin(latitude: 10.002)
        )
        if nativePOI {
            let resolution = model.beginMapFeatureSelection { () async throws(PlaceServiceError) -> PlaceCandidate in
                newer
            }
            await resolution?.value
        } else {
            model.selectSearchCandidate(newer)
        }
        let camera = try #require(model.cameraPosition.region)
        let focus = model.locationFocus
        #expect(model.selectedCandidate?.id == newer.id)
        #expect(model.route.state == .noOrigin)
        #expect(await service.requestCount == 1)

        if completion == .staleAllowedAfterDenial {
            model.deactivate()
            location.snapshot = MapPresentationLocationService.denied
            let laterActivation = Task { await model.activate() }
            await location.waitForAuthorization(3)
            location.completeAuthorization(3)
            #expect(await laterActivation.value == nil)
            #expect(model.route.state == .noOrigin)
            location.snapshot = MapPresentationLocationService.allowed
        } else {
            location.snapshot = completion == .allowed
                ? MapPresentationLocationService.allowed : MapPresentationLocationService.denied
        }
        location.completeAuthorization(2)
        #expect(await activation.value == nil)
        #expect(location.positionCalls == 1)
        #expect(model.currentPosition == position)
        #expect(model.selectedCandidate?.id == newer.id)
        #expect(model.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == camera.center.longitude)
        #expect(model.cameraPosition.region?.span.latitudeDelta == camera.span.latitudeDelta)
        #expect(model.cameraPosition.region?.span.longitudeDelta == camera.span.longitudeDelta)
        #expect(model.locationFocus == focus)
        if completion == .allowed {
            let request = await service.waitForRequest(2)
            #expect(request.origin.coordinate == position.coordinate)
            #expect(request.destination.coordinate == newer.coordinate)
            await service.complete(2, with: .success(try makeEstimate(request)))
            await model.route.awaitPendingEstimate()
            #expect(await service.requestCount == 2)
            guard case .available(_, let estimate) = model.route.state else { Issue.record(); return }
            #expect(estimate.request == request)
        } else {
            #expect(model.route.state == .noOrigin)
            #expect(await service.requestCount == 1)
        }
    }

    enum AuthorizationCompletion: CaseIterable, Equatable {
        case allowed, denied, staleAllowedAfterDenial
    }

    enum AuthorizationLoss: CaseIterable, Equatable {
        case denied, restricted, servicesDisabled

        var status: LocationAuthorizationStatus {
            switch self {
            case .denied: .denied
            case .restricted: .restricted
            case .servicesDisabled: .authorizedWhenInUse
            }
        }

        var outcome: MapLocationOutcome {
            switch self {
            case .denied: .permissionDenied
            case .restricted: .toast(.restricted)
            case .servicesDisabled: .toast(.servicesDisabled)
            }
        }
    }

    private func activeMap(_ service: ControlledSelectedPlaceRoutes) async throws -> (MapViewModel, DevicePosition) {
        let location = MapPresentationLocationService(status: .authorizedWhenInUse)
        let position = try DevicePosition(coordinate: origin(), timestamp: Fixture.date,
                                          horizontalAccuracyMetres: 10,
                                          authorization: MapPresentationLocationService.allowed)
        location.immediateResult = .success(position)
        let model = MapViewModel(deviceLocationService: location, routeEstimationService: service,
                                 positionClock: { Fixture.date })
        #expect(await model.activate() == nil)
        return (model, position)
    }

    enum Change: CaseIterable { case origin, coordinate, selectedID, mode }

    private func activeModel(_ service: ControlledSelectedPlaceRoutes) throws -> MapRouteModel {
        let model = MapRouteModel(service: service)
        model.setActive(true)
        model.update(origin: try origin(), destination: try place())
        return model
    }

    private func origin(latitude: Double = 10) throws -> Coordinate {
        try Coordinate(latitude: latitude, longitude: 106)
    }

    private func place(latitude: Double = 10.001, id: MapQuickPlaceID = Fixture.id) throws -> MapQuickPlace {
        MapQuickPlace(id: id, name: Fixture.name, address: nil,
                      coordinate: try origin(latitude: latitude), horizontalAccuracyMetres: nil, timestamp: nil)
    }

    private func makeEstimate(_ request: RouteRequest) throws -> RouteEstimate {
        try RouteEstimate(request: request, distanceMetres: Fixture.routeDistance,
                          duration: Fixture.duration, computedAt: Fixture.date)
    }

    /// Signal only after the main-actor task has reached awaitPendingEstimate,
    /// capturing the old task before a cancellation can replace its handle.
    private func capturePendingCompletion(_ model: MapRouteModel) async -> Task<Void, Never> {
        let (started, signal) = AsyncStream<Void>.makeStream()
        let task = Task { @MainActor in
            signal.yield(())
            signal.finish()
            await model.awaitPendingEstimate()
        }
        for await _ in started { }
        return task
    }

    private enum Fixture {
        static let routeDistanceText = "987"
        static let directDistanceText = "720"
        static let calculatingText = "Calculating route"
        static let directDistance = 720.0
        static let summaryWidth: CGFloat = 360
        static let summaryHeight: CGFloat = 140
        static let renderScale: CGFloat = 3
        static let locale = Locale(identifier: "en_GB")
        static let recognitionLanguage = "en-US"
        static let textSeparator = " "
        static let straightLineLabel = "Straight-line distance"
        static let summaryImageName = "route-summary.png"
        static let name = "Selected museum"
        static let id = MapQuickPlaceID.searchCandidate(UUID())
        static let otherID = MapQuickPlaceID.searchCandidate(UUID())
        static let routeDistance = 987.0
        static let duration = 731.0
        static let date = Date(timeIntervalSince1970: 1_800_000_000)
    }
}

/// AC-43/54: the Domain policy owns the walking threshold and safely rejects
/// invalid distances independently of presentation or provider behavior.
struct SelectedPlaceRouteModePolicyTests {
    @Test(arguments: [0.0, 1_000.0])
    func walkingIncludesZeroAndOneKilometre(distance: Double) {
        #expect(RouteModePolicy.automaticMode(distanceMetres: distance) == .walking)
    }

    @Test(arguments: [(1_000.0).nextUp, 500_000.0, 2_000_000.0, (2_000_000.0).nextUp, 20_000_000.0, Double.greatestFiniteMagnitude])
    func drivingHasNoUpperDistanceCutoff(distance: Double) {
        #expect(RouteModePolicy.automaticMode(distanceMetres: distance) == .driving)
    }

    @Test(arguments: [-1.0, Double.nan, Double.infinity, -Double.infinity])
    func invalidDistancesHaveNoRouteMode(distance: Double) {
        #expect(RouteModePolicy.automaticMode(distanceMetres: distance) == nil)
    }
}

/// Deliberately ignores cancellation so stale-result tests exercise the model guard.
private actor ControlledSelectedPlaceRoutes: RouteEstimationService {
    private var requests: [RouteRequest] = []
    private var pending: [Int: CheckedContinuation<Result<RouteEstimate, PlaceServiceError>, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<RouteRequest, Never>)] = []
    var requestCount: Int { requests.count }

    func estimateRoute(_ request: RouteRequest) async throws(PlaceServiceError) -> RouteEstimate {
        let result: Result<RouteEstimate, PlaceServiceError> = await withCheckedContinuation { continuation in
            requests.append(request)
            pending[requests.count] = continuation
            let ready = waiters.filter { $0.0 <= requests.count }
            waiters.removeAll { $0.0 <= requests.count }
            for (count, waiter) in ready { waiter.resume(returning: requests[count - 1]) }
        }
        return try result.get()
    }

    func waitForRequest(_ count: Int) async -> RouteRequest {
        if requests.count >= count { return requests[count - 1] }
        return await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func complete(_ count: Int, with result: Result<RouteEstimate, PlaceServiceError>) {
        pending.removeValue(forKey: count)?.resume(returning: result)
    }
}
