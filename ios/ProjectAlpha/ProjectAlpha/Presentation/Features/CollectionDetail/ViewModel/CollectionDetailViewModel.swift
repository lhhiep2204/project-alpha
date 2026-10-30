//
//  CollectionDetailViewModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 26/9/26.
//

import Foundation

@MainActor
@Observable
final class CollectionDetailViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case unavailable
        case failed
    }

    let collectionID: UUID
    private let repository: any CollectionRepository
    private let router: Router<HomeRoute>
    private let mediaService: (any LocationMediaService)?
    private let locationRepository: (any LocationRepository)?
    private(set) var locations: [SavedLocation] = []
    private(set) var filteredLocations: [SavedLocation] = []
    var query = String() { didSet { filterLocations() } }
    var favoritesOnly = false { didSet { filterLocations() } }
    private(set) var favoriteFailed = false
    var editor: LocationCaptureModel?
    private(set) var isPerformingAction = false
    var actionError: LocationWriteError?
    var deleteTarget: SavedLocation?
    var deleteNeedsConfirmation = false
    private(set) var collection: CollectionSummary?
    private(set) var phase: Phase = .loading
    private var libraryRevision: Int64 = -1
    @ObservationIgnored private var observationGeneration = 0
    private var isLoadingEditor = false
    private var isEditorPresented = false
    private var isAwaitingEditorDismissal = false
    private var needsUnavailableRouteRemoval = false

    init(collectionID: UUID, repository: any CollectionRepository, router: Router<HomeRoute>,
         locationRepository: (any LocationRepository)? = nil, mediaService: (any LocationMediaService)? = nil) {
        self.collectionID = collectionID
        self.repository = repository
        self.router = router
        self.locationRepository = locationRepository
        self.mediaService = mediaService
    }

    func displayTitle(hint: String?) -> String {
        guard phase != .unavailable else { return String() }
        return collection?.collection.name ?? hint ?? String()
    }

    func observe(onUnavailable: @MainActor () -> Void = {}) async {
        guard !Task.isCancelled else { return }
        observationGeneration &+= 1
        let generation = observationGeneration
        // A lifecycle restart keeps the last committed content usable until fresh data arrives.
        if phase != .ready {
            phase = .loading
        }
        do {
            if let locationRepository {
                let stream = await locationRepository.observeLocations(collectionID: collectionID)
                for try await snapshot in stream {
                    guard !Task.isCancelled, generation == observationGeneration else { return }
                    guard snapshot.libraryRevision >= libraryRevision else { continue }
                    locations = snapshot.locations
                    filterLocations()
                    applyCollections(snapshot.collections, revision: snapshot.libraryRevision, onUnavailable: onUnavailable)
                    if phase == .unavailable { return }
                }
                return
            }
            let stream = await repository.observeSnapshots()
            guard !Task.isCancelled, generation == observationGeneration else { return }
            for try await snapshot in stream {
                guard !Task.isCancelled, generation == observationGeneration else { return }
                guard snapshot.libraryRevision >= libraryRevision else { continue }
                applyCollections(snapshot.collections, revision: snapshot.libraryRevision, onUnavailable: onUnavailable)
                if phase == .unavailable { return }
            }
        } catch {
            guard !Task.isCancelled, generation == observationGeneration else { return }
            phase = .failed
        }
    }

    func toggleFavorite(_ location: SavedLocation) async {
        guard let locationRepository else { return }
        favoriteFailed = false
        do {
            _ = try await locationRepository.setLocationFavorite(
                SetLocationFavoriteCommand(id: location.id, isFavorite: !location.isFavorite, updatedAt: .now)
            )
        } catch { favoriteFailed = true }
    }

    func editLocation(_ location: SavedLocation) async {
        guard let locationRepository, !isPerformingAction, editor == nil,
              phase != .unavailable, !isAwaitingEditorDismissal else { return }
        isPerformingAction = true
        isLoadingEditor = true
        actionError = nil
        deleteTarget = nil
        deleteNeedsConfirmation = false
        defer {
            isPerformingAction = false
            isLoadingEditor = false
            finishUnavailableRouteRemoval()
        }
        do {
            guard let latest = try await locationRepository.location(id: location.id) else {
                throw LocationWriteError.locationMissing(location.id)
            }
            guard !Task.isCancelled, phase != .unavailable else { return }
            editor = LocationCaptureModel(savedLocation: latest, repository: locationRepository,
                                          collectionRepository: repository, mediaService: mediaService)
        } catch { actionError = (error as? LocationWriteError) ?? .storageFailure }
    }

    func dismissEditor() {
        guard let closing = editor, !closing.isSaving || closing.commit != nil else { return }
        isAwaitingEditorDismissal = isEditorPresented
        editor = nil
        Task { await closing.cancel() }
        finishUnavailableRouteRemoval()
    }

    func editorDidPresent() {
        guard editor != nil else { return }
        isEditorPresented = true
    }

    /// The parent destination must survive the sheet's dismissal transition.
    func editorDidDismiss() {
        isEditorPresented = false
        isAwaitingEditorDismissal = false
        finishUnavailableRouteRemoval()
    }

    var canShareLocation: Bool {
        phase == .ready && !isPerformingAction && editor == nil && !isAwaitingEditorDismissal
            && !deleteNeedsConfirmation && actionError == nil
    }

    func sharePayload(for location: SavedLocation) -> LocationDetailPayload {
        LocationDetailPayload(
            name: location.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? location.name,
            address: location.address, coordinate: location.coordinate, notes: nil)
    }

    func requestDelete(_ location: SavedLocation) {
        guard !isPerformingAction else { return }
        actionError = nil
        deleteTarget = location
        deleteNeedsConfirmation = true
    }

    @discardableResult
    func deleteLocation() async -> Bool {
        guard let locationRepository, let target = deleteTarget, !isPerformingAction else { return false }
        isPerformingAction = true
        actionError = nil
        defer { isPerformingAction = false }
        do {
            _ = try await locationRepository.deleteLocation(DeleteLocationCommand(
                id: target.id, expectedRevision: target.revision))
            deleteTarget = nil
            return true
        } catch LocationWriteError.editConflict(let latest) {
            deleteTarget = latest
            actionError = .editConflict(latest: latest)
        } catch {
            actionError = (error as? LocationWriteError) ?? .storageFailure
        }
        return false
    }

    private func filterLocations() {
        filteredLocations = locations.filter { location in
            (!favoritesOnly || location.isFavorite) &&
            (query.isEmpty || location.name.localizedStandardContains(query) ||
             location.displayName?.localizedStandardContains(query) == true ||
             location.address?.localizedStandardContains(query) == true)
        }
    }

    private func applyCollections(_ collections: [CollectionSummary], revision: Int64,
                                  onUnavailable: @MainActor () -> Void) {
        libraryRevision = revision
        collection = collections.first { $0.id == collectionID }
        phase = collection == nil ? .unavailable : .ready
        needsUnavailableRouteRemoval = collection == nil
        if collection == nil {
            onUnavailable()
            if let editor, !editor.isDirty, !editor.isSaving {
                dismissEditor()
            }
            finishUnavailableRouteRemoval()
        }
    }

    private func finishUnavailableRouteRemoval() {
        guard needsUnavailableRouteRemoval, editor == nil,
              !isLoadingEditor, !isAwaitingEditorDismissal else { return }
        needsUnavailableRouteRemoval = false
        router.paths.removeAll { route in
            if case .collection(let id) = route { return id == collectionID }
            return false
        }
    }
}
