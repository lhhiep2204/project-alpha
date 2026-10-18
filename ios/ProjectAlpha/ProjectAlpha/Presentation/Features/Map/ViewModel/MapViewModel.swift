//
//  MapViewModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation
import MapKit
import Observation
import SwiftUI

enum MapLocationIssue: Equatable {
    case servicesDisabled
    case restricted
    case timedOut
    case unavailable
}

enum MapLocationOutcome: Equatable {
    case permissionDenied
    case toast(MapLocationIssue)
}

struct MapLocationFocus: Equatable {
    let coordinate: Coordinate
    let generation: Int
    let geographicKind: PlaceGeographicKind
}

enum MapQuickPlaceID: Hashable {
    case currentPosition
    case searchCandidate(UUID)
}

enum MapCandidateSelectionSource: Equatable {
    case search
    case nativePOI
}

struct MapQuickPlace: Identifiable, Equatable {
    let id: MapQuickPlaceID
    let name: String?
    let address: String?
    let coordinate: Coordinate
    let horizontalAccuracyMetres: Double?
    let timestamp: Date?
    let placeIdentity: PlaceIdentity?

    init(
        id: MapQuickPlaceID,
        name: String?,
        address: String?,
        coordinate: Coordinate,
        horizontalAccuracyMetres: Double?,
        timestamp: Date?,
        placeIdentity: PlaceIdentity? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.horizontalAccuracyMetres = horizontalAccuracyMetres
        self.timestamp = timestamp
        self.placeIdentity = placeIdentity
    }

    var isCurrentPosition: Bool { id == .currentPosition }
}

private struct MapFocusViewport: Equatable {
    let width: CGFloat
    let height: CGFloat
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardAtLeading: Bool
    let leadingIsPhysicalLeft: Bool
}

@Observable
@MainActor
final class MapViewModel {
    let route: MapRouteModel
    private let deviceLocationService: any DeviceLocationService
    private let placeSearchService: (any PlaceSearchService)?
    private let reverseGeocodingService: (any ReverseGeocodingService)?
    private let searchDebounceClock: any PlaceSearchDebounceClock
    private let positionClock: () -> Date
    private let mapFeatureResolver: @MainActor (MapFeature) async throws(PlaceServiceError) -> PlaceCandidate
    private var operationGeneration = 0
    private var initialPositionCompleted = false
    private var userChangedCamera = false
    private var userCameraChangeRevision: UInt64 = 0
    private var consumedRecenterRequestID = 0
    private var isActive = false
    private var routeOriginIsAuthorized = false
    private var authorizationReadGeneration: UInt64 = 0
    private var reverseGeocodeGeneration: UInt64 = 0
    private var reverseGeocodeTask: Task<Void, Never>?
    private var addressLocaleIdentifier: String?
    private var focusViewport: MapFocusViewport?
    private var mapFeatureGeneration: UInt64 = 0
    private var mapFeatureTask: Task<Void, Never>?
    private var acceptedNativeMapSelection: MapSelection<UUID>?

    private(set) var mapSelection: MapSelection<UUID>?
    private(set) var mapFeatureResolutionFailureID: UInt64 = 0
    private(set) var placeSearch: MapPlaceSearchModel?
    private(set) var placeSearchGeneration: UInt64 = 0
    private(set) var selectedCandidate: PlaceCandidate?
    private(set) var selectedCandidateSource: MapCandidateSelectionSource?
    private(set) var currentPosition: DevicePosition?
    private(set) var currentAddress: String?
    var selectedDetail: MapQuickPlace?
    private(set) var visibleSearchRegion: PlaceSearchRegion?

    var cameraPosition: MapCameraPosition = .rect(.world)
    private(set) var locationFocus: MapLocationFocus?
    private(set) var isLocating = false
    // A fresh session fix ends visible loading, while the same structured task
    // continues one bounded update. Repeated taps coalesce with that acquisition.
    private(set) var isAcquiringLocation = false
    private(set) var showsUserLocation = false
    private(set) var recenterRequestID = 0
    var permissionAlertPresented = false

    var hasPendingRecenterRequest: Bool {
        recenterRequestID != consumedRecenterRequestID
    }

