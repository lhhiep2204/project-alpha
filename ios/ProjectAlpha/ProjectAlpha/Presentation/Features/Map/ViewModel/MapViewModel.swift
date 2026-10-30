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
    case savedLocation(UUID)
}

enum MapCandidateSelectionSource: Equatable {
    case search
    case nativePOI
}

private enum MapCollectionTemporarySelection {
    case currentPosition
    case candidate(PlaceCandidate, MapCandidateSelectionSource, MapSelection<UUID>?)
    case receipt(SavedLocation)
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

private struct MapSavedLocationRequest {
    let id: UUID
    let generation: UInt64
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
    let detailActions: LocationDetailActionModel
    let scopeCollectionID: UUID?
    private let locationRepository: (any LocationRepository)?
    private let collectionRepository: (any CollectionRepository)?
    let mediaService: (any LocationMediaService)?
    private let initialLocationID: UUID?
    private var appliedInitialLibrary = false
    private var pendingSavedLocationRequest: MapSavedLocationRequest?
    private var failedSavedLocationRequest: MapSavedLocationRequest?
    private var libraryObservationFailed = false
    private var failedReceiptID: UUID?
    private(set) var libraryObservationRequestID = UUID()
    private var savedFocusGeneration: UInt64 = 0
    private var libraryGeneration: UInt64 = 0
    private(set) var libraryRevision: Int64 = -1
    private(set) var savedLocations: [SavedLocation] = []
    private(set) var collections: [CollectionSummary] = []
    private(set) var annotationGroups: [MapSavedAnnotationGroup] = []
    private(set) var selectedSavedLocation: SavedLocation?
    private(set) var existingSavedLocationID: UUID?
    private(set) var capture: LocationCaptureModel?
    private(set) var committedReceipt: SavedLocation?
    private(set) var unavailableSavedLocationEvent: UInt64 = 0
    var libraryLoadFailed: Bool {
        libraryObservationFailed
            || (failedReceiptID != nil && failedReceiptID == retainedReceiptID)
            || failedSavedLocationRequest?.generation == savedFocusGeneration
    }