    var candidateForCustomAnnotation: PlaceCandidate? {
        selectedCandidateSource == .search ? selectedCandidate : nil
    }

    var visiblePlace: MapQuickPlace? {
        if let selectedCandidate {
            return MapQuickPlace(
                id: .searchCandidate(selectedCandidate.id),
                name: selectedCandidate.name,
                address: selectedCandidate.address,
                coordinate: selectedCandidate.coordinate,
                horizontalAccuracyMetres: nil,
                timestamp: nil,
                placeIdentity: selectedCandidate.placeIdentity
            )
        }
        guard let currentPosition else { return nil }
        return MapQuickPlace(
            id: .currentPosition,
            name: nil,
            address: currentAddress,
            coordinate: currentPosition.coordinate,
            horizontalAccuracyMetres: currentPosition.horizontalAccuracyMetres,
            timestamp: currentPosition.timestamp
        )
    }

    init(
        deviceLocationService: any DeviceLocationService,
        placeSearchService: (any PlaceSearchService)? = nil,
        reverseGeocodingService: (any ReverseGeocodingService)? = nil,
        routeEstimationService: (any RouteEstimationService)? = nil,
        searchDebounceClock: any PlaceSearchDebounceClock = ContinuousPlaceSearchDebounceClock(),
        positionClock: @escaping () -> Date = { .now },
        mapFeatureResolver: @escaping @MainActor (MapFeature) async throws(PlaceServiceError) -> PlaceCandidate = {
            _ in throw .providerUnavailable
        }
    ) {
        self.deviceLocationService = deviceLocationService
        self.route = MapRouteModel(service: routeEstimationService)
        self.placeSearchService = placeSearchService
        self.reverseGeocodingService = reverseGeocodingService
        self.searchDebounceClock = searchDebounceClock
        self.positionClock = positionClock
        self.mapFeatureResolver = mapFeatureResolver
    }

    /// Cheap creation belongs to the opening action, never rendering or initialization.
    @discardableResult
    func openPlaceSearch() -> MapPlaceSearchModel {
        pauseMapFeatureSelection()
        if let placeSearch { return placeSearch }
        placeSearchGeneration += 1
        let search = MapPlaceSearchModel(service: placeSearchService, clock: searchDebounceClock)
        placeSearch = search
        return search
    }

    /// Actual dismissal ends this presentation's lifetime; pause uses stop instead.
    func dismissPlaceSearch() {
        placeSearch?.dismiss()
        placeSearch = nil
        resumeNativeMapSelection()
    }

    /// The lifecycle task carries the presentation generation captured by its view.
    /// Cancelled or obsolete tasks never start or pause a replacement presentation.
    func updatePlaceSearchActivity(
        isActive: Bool,
        expectedGeneration: UInt64,
        localeIdentifier: String?
    ) async {
        guard !Task.isCancelled, placeSearchGeneration == expectedGeneration else { return }
        guard isActive else {
            placeSearch?.stop()
            return
        }
        guard let search = placeSearch else { return }
        await search.start(localeIdentifier: localeIdentifier, region: visibleSearchRegion)
    }

    /// Called only by the selected Map destination's foreground lifecycle task.
    /// A cancelled first acquisition can resume on return; completed attempts never refocus.
    func activate() async -> MapLocationOutcome? {
        isActive = true
        // Reinspect current authorization before resuming routes from a retained fix.
        routeOriginIsAuthorized = false
        route.setActive(false)
        resumeNativeMapSelection()
        if currentPosition != nil, currentAddress == nil { startReverseGeocode() }
        return await locate(isExplicit: false)
    }

    func recenter() async -> MapLocationOutcome? {
        guard isActive else { return nil }
        routeOriginIsAuthorized = false
        route.setActive(false)
        defer {
            updateRoute()
            route.setActive(isActive && routeOriginIsAuthorized)
        }
        pauseMapFeatureSelection()
        return await locate(isExplicit: true)
    }

    func requestRecenter() {
        pauseMapFeatureSelection()
        guard isActive, !isAcquiringLocation, !hasPendingRecenterRequest else { return }
        routeOriginIsAuthorized = false
        route.setActive(false)
        recenterRequestID += 1
    }

    func performPendingRecenter() async -> MapLocationOutcome? {
        guard hasPendingRecenterRequest else { return nil }
        consumedRecenterRequestID = recenterRequestID
        return await recenter()
    }

    /// The view cancels its structured task at the same boundary. Generation invalidation
    /// also rejects a service that returns after cancellation or a later activation.
    func deactivate() {
        authorizationReadGeneration += 1
        routeOriginIsAuthorized = false
        route.setActive(false)
        pauseMapFeatureSelection()
        placeSearch?.stop()
        cancelReverseGeocode()
        isActive = false
        operationGeneration += 1
        consumedRecenterRequestID = recenterRequestID
        isLocating = false
        isAcquiringLocation = false
        showsUserLocation = false
    }

    func userDidChangeCamera() {
        userChangedCamera = true
        userCameraChangeRevision += 1
    }

    func recordVisibleRegion(_ region: MKCoordinateRegion) {
        guard let coordinate = try? Coordinate(latitude: region.center.latitude, longitude: region.center.longitude) else { return }
        visibleSearchRegion = try? PlaceSearchRegion(
            center: coordinate,
            latitudeDelta: region.span.latitudeDelta,
            longitudeDelta: region.span.longitudeDelta
        )
        placeSearch?.updateRegion(visibleSearchRegion)
    }

    func selectSearchCandidate(_ candidate: PlaceCandidate) {
        clearMapFeatureSelection()
        selectCandidate(candidate, source: .search, focusesCamera: true)
    }

    /// Native map selection is processed synchronously, before another explicit action
    /// can supersede it. Selecting our own marker retains the existing card.
    func updateMapSelection(_ selection: MapSelection<UUID>?) {
        // MapKit can clear a feature using a non-nil MapSelection whose feature
        // and tag are both nil. Treat it like an absent optional selection.
        let isDeselection = selection?.feature == nil && selection?.value == nil
        if isDeselection {
            if isActive, placeSearch == nil, selectedDetail == nil,
               selectedCandidateSource == .nativePOI || mapFeatureTask != nil {
                // Native focus is independent of the retained card. Only its X
                // dismisses the candidate and returns to the session position.
                clearMapFeatureSelection()
            } else {
                pauseMapFeatureSelection()
            }
            return
        }
        guard isActive, placeSearch == nil, selectedDetail == nil else {
            pauseMapFeatureSelection()
            return
        }
        // Restoring an accepted native selection is presentation bookkeeping,
        // not another explicit provider selection or camera-focus request.
        guard selection != mapSelection else { return }
        if selectedCandidateSource == .nativePOI, selection == acceptedNativeMapSelection {
            pauseMapFeatureSelection()
            return
        }
        cancelMapFeatureResolution()
        mapSelection = selection
        guard let feature = selection?.feature else { return }
        beginMapFeatureSelection { [mapFeatureResolver] () async throws(PlaceServiceError) -> PlaceCandidate in
            try await mapFeatureResolver(feature)
        }
    }