    var retainedReceiptID: UUID? {
        guard case let .receipt(receipt) = collectionTemporarySelection else { return nil }
        return receipt.id
    }
    private(set) var scopeUnavailable = false
    private var suppressesCurrentPositionCard = false
    private var collectionTemporarySelection: MapCollectionTemporarySelection?
    private var deletionFallbackCandidate: PlaceCandidate?

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
    private var isAcquiringCollectionOrigin = false
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
        if let saved = selectedSavedLocation { return quickPlace(for: saved) }
        if let committedReceipt { return quickPlace(for: committedReceipt) }
        if let committed = capture?.commit { return quickPlace(for: committedReceipt ?? committed.location) }
        if let capture, capture.candidate.source == .currentPosition,
           capture.isDirty || capture.isSaving || capture.isEditing {
            return MapQuickPlace(id: .currentPosition, name: nil, address: capture.candidate.address,
                                 coordinate: capture.candidate.coordinate,
                                 horizontalAccuracyMetres: nil, timestamp: nil)
        }
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
        // A passive collection origin supplies travel facts, not a temporary card.
        // Only explicit current-position selection creates that collection item.
        if isCollectionMap {
            guard case .currentPosition = collectionTemporarySelection else { return nil }
        }
        guard !suppressesCurrentPositionCard, let currentPosition else { return nil }
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
        },
        locationRepository: (any LocationRepository)? = nil,
        collectionRepository: (any CollectionRepository)? = nil,
        scopeCollectionID: UUID? = nil,
        initialLocationID: UUID? = nil,
        mediaService: (any LocationMediaService)? = nil
    ) {
        self.scopeCollectionID = scopeCollectionID
        self.initialLocationID = initialLocationID
        self.locationRepository = locationRepository
        self.collectionRepository = collectionRepository
        self.mediaService = mediaService
        self.deviceLocationService = deviceLocationService
        self.route = MapRouteModel(service: routeEstimationService)
        self.detailActions = LocationDetailActionModel(repository: locationRepository, clock: positionClock)
        self.placeSearchService = placeSearchService
        self.reverseGeocodingService = reverseGeocodingService
        self.searchDebounceClock = searchDebounceClock
        self.positionClock = positionClock
        self.mapFeatureResolver = mapFeatureResolver
    }

    var isCollectionMap: Bool { scopeCollectionID != nil }

    var collectionTemporaryPlace: MapQuickPlace? {
        switch collectionTemporarySelection {
        case .currentPosition:
            if selectedSavedLocation == nil, let capture,
               capture.isDirty || capture.isSaving || capture.isEditing { return visiblePlace }
            guard let currentPosition else { return nil }
            return MapQuickPlace(id: .currentPosition, name: nil, address: currentAddress,
                                 coordinate: currentPosition.coordinate,
                                 horizontalAccuracyMetres: currentPosition.horizontalAccuracyMetres,
                                 timestamp: currentPosition.timestamp)
        case let .candidate(candidate, _, _):
            return MapQuickPlace(id: .searchCandidate(candidate.id), name: candidate.name,
                                 address: candidate.address, coordinate: candidate.coordinate,
                                 horizontalAccuracyMetres: nil, timestamp: nil,
                                 placeIdentity: candidate.placeIdentity)
        case let .receipt(saved): return quickPlace(for: saved)
        case nil: return nil
        }
    }

    var collectionCardPlaces: [MapQuickPlace] {
        let temporary = collectionTemporaryPlace.map { [$0] } ?? []
        return temporary + savedLocations.map(quickPlace(for:))
    }

    func showsClose(for place: MapQuickPlace) -> Bool {
        if isCollectionMap {
            return collectionTemporaryPlace?.id == place.id
        }
        return !place.isCurrentPosition
    }

    func selectCollectionCard(_ id: MapQuickPlaceID) {
        guard visiblePlace?.id != id else { return }
        if case let .receipt(saved) = collectionTemporarySelection, id == .savedLocation(saved.id) {
            savedFocusGeneration &+= 1
            clearMapFeatureSelection()
            supersedePendingPositionFocus()
            selectedSavedLocation = nil
            selectedCandidate = nil
            selectedCandidateSource = nil
            selectedDetail = nil
            discardCapture()
            committedReceipt = saved
            suppressesCurrentPositionCard = false
            focusCamera(on: MapLocationFocus(coordinate: saved.coordinate,
                        generation: operationGeneration, geographicKind: .unknown))
            updateRoute()
            route.setActive(isActive && routeOriginIsAuthorized)
            return
        }
        if case let .savedLocation(savedID) = id { selectSavedLocation(savedID); return }
        guard collectionTemporaryPlace?.id == id else { return }
        switch collectionTemporarySelection {
        case let .candidate(candidate, source, nativeSelection):
            clearMapFeatureSelection()
            mapSelection = nativeSelection
            selectCandidate(candidate, source: source, focusesCamera: true)
        case .currentPosition:
            guard let currentPosition else { return }
            savedFocusGeneration &+= 1
            clearMapFeatureSelection()
            supersedePendingPositionFocus()
            selectedSavedLocation = nil
            selectedCandidate = nil
            selectedCandidateSource = nil
            selectedDetail = nil
            discardCapture()
            suppressesCurrentPositionCard = false
            focusCamera(on: MapLocationFocus(coordinate: currentPosition.coordinate,
                        generation: operationGeneration, geographicKind: .point))
            updateRoute()
        case .receipt, nil: break
        }
    }

    var selectedPageIndex: Int? {
        if isCollectionMap {
            return collectionCardPlaces.firstIndex { $0.id == visiblePlace?.id }
        }
        guard let id = selectedSavedLocation?.id else { return nil }
        return savedLocations.firstIndex { $0.id == id }
    }

    var canPagePrevious: Bool { selectedPageIndex.map { $0 > 0 } ?? false }
    var canPageNext: Bool {
        selectedPageIndex.map { $0 + 1 < (isCollectionMap ? collectionCardPlaces.count : savedLocations.count) } ?? false
    }

    func pageSelection(by offset: Int) {
        guard let index = selectedPageIndex else { return }
        let next = index + offset
        if isCollectionMap {
            let places = collectionCardPlaces
            guard places.indices.contains(next) else { return }
            selectCollectionCard(places[next].id)
            return
        }
        guard savedLocations.indices.contains(next) else { return }
        selectSavedLocation(savedLocations[next].id)
    }

    func quickPlace(for saved: SavedLocation) -> MapQuickPlace {
        MapQuickPlace(id: .savedLocation(saved.id), name: saved.displayName ?? saved.name,
                      address: saved.address, coordinate: saved.coordinate,
                      horizontalAccuracyMetres: nil, timestamp: nil, placeIdentity: saved.placeIdentity)
    }

    /// The view owns restarting the structured observation without replacing this map session.
    func retryLibraryLoading() {
        libraryObservationRequestID = UUID()
    }

    /// One structured stream per visible session. A resumed older stream cannot win.
    func observeSavedLocations() async {
        guard !Task.isCancelled, let locationRepository else { return }
        let requestID = libraryObservationRequestID
        libraryGeneration &+= 1
        let generation = libraryGeneration
        if let failed = failedSavedLocationRequest, failed.generation == savedFocusGeneration {
            await resolveSavedLocationRequest(id: failed.id, generation: failed.generation, observationRequestID: requestID)
            guard !Task.isCancelled, generation == libraryGeneration,
                  requestID == libraryObservationRequestID else { return }
        }
        let stream = await locationRepository.observeLocations(collectionID: scopeCollectionID)
        do {
            for try await snapshot in stream {
                guard !Task.isCancelled, generation == libraryGeneration,
                      requestID == libraryObservationRequestID else { return }
                libraryObservationFailed = false
                applyLibrarySnapshot(snapshot)
            }
        } catch {
            guard !Task.isCancelled, generation == libraryGeneration,
                  requestID == libraryObservationRequestID else { return }
            libraryObservationFailed = true
        }
    }

    func applyLibrarySnapshot(_ snapshot: LocationLibrarySnapshot) {
        guard snapshot.libraryRevision >= libraryRevision else { return }
        libraryRevision = snapshot.libraryRevision
        collections = snapshot.collections
        scopeUnavailable = scopeCollectionID.map { id in !snapshot.collections.contains { $0.id == id } } ?? false
        savedLocations = snapshot.locations.filter {
            scopeCollectionID == nil || $0.collectionID == scopeCollectionID
        }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        refreshAnnotationGroups()
        refreshCaptureMatch()
        if let selected = selectedSavedLocation {
            selectedSavedLocation = savedLocations.first { $0.id == selected.id }
            if selectedSavedLocation == nil {
                selectedDetail = nil
                if detailActions.deletingLocationID == selected.id {
                    suppressesCurrentPositionCard = true
                }
                updateRoute()
            }
            else if selectedDetail != nil { selectedDetail = visiblePlace }
        }
        if let request = pendingSavedLocationRequest {
            pendingSavedLocationRequest = nil
            if request.generation == savedFocusGeneration {
                if savedLocations.contains(where: { $0.id == request.id }) {
                    appliedInitialLibrary = true
                    selectSavedLocation(request.id)
                    return
                }
                unavailableSavedLocationEvent &+= 1
            }
        }
        guard !appliedInitialLibrary else { return }
        appliedInitialLibrary = true
        if let initialLocationID { selectSavedLocation(initialLocationID) }
        else if isCollectionMap, !userChangedCamera { fitAll() }
    }

    func requestSavedLocation(id: UUID) {
        savedFocusGeneration &+= 1
        if savedLocations.contains(where: { $0.id == id }) { selectSavedLocation(id) }
        else {
            pendingSavedLocationRequest = MapSavedLocationRequest(id: id, generation: savedFocusGeneration)
        }
    }

    /// Explicit cross-map navigation resolves current data before using a retained projection.
    func resolveSavedLocationRequest(id: UUID) async {
        savedFocusGeneration &+= 1
        let generation = savedFocusGeneration
        pendingSavedLocationRequest = nil
        failedSavedLocationRequest = nil
        await resolveSavedLocationRequest(id: id, generation: generation)
    }

    private func resolveSavedLocationRequest(id: UUID, generation: UInt64, observationRequestID: UUID? = nil) async {
        guard !Task.isCancelled, generation == savedFocusGeneration,
              observationRequestID == nil || observationRequestID == libraryObservationRequestID else { return }
        guard let locationRepository else { requestSavedLocation(id: id); return }
        // Keep this target local: an older observation cannot consume the intent.
        do {
            let snapshot = try await locationRepository.locationSnapshot(collectionID: scopeCollectionID)
            guard !Task.isCancelled, generation == savedFocusGeneration,
                  observationRequestID == nil || observationRequestID == libraryObservationRequestID else { return }
            failedSavedLocationRequest = nil
            if snapshot.libraryRevision >= libraryRevision { applyLibrarySnapshot(snapshot) }
            if savedLocations.contains(where: { $0.id == id }) {
                selectSavedLocation(id)
            } else {
                unavailableSavedLocationEvent &+= 1
            }
        } catch {
            guard !Task.isCancelled, generation == savedFocusGeneration,
                  observationRequestID == nil || observationRequestID == libraryObservationRequestID else { return }
            failedSavedLocationRequest = MapSavedLocationRequest(id: id, generation: generation)
        }
    }

    func selectSavedLocation(_ id: UUID) {
        applySavedLocationSelection(id, preservingPresentedDetail: false)
    }

    private func applySavedLocationSelection(_ id: UUID, preservingPresentedDetail: Bool, focusesCamera: Bool = true) {
        savedFocusGeneration &+= 1
        guard let saved = savedLocations.first(where: { $0.id == id }) else { return }
        let keepsDetail = preservingPresentedDetail && selectedDetail != nil
        clearMapFeatureSelection()
        supersedePendingPositionFocus()
        selectedCandidate = nil
        selectedCandidateSource = nil
        selectedSavedLocation = saved
        selectedDetail = keepsDetail ? quickPlace(for: saved) : nil
        discardCapture()
        suppressesCurrentPositionCard = false
        mapSelection = MapSelection(id)
        if !keepsDetail && focusesCamera {
            focusCamera(on: MapLocationFocus(coordinate: saved.coordinate,
                        generation: operationGeneration, geographicKind: .unknown))
        }
        updateRoute()
        route.setActive(isActive && routeOriginIsAuthorized)
    }

    func fitAll() {
        collectionTemporarySelection = nil
        deletionFallbackCandidate = nil
        savedFocusGeneration &+= 1
        clearMapFeatureSelection()
        supersedePendingPositionFocus()
        selectedCandidate = nil
        selectedCandidateSource = nil
        selectedSavedLocation = nil
        selectedDetail = nil
        discardCapture()
        suppressesCurrentPositionCard = true
        updateRoute()
        guard let region = MapSavedCamera.region(for: savedLocations.map(\.coordinate)) else { return }
        cameraPosition = .region(region)
    }

    /// Freeze a current-position coordinate and its optional address into a draft.
    func prepareCapture(fallbackName: String) {
        if let capture, capture.isEditingSavedLocation, !capture.isCancelled, capture.commit == nil,
           capture.isEditing || capture.isDirty || capture.isSaving { return }
        guard selectedSavedLocation == nil, committedReceipt == nil, let place = visiblePlace,
              let locationRepository, let collectionRepository else { return }
        if capture?.commit != nil { return }
        if let capture, capture.candidate.source == .currentPosition,
           capture.isDirty || capture.isSaving || capture.isEditing { return }
        if let capture, capture.candidate.coordinate == place.coordinate,
           capture.candidate.placeIdentity == place.placeIdentity,
           capture.candidate.address == place.address { return }
        guard let destination = scopeCollectionID ?? collections.first(where: { $0.collection.isDefault })?.id else { return }
        let candidate = selectedCandidate ?? PlaceCandidate(
            id: UUID(), source: .currentPosition, placeIdentity: nil,
            name: fallbackName, address: place.address, category: nil,
            coordinate: place.coordinate, geographicKind: .point
        )
        discardCapture()
        capture = LocationCaptureModel(candidate: candidate, destinationCollectionID: destination,
                                       repository: locationRepository, collectionRepository: collectionRepository,
                                       mediaService: mediaService)
        refreshCaptureMatch()
    }

    /// Editing uses the same scene-owned sheet and keeps the map camera untouched.
    @discardableResult
    func prepareSavedLocationEdit() -> Bool {
        guard let saved = displayedSavedLocation,
              let locationRepository, let collectionRepository else { return false }
        if let capture, capture.isEditingSavedLocation, capture.id == saved.id,
           capture.isEditing, !capture.isCancelled, capture.commit == nil { return true }
        discardCapture()
        if selectedSavedLocation == nil { committedReceipt = saved }
        capture = LocationCaptureModel(savedLocation: saved, repository: locationRepository,
                                       collectionRepository: collectionRepository, mediaService: mediaService)
        return true
    }

    /// Selection changes while a write is suspended cannot receive an old receipt.
    func acceptCaptureCommit(_ completed: LocationCaptureModel) {
        guard capture === completed, let commit = completed.commit else { return }
        if completed.isEditingSavedLocation {
            acceptSavedLocationEdit(commit)
            return
        }
        // A newer observed revision is authoritative, including a record's absence.
        if libraryRevision > commit.libraryRevision {
            if let latest = savedLocations.first(where: { $0.id == commit.location.id }) {
                collectionTemporarySelection = nil
                applySavedLocationSelection(latest.id, preservingPresentedDetail: true)
            } else if scopeCollectionID == nil || commit.location.collectionID == scopeCollectionID {
                if isCollectionMap {
                    collectionTemporarySelection = nil
                    clearMapFeatureSelection()
                    selectedCandidate = nil
                    selectedCandidateSource = nil
                }
                discardCapture()
                selectedDetail = nil
                suppressesCurrentPositionCard = true
                updateRoute()
            } else {
                committedReceipt = commit.location
                collectionTemporarySelection = .receipt(commit.location)
                updateRoute()
                if selectedDetail != nil { selectedDetail = visiblePlace }
            }
            return
        }
        libraryRevision = max(libraryRevision, commit.libraryRevision)
        if scopeCollectionID == nil || commit.location.collectionID == scopeCollectionID {
            collectionTemporarySelection = nil
            if !savedLocations.contains(where: { $0.id == commit.location.id }) {
                savedLocations.append(commit.location)
                savedLocations.sort {
                    if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
            }
            refreshAnnotationGroups()
            applySavedLocationSelection(commit.location.id, preservingPresentedDetail: true)
        } else {
            committedReceipt = commit.location
            collectionTemporarySelection = .receipt(commit.location)
        }
        updateRoute()
        if selectedDetail != nil { selectedDetail = visiblePlace }
    }

    private func acceptSavedLocationEdit(_ commit: LocationCommit) {
        clearMapFeatureSelection()
        selectedCandidate = nil
        selectedCandidateSource = nil
        existingSavedLocationID = nil
        let saved = libraryRevision > commit.libraryRevision
            ? savedLocations.first { $0.id == commit.location.id } : commit.location
        libraryRevision = max(libraryRevision, commit.libraryRevision)
        savedLocations.removeAll { $0.id == commit.location.id }
        if let saved, scopeCollectionID == nil || saved.collectionID == scopeCollectionID {
            savedLocations.append(saved)
            savedLocations.sort {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            selectedSavedLocation = saved
            mapSelection = MapSelection(saved.id)
        } else {
            selectedSavedLocation = nil
            mapSelection = nil
            selectedDetail = nil
            suppressesCurrentPositionCard = true
        }
        capture = nil
        committedReceipt = nil
        collectionTemporarySelection = nil
        refreshAnnotationGroups()
        if selectedDetail != nil { selectedDetail = visiblePlace }
        updateRoute()
    }

    var displayedSavedLocation: SavedLocation? {
        selectedSavedLocation
            ?? savedLocations.first { $0.id == existingSavedLocationID }
            ?? committedReceipt ?? capture?.commit?.location
    }

    /// Apply only a committed patch, preserving selection, camera and route requests.
    func toggleDetailFavorite(_ location: SavedLocation) async {
        guard let commit = await detailActions.toggleFavorite(location),
              commit.libraryRevision >= libraryRevision else { return }
        libraryRevision = commit.libraryRevision
        if let index = savedLocations.firstIndex(where: { $0.id == commit.location.id }) {
            savedLocations[index] = commit.location
        }
        if selectedSavedLocation?.id == commit.location.id { selectedSavedLocation = commit.location }
        if committedReceipt?.id == commit.location.id { committedReceipt = commit.location }
        if case let .receipt(saved) = collectionTemporarySelection, saved.id == commit.location.id {
            collectionTemporarySelection = .receipt(commit.location)
        }
        if capture?.commit?.location.id == commit.location.id, selectedSavedLocation == nil {
            committedReceipt = commit.location
        }
    }

    @discardableResult
    func deleteDetailLocation() async -> Bool {
        let target = detailActions.deleteTarget
        let wasDisplayed = target != nil && displayedSavedLocation?.id == target?.id
        let focusGeneration = savedFocusGeneration
        let featureGeneration = mapFeatureGeneration
        guard let commit = await detailActions.deleteLocation() else { return false }
        // A newer stream revision has already reconciled the logical library.
        if commit.libraryRevision >= libraryRevision {
            libraryRevision = commit.libraryRevision
            savedLocations.removeAll { $0.id == commit.deletedLocationID }
            refreshAnnotationGroups()
        }
        if wasDisplayed, savedFocusGeneration == focusGeneration,
           mapFeatureGeneration == featureGeneration {
            clearMapFeatureSelection()
            selectedSavedLocation = nil
            selectedCandidate = nil
            selectedCandidateSource = nil
            selectedDetail = nil
            committedReceipt = nil
            existingSavedLocationID = nil
            discardCapture()
            let remaining = savedLocations.filter { $0.collectionID == target?.collectionID }
            // Use the deleted item's immutable ordering key against the latest
            // projection, including items inserted while the write was suspended.
            let next = target.flatMap { deleted in
                remaining.first {
                    $0.createdAt < deleted.createdAt
                        || ($0.createdAt == deleted.createdAt && $0.id.uuidString > deleted.id.uuidString)
                }
            } ?? remaining.last
            if let next {
                applySavedLocationSelection(next.id, preservingPresentedDetail: false, focusesCamera: false)
            } else if let candidate = deletionFallbackCandidate {
                selectCandidate(candidate, source: .search, focusesCamera: false)
            } else {
                collectionTemporarySelection = isCollectionMap && currentPosition != nil ? .currentPosition : nil
                suppressesCurrentPositionCard = false
                updateRoute()
            }
        }
        return true
    }

    /// Scoped projections cannot prove an out-of-scope receipt still exists.
    func refreshCommittedReceipt(expectedLibraryRevision: Int64) async {
        guard !Task.isCancelled, libraryRevision == expectedLibraryRevision else { return }
        guard case let .receipt(receipt) = collectionTemporarySelection,
              receipt.collectionID != scopeCollectionID, scopeCollectionID != nil,
              let locationRepository else {
            failedReceiptID = nil
            return
        }
        let requestID = libraryObservationRequestID
        do {
            let current = try await locationRepository.location(id: receipt.id)
            guard !Task.isCancelled, requestID == libraryObservationRequestID,
                  case let .receipt(retained) = collectionTemporarySelection,
                  retained == receipt, libraryRevision == expectedLibraryRevision else { return }
            failedReceiptID = nil
            guard let current else {
                collectionTemporarySelection = nil
                if committedReceipt?.id == receipt.id {
                    // A newer POI tap may still be resolving over this receipt.
                    if mapFeatureTask == nil { clearMapFeatureSelection() }
                    acceptedNativeMapSelection = nil
                    selectedCandidate = nil
                    selectedCandidateSource = nil
                    discardCapture()
                    selectedDetail = nil
                    suppressesCurrentPositionCard = true
                }
                unavailableSavedLocationEvent &+= 1
                updateRoute()
                return
            }
            collectionTemporarySelection = .receipt(current)
            if committedReceipt?.id == receipt.id {
                committedReceipt = current
                if selectedDetail != nil { selectedDetail = quickPlace(for: current) }
            }
            updateRoute()
        } catch {
            guard !Task.isCancelled, requestID == libraryObservationRequestID,
                  case let .receipt(retained) = collectionTemporarySelection,
                  retained == receipt, libraryRevision == expectedLibraryRevision else { return }
            failedReceiptID = receipt.id
        }
    }

    func refreshCaptureMatch() {
        existingSavedLocationID = nil
        guard let capture, capture.commit == nil else { return }
        if case .blockingDuplicate(let id, _) = DuplicatePlacePolicy.evaluate(
            draftID: capture.id, destinationCollectionID: capture.destinationCollectionID,
            candidate: capture.candidate, against: savedLocations
        ) { existingSavedLocationID = id }
    }

    private func discardCapture() {
        existingSavedLocationID = nil
        committedReceipt = nil
        let abandoned = capture
        capture = nil
        // The media owner handles staged cleanup; an in-flight committed write is
        // allowed to settle and cannot change a newer map selection.
        if let abandoned { Task { await abandoned.cancel() } }
    }

    private func refreshAnnotationGroups() {
        let collectionsByID = Dictionary(collections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: savedLocations, by: \.coordinate)
        annotationGroups = grouped.values.compactMap { locations in
            guard let first = locations.first else { return nil }
            let records = locations.map { location in
                let collection = collectionsByID[location.collectionID]
                return MapSavedPinRecord(id: location.id, title: location.name,
                                         collectionName: collection?.collection.name,
                                         createdAt: location.createdAt,
                                         collectionIsDefault: collection?.collection.isDefault ?? false,
                                         collectionLocationCount: collection?.locationCount ?? 0)
            }
            return MapSavedAnnotationGroup(id: first.id, coordinate: first.coordinate, records: records)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
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
        savedFocusGeneration &+= 1
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
        isAcquiringCollectionOrigin = false
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
                if case let .candidate(candidate, .nativePOI, _) = collectionTemporarySelection {
                    collectionTemporarySelection = .candidate(candidate, .nativePOI, nil)
                }
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
        if let id = selection?.value, savedLocations.contains(where: { $0.id == id }) {
            selectSavedLocation(id)
            return
        }
        guard let feature = selection?.feature else { return }
        // Nil/equal/restored native focus is bookkeeping, not a newer destination.
        savedFocusGeneration &+= 1
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
        savedFocusGeneration &+= 1
        deletionFallbackCandidate = source == .search ? candidate : nil
        acceptedNativeMapSelection = source == .nativePOI ? mapSelection : nil
        if isCollectionMap {
            collectionTemporarySelection = .candidate(candidate, source, acceptedNativeMapSelection)
        }
        selectedSavedLocation = nil
        suppressesCurrentPositionCard = false
        discardCapture()
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
        // A collection's background origin enriches whichever saved card settles,
        // including when its first library snapshot arrives after acquisition starts.
        if !isAcquiringCollectionOrigin {
            operationGeneration += 1
            isLocating = false
            isAcquiringLocation = false
        }
        locationFocus = nil
        consumedRecenterRequestID = recenterRequestID
        userChangedCamera = true
    }

    func dismissSearchCandidate() {
        deletionFallbackCandidate = nil
        if isCollectionMap {
            guard collectionTemporarySelection != nil else { return }
            savedFocusGeneration &+= 1
            collectionTemporarySelection = nil
            clearMapFeatureSelection()
            supersedePendingPositionFocus()
            selectedCandidate = nil
            selectedSavedLocation = nil
            selectedCandidateSource = nil
            selectedDetail = nil
            discardCapture()
            suppressesCurrentPositionCard = true
            if let first = savedLocations.first { selectSavedLocation(first.id) }
            else { updateRoute() }
            return
        }
        let dismissesPendingFeature = mapFeatureTask != nil
        clearMapFeatureSelection()
        guard selectedCandidate != nil || selectedSavedLocation != nil || capture?.commit != nil || dismissesPendingFeature else { return }
        selectedCandidate = nil
        selectedSavedLocation = nil
        discardCapture()
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

    /// Scene-owned editing state also restores update mode after a tab/scene pause.
    var isUpdatingDetail: Bool {
        guard let capture else { return false }
        return capture.isEditing && !capture.isCancelled && capture.commit == nil
    }

    /// An in-place editor outlives a record disappearing from the map projection.
    /// Save still validates the original draft/revision and can report a missing record.
    var presentedDetail: MapQuickPlace? {
        if let selectedDetail { return selectedDetail }
        guard isUpdatingDetail, let capture else { return nil }
        let candidate = capture.candidate
        let id: MapQuickPlaceID = capture.isEditingSavedLocation ? .savedLocation(capture.id)
            : candidate.source == .currentPosition ? .currentPosition : .searchCandidate(candidate.id)
        return MapQuickPlace(id: id, name: candidate.name, address: candidate.address,
                            coordinate: candidate.coordinate, horizontalAccuracyMetres: nil,
                            timestamp: nil, placeIdentity: candidate.placeIdentity)
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
        let isPassiveCollectionRequest = isCollectionMap && !isExplicit
        operationGeneration += 1
        let generation = operationGeneration
        let cameraRevision = userCameraChangeRevision
        isAcquiringLocation = true
        isAcquiringCollectionOrigin = isPassiveCollectionRequest
        // Preserve first/no-position feedback without flashing loading over an
        // already usable card while authorization inspection is suspended.
        isLocating = currentPosition == nil && (isExplicit || !initialPositionCompleted)
        defer {
            if generation == operationGeneration {
                isAcquiringLocation = false
                isAcquiringCollectionOrigin = false
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

        // Collection entry may enrich travel facts, but never asks for permission
        // or interrupts the library task with acquisition feedback.
        if isPassiveCollectionRequest,
           !authorization.servicesEnabled || !authorization.status.allowsPosition {
            initialPositionCompleted = true
            return nil
        }

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
            if isCollectionMap { collectionTemporarySelection = .currentPosition }
            deletionFallbackCandidate = nil
            selectedCandidate = nil
            selectedSavedLocation = nil
            discardCapture()
            suppressesCurrentPositionCard = false
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
                if isCollectionMap { collectionTemporarySelection = .currentPosition }
                deletionFallbackCandidate = nil
                selectedCandidate = nil
                selectedSavedLocation = nil
                discardCapture()
                suppressesCurrentPositionCard = false
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
            if !isPassiveCollectionRequest,
               isExplicit ? userCameraChangeRevision == cameraRevision : !userChangedCamera {
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
            if isPassiveCollectionRequest { return nil }
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