    /// Each tap owns a distinct cancellable request. The closure is also a deterministic
    /// test seam: tests need no live provider or artificially constructed MapFeature.
    @discardableResult
    func beginMapFeatureSelection(
        resolve: @escaping @MainActor () async throws(PlaceServiceError) -> PlaceCandidate
    ) -> Task<Void, Never>? {
        cancelMapFeatureResolution()
        guard isActive, placeSearch == nil, selectedDetail == nil else { return nil }
        supersedePendingPositionFocus()
        let generation = mapFeatureGeneration
        let cameraRevision = userCameraChangeRevision
        mapFeatureTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do {
                let candidate = try await resolve()
                guard !Task.isCancelled, let self, self.isActive,
                      self.mapFeatureGeneration == generation else { return }
                self.mapFeatureTask = nil
                self.selectCandidate(
                    candidate, source: .nativePOI,
                    focusesCamera: self.userCameraChangeRevision == cameraRevision
                )
            } catch {
                guard !Task.isCancelled, let self, self.isActive,
                      self.mapFeatureGeneration == generation else { return }
                self.mapFeatureTask = nil
                self.pauseMapFeatureSelection()
                if (error as? PlaceServiceError) != .cancelled { self.mapFeatureResolutionFailureID += 1 }
            }
        }
        return mapFeatureTask
    }

    func awaitPendingMapFeatureSelection() async {
        await mapFeatureTask?.value
    }

    private func cancelMapFeatureResolution() {
        mapFeatureGeneration += 1
        mapFeatureTask?.cancel()
        mapFeatureTask = nil
    }

    private func clearMapFeatureSelection() {
        cancelMapFeatureResolution()
        mapSelection = nil
        acceptedNativeMapSelection = nil
    }

    /// Cancel a pending replacement without discarding the accepted feature.
    /// A feature explicitly unfocused on the map has no selection to restore.
    private func pauseMapFeatureSelection() {
        cancelMapFeatureResolution()
        mapSelection = selectedCandidateSource == .nativePOI ? acceptedNativeMapSelection : nil
    }

    func resumeNativeMapSelection() {
        guard isActive, placeSearch == nil, selectedDetail == nil,
              mapFeatureTask == nil, selectedCandidateSource == .nativePOI else { return }
        mapSelection = acceptedNativeMapSelection
    }

    private func selectCandidate(
        _ candidate: PlaceCandidate,
        source: MapCandidateSelectionSource,
        focusesCamera: Bool
    ) {
        acceptedNativeMapSelection = source == .nativePOI ? mapSelection : nil
        selectedCandidate = candidate
        selectedCandidateSource = source
        selectedDetail = nil
        updateRoute()
        route.setActive(isActive && routeOriginIsAuthorized)
        // Selecting a search result supersedes both passive acquisition and explicit
        // recentering. A late completion must not publish an obsolete camera focus.
        supersedePendingPositionFocus()
        if focusesCamera {
            focusCamera(on: MapLocationFocus(
                coordinate: candidate.coordinate, generation: operationGeneration,
                geographicKind: candidate.geographicKind
            ))
        }
    }

    private func supersedePendingPositionFocus() {
        operationGeneration += 1
        locationFocus = nil
        isLocating = false
        isAcquiringLocation = false
        consumedRecenterRequestID = recenterRequestID
        userChangedCamera = true
    }

    func dismissSearchCandidate() {
        let dismissesPendingFeature = mapFeatureTask != nil
        clearMapFeatureSelection()
        guard selectedCandidate != nil || dismissesPendingFeature else { return }
        selectedCandidate = nil
        selectedCandidateSource = nil
        selectedDetail = nil
        updateRoute()
        guard let currentPosition else { return }
        operationGeneration += 1
        userChangedCamera = true
        locationFocus = MapLocationFocus(
            coordinate: currentPosition.coordinate, generation: operationGeneration,
            geographicKind: .point
        )
    }

    func showDetails() {
        pauseMapFeatureSelection()
        selectedDetail = visiblePlace
    }

    private func updateRoute() {
        route.update(
            origin: routeOriginIsAuthorized ? currentPosition?.coordinate : nil,
            destination: visiblePlace
        )
    }

    /// Deterministic completion seam for an in-flight optional address request.
    func awaitPendingAddressEnrichment() async {
        await reverseGeocodeTask?.value
    }

    func updateAddressLocale(_ identifier: String) {
        guard addressLocaleIdentifier != identifier else { return }
        addressLocaleIdentifier = identifier
        guard currentPosition != nil else { return }
        currentAddress = nil
        if selectedDetail?.id == .currentPosition {
            selectedDetail = visiblePlace
        }
        if isActive { startReverseGeocode() }
    }

    func setFocusViewport(
        width: CGFloat,
        height: CGFloat,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        cardAtLeading: Bool,
        leadingIsPhysicalLeft: Bool = true
    ) {
        let viewport = MapFocusViewport(
            width: width, height: height, cardWidth: cardWidth,
            cardHeight: cardHeight, cardAtLeading: cardAtLeading,
            leadingIsPhysicalLeft: leadingIsPhysicalLeft
        )
        if focusViewport != viewport { focusViewport = viewport }
    }

    func focusCamera(on focus: MapLocationFocus) {
        // MapKit can represent a gesture-owned camera without a readable region.
        // The latest completed visible region then preserves the user's zoom.
        let retainedSpan = cameraPosition.region?.span ?? visibleSearchRegion.map {
            MKCoordinateSpan(latitudeDelta: $0.latitudeDelta, longitudeDelta: $0.longitudeDelta)
        }
        let span = MapCameraMetrics.span(for: focus.geographicKind, retaining: retainedSpan)
        var latitude = focus.coordinate.latitude
        var longitude = focus.coordinate.longitude
        if let focusViewport, focusViewport.width > 0, focusViewport.height > 0 {
            if focusViewport.cardAtLeading {
                let direction = focusViewport.leadingIsPhysicalLeft ? -1.0 : 1.0
                longitude += direction * span.longitudeDelta
                    * Double(focusViewport.cardWidth / (2 * focusViewport.width))
            } else {
                latitude -= span.latitudeDelta * Double(focusViewport.cardHeight / (2 * focusViewport.height))
            }
        }
        latitude = min(MapCameraMetrics.maximumLatitude, max(-MapCameraMetrics.maximumLatitude, latitude))
        longitude = (longitude + MapCameraMetrics.halfCircle).truncatingRemainder(dividingBy: MapCameraMetrics.fullCircle)
        if longitude < 0 { longitude += MapCameraMetrics.fullCircle }
        longitude -= MapCameraMetrics.halfCircle
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func locate(isExplicit: Bool) async -> MapLocationOutcome? {
        guard !isAcquiringLocation else { return nil }
        operationGeneration += 1
        let generation = operationGeneration
        let cameraRevision = userCameraChangeRevision
        isAcquiringLocation = true
        // Preserve first/no-position feedback without flashing loading over an
        // already usable card while authorization inspection is suspended.
        isLocating = currentPosition == nil && (isExplicit || !initialPositionCompleted)
        defer {
            if generation == operationGeneration {
                isAcquiringLocation = false
                isLocating = false
            }
        }

        authorizationReadGeneration += 1
        let authorizationGeneration = authorizationReadGeneration
        let authorization = await deviceLocationService.authorization()
        // Authorization belongs to this active lifecycle, independently of the
        // camera/acquisition that a newly selected candidate may supersede.
        guard acceptsAuthorization(authorizationGeneration) else { return nil }
        showsUserLocation = authorization.servicesEnabled && authorization.status.allowsPosition
        routeOriginIsAuthorized = showsUserLocation
        updateRoute()
        if !isExplicit || generation != operationGeneration {
            route.setActive(isActive && routeOriginIsAuthorized)
        }
        guard accepts(generation) else { return nil }

        if !isExplicit, initialPositionCompleted { return nil }

        if !authorization.servicesEnabled {
            initialPositionCompleted = true
            return .toast(.servicesDisabled)
        }
        if authorization.status == .denied {
            initialPositionCompleted = true
            return isExplicit ? .permissionDenied : nil
        }
        if authorization.status == .restricted {
            initialPositionCompleted = true
            return .toast(.restricted)
        }

        let reusesPosition = isExplicit && authorization.status.allowsPosition && hasFreshSessionPosition
        isLocating = !reusesPosition
        if reusesPosition, let currentPosition {
            selectedCandidate = nil
            selectedCandidateSource = nil
            clearMapFeatureSelection()
            selectedDetail = nil
            updateRoute()
            locationFocus = MapLocationFocus(
                coordinate: currentPosition.coordinate, generation: generation,
                geographicKind: .point
            )
        }

        do {
            let position = try await deviceLocationService.currentPosition()
            guard accepts(generation) else { return nil }
            initialPositionCompleted = true
            currentPosition = position
            currentAddress = nil
            startReverseGeocode()
            if isExplicit && !reusesPosition {
                selectedCandidate = nil
                selectedCandidateSource = nil
                clearMapFeatureSelection()
                selectedDetail = nil
            }
            if selectedDetail?.id == .currentPosition {
                selectedDetail = visiblePlace
            }
            showsUserLocation = position.authorization.servicesEnabled
                && position.authorization.status.allowsPosition
            routeOriginIsAuthorized = showsUserLocation
            updateRoute()
            if !isExplicit { route.setActive(isActive && routeOriginIsAuthorized) }
            if isExplicit ? userCameraChangeRevision == cameraRevision : !userChangedCamera {
                locationFocus = MapLocationFocus(
                    coordinate: position.coordinate, generation: generation,
                    geographicKind: .point
                )
            }
            return nil
        } catch {
            guard accepts(generation), error != .cancelled else { return nil }
            authorizationReadGeneration += 1
            let authorizationGeneration = authorizationReadGeneration
            let latestAuthorization = await deviceLocationService.authorization()
            guard acceptsAuthorization(authorizationGeneration) else { return nil }
            showsUserLocation = latestAuthorization.servicesEnabled && latestAuthorization.status.allowsPosition
            routeOriginIsAuthorized = showsUserLocation
            switch error {
            case .permissionDenied, .permissionRestricted, .servicesDisabled, .authorizationRequired:
                routeOriginIsAuthorized = false
            default: break
            }
            updateRoute()
            if !isExplicit || generation != operationGeneration {
                route.setActive(isActive && routeOriginIsAuthorized)
            }
            guard accepts(generation) else { return nil }
            initialPositionCompleted = true
            switch error {
            case .permissionDenied:
                showsUserLocation = false
                return isExplicit ? .permissionDenied : nil
            case .servicesDisabled:
                showsUserLocation = false
                return .toast(.servicesDisabled)
            case .permissionRestricted:
                showsUserLocation = false
                return .toast(.restricted)
            case .timedOut: return .toast(.timedOut)
            case .authorizationRequired, .positionUnavailable, .invalidPosition, .stalePosition:
                return .toast(.unavailable)
            case .cancelled: return nil
            }
        }
    }

    private var hasFreshSessionPosition: Bool {
        guard let currentPosition else { return false }
        let age = positionClock().timeIntervalSince(currentPosition.timestamp)
        return age.isFinite && age >= 0 && age <= MapPositionMetrics.maximumImmediateReuseAge
    }

    private func accepts(_ generation: Int) -> Bool {
        isActive && generation == operationGeneration && !Task.isCancelled
    }

    private func acceptsAuthorization(_ generation: UInt64) -> Bool {
        isActive && generation == authorizationReadGeneration && !Task.isCancelled
    }

    private func startReverseGeocode() {
        cancelReverseGeocode()
        guard let service = reverseGeocodingService, let position = currentPosition else { return }
        let generation = reverseGeocodeGeneration
        let request = ReverseGeocodeRequest(
            coordinate: position.coordinate,
            generation: generation,
            localeIdentifier: addressLocaleIdentifier
        )
        reverseGeocodeTask = Task { [weak self] in
            let result = try? await service.reverseGeocode(request)
            guard !Task.isCancelled, let self,
                  self.reverseGeocodeGeneration == generation,
                  self.currentPosition == position else { return }
            self.reverseGeocodeTask = nil
            guard result?.request == request else { return }
            self.currentAddress = result?.address
            if self.selectedDetail?.id == .currentPosition {
                self.selectedDetail = self.visiblePlace
            }
        }
    }

    private func cancelReverseGeocode() {
        reverseGeocodeGeneration += 1
        reverseGeocodeTask?.cancel()
        reverseGeocodeTask = nil
    }
}

private enum MapPositionMetrics {
    static let maximumImmediateReuseAge: TimeInterval = 30
}

private enum MapCameraMetrics {
    static let neighbourhoodSpan = 0.01
    static let citySpan = 0.18
    static let regionSpan = 8.0
    // A larger unknown span shows multiple cities or countries rather than a useful place view.
    static let maximumRetainedSpan = 2.0
    static let maximumLatitude = 85.0
    static let halfCircle = 180.0
    static let fullCircle = 360.0

    static func span(for kind: PlaceGeographicKind, retaining current: MKCoordinateSpan?) -> MKCoordinateSpan {
        let delta: Double
        switch kind {
        case .point: delta = neighbourhoodSpan
        case .city: delta = citySpan
        case .region: delta = regionSpan
        case .unknown:
            if let current,
               current.latitudeDelta.isFinite, current.longitudeDelta.isFinite,
               current.latitudeDelta > 0, current.longitudeDelta > 0,
               current.latitudeDelta <= maximumRetainedSpan,
               current.longitudeDelta <= maximumRetainedSpan {
                return current
            }
            delta = neighbourhoodSpan
        }
        return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
    }
}
