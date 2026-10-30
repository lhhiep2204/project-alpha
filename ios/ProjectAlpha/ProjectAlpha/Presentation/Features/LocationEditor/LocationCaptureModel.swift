//
//  LocationCaptureModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation
import Observation

/// One scene-owned capture survives optional details, destination changes and failed writes.
@MainActor
@Observable
final class LocationCaptureModel {
    let id: UUID
    let createdAt: Date
    let mediaDraftID: UUID
    private(set) var candidate: PlaceCandidate
    let collectionRepository: any CollectionRepository
    private let repository: any LocationRepository
    private let mediaService: (any LocationMediaService)?
    private var originalDestinationID: UUID
    private var originalLocation: SavedLocation?
    private(set) var expectedRevision: Int64?
    var isEditingSavedLocation: Bool { originalLocation != nil }
    private var selectedDestinationID: UUID
    private var enteredDisplayName = String()
    private var enteredNotes = String()
    var destinationCollectionID: UUID {
        get { selectedDestinationID }
        set {
            guard !isSaving, commit == nil, selectedDestinationID != newValue else { return }
            selectedDestinationID = newValue
            clearError()
        }
    }
    var displayName: String {
        get { enteredDisplayName }
        set { guard !isSaving, commit == nil else { return }; enteredDisplayName = newValue }
    }
    var notes: String {
        get { enteredNotes }
        set { guard !isSaving, commit == nil else { return }; enteredNotes = newValue }
    }
    private(set) var assets: [LocalAssetReference] = []
    private(set) var collections: [CollectionSummary] = []
    private(set) var collectionLoadFailed = false
    private(set) var collectionObservationRequestID = UUID()
    private(set) var isSaving = false
    private(set) var isImportingPhoto = false
    private(set) var photoImportFailed = false
    private(set) var commit: LocationCommit?
    private(set) var saveError: LocationWriteError?
    private(set) var duplicateMatches: [SavedLocation] = []
    @ObservationIgnored private var collectionObservationGeneration: UInt64 = 0
    private var cancelled = false
    var isCancelled: Bool { cancelled }
    private var editingOwners: Set<UUID> = []
    private static let defaultEditingOwner = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    var isEditing: Bool { !editingOwners.isEmpty }

    func beginEditing(ownerID: UUID? = nil) {
        if !cancelled { editingOwners.insert(ownerID ?? Self.defaultEditingOwner) }
    }
    func endEditing(ownerID: UUID? = nil) {
        editingOwners.remove(ownerID ?? Self.defaultEditingOwner)
    }
    func endAllEditing() {
        if !isDirty && !isSaving { editingOwners.removeAll() }
    }
    private var photoSelectionGeneration: UInt64 = 0
    private(set) var isLoadingPhotoSelection = false
    var photoService: (any LocationMediaService)? { mediaService }

    init(candidate: PlaceCandidate, destinationCollectionID: UUID,
         repository: any LocationRepository, collectionRepository: any CollectionRepository,
         mediaService: (any LocationMediaService)? = nil,
         id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        mediaDraftID = id
        self.createdAt = createdAt
        self.candidate = candidate
        selectedDestinationID = destinationCollectionID
        originalDestinationID = destinationCollectionID
        self.repository = repository
        self.collectionRepository = collectionRepository
        self.mediaService = mediaService
    }

    init(savedLocation: SavedLocation, repository: any LocationRepository,
         collectionRepository: any CollectionRepository, mediaService: (any LocationMediaService)? = nil,
         mediaDraftID: UUID = UUID()) {
        id = savedLocation.id
        self.mediaDraftID = mediaDraftID
        createdAt = savedLocation.createdAt
        candidate = Self.candidate(for: savedLocation)
        selectedDestinationID = savedLocation.collectionID
        originalDestinationID = savedLocation.collectionID
        originalLocation = savedLocation
        expectedRevision = savedLocation.revision
        enteredDisplayName = savedLocation.displayName ?? String()
        enteredNotes = savedLocation.notes ?? String()
        assets = savedLocation.assets
        self.repository = repository
        self.collectionRepository = collectionRepository
        self.mediaService = mediaService
    }

    private static func candidate(for location: SavedLocation) -> PlaceCandidate {
        PlaceCandidate(id: location.id, source: location.source, placeIdentity: location.placeIdentity,
                       name: location.name, address: location.address, category: location.category,
                       coordinate: location.coordinate)
    }

    var draft: LocationDraft {
        LocationDraft(id: id, candidate: candidate, destinationCollectionID: destinationCollectionID,
                      displayName: displayName, notes: notes, assets: assets, createdAt: createdAt)
    }
    var isDirty: Bool {
        if let originalLocation {
            return displayName != (originalLocation.displayName ?? String())
                || notes != (originalLocation.notes ?? String()) || assets != originalLocation.assets
                || destinationCollectionID != originalLocation.collectionID || isLoadingPhotoSelection || isImportingPhoto
        }
        return !displayName.isEmpty || !notes.isEmpty || !assets.isEmpty || isLoadingPhotoSelection || isImportingPhoto || destinationCollectionID != originalDestinationID
    }
    var destinationName: String? { collections.first { $0.id == destinationCollectionID }?.collection.name }
    var destinationIsDefault: Bool { collections.first { $0.id == destinationCollectionID }?.collection.isDefault == true }
    var remainingPhotoCapacity: Int { max(0, LocationDraftPolicy.maximumPhotoCount - assets.count) }
    var canImportPhotos: Bool {
        mediaService != nil && remainingPhotoCapacity > 0 && !isSaving && !isImportingPhoto && !cancelled && commit == nil
    }
    var canSave: Bool {
        !cancelled && commit == nil && !isSaving && !isImportingPhoto && !isLoadingPhotoSelection
            && collections.contains { $0.id == destinationCollectionID }
    }

    /// The editor's structured task owns the stream, including retries requested by child pickers.
    func retryCollectionObservation() {
        guard !cancelled else { return }
        collectionObservationRequestID = UUID()
    }

    func observeCollections() async {
        guard !cancelled, !Task.isCancelled else { return }
        let requestID = collectionObservationRequestID
        collectionObservationGeneration &+= 1
        let generation = collectionObservationGeneration
        do {
            let stream = await collectionRepository.observeSnapshots()
            for try await snapshot in stream {
                guard !Task.isCancelled, !cancelled,
                      requestID == collectionObservationRequestID,
                      generation == collectionObservationGeneration else { return }
                collections = snapshot.collections
                collectionLoadFailed = false
            }
        } catch {
            guard !Task.isCancelled, !cancelled,
                  requestID == collectionObservationRequestID,
                  generation == collectionObservationGeneration else { return }
            collectionLoadFailed = true
        }
    }

    func save() async { await performSave(acknowledgedWarning: nil) }
    func acknowledgeWarningAndSave() async {
        guard case .possibleDuplicates(_, let token) = saveError else { return }
        await performSave(acknowledgedWarning: token)
    }
    private func performSave(acknowledgedWarning: DuplicateWarningToken?) async {
        guard !isSaving, !isImportingPhoto, !isLoadingPhotoSelection, !cancelled, commit == nil else { return }
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        do {
            let result: LocationCommit
            if let expectedRevision {
                result = try await repository.updateLocation(UpdateLocationCommand(
                    draft: draft, expectedRevision: expectedRevision, acknowledgedWarning: acknowledgedWarning))
            } else {
                result = try await repository.createLocation(CreateLocationCommand(
                    draft: draft, acknowledgedWarning: acknowledgedWarning))
            }
            commit = result
            await mediaService?.finishDraft(id: mediaDraftID)
        } catch let error as LocationWriteError {
            saveError = error
            let ids: [UUID]
            switch error {
            case .blockingDuplicate(let id, _): ids = [id]
            case .possibleDuplicates(let candidateIDs, _): ids = candidateIDs
            default: ids = []
            }
            duplicateMatches.removeAll()
            for id in ids {
                if let location = try? await repository.location(id: id) { duplicateMatches.append(location) }
            }
        }
        catch { saveError = .storageFailure }
    }
    func clearError() { saveError = nil; duplicateMatches.removeAll() }
    /// Closing optional details discards those edits, while the accepted candidate stays saveable.
    func discardDetails() async {
        guard !isSaving, commit == nil else { return }
        photoSelectionGeneration &+= 1
        isLoadingPhotoSelection = false
        editingOwners.removeAll()
        let discardedAssets = stagedAssets
        assets = originalLocation?.assets ?? []
        displayName = originalLocation?.displayName ?? String()
        notes = originalLocation?.notes ?? String()
        destinationCollectionID = originalDestinationID
        clearError()
        for asset in discardedAssets { await mediaService?.discardPhoto(asset, draftID: mediaDraftID) }
    }
    func beginPhotoSelection() -> UInt64? {
        guard !isSaving, !isImportingPhoto, !isLoadingPhotoSelection, !cancelled, commit == nil else { return nil }
        photoSelectionGeneration &+= 1
        isLoadingPhotoSelection = true
        photoImportFailed = false
        return photoSelectionGeneration
    }
    func finishPhotoSelection(generation: UInt64) {
        if generation == photoSelectionGeneration { isLoadingPhotoSelection = false }
    }
    func acceptsPhotoSelection(generation: UInt64) -> Bool {
        !cancelled && generation == photoSelectionGeneration
    }
    func importPhoto(data: Data, selectionGeneration: UInt64? = nil) async {
        guard canImportPhotos, let mediaService, !cancelled,
              selectionGeneration == nil || selectionGeneration == photoSelectionGeneration else { return }
        let generation = photoSelectionGeneration
        isImportingPhoto = true
        if !isLoadingPhotoSelection { photoImportFailed = false }
        defer { isImportingPhoto = false }
        do {
            let asset = try await mediaService.preparePhoto(data: data, draftID: mediaDraftID)
            if cancelled || generation != photoSelectionGeneration { await mediaService.discardPhoto(asset, draftID: mediaDraftID) }
            else { assets.append(asset) }
        } catch { photoImportFailed = true }
    }
    func reportPhotoImportFailure() { photoImportFailed = true }
    func removePhoto(_ asset: LocalAssetReference) async {
        guard !isSaving, !isImportingPhoto, commit == nil else { return }
        assets.removeAll { $0.assetID == asset.assetID }
        if originalLocation?.assets.contains(where: { $0.assetID == asset.assetID }) != true {
            await mediaService?.discardPhoto(asset, draftID: mediaDraftID)
        }
    }
    private var stagedAssets: [LocalAssetReference] {
        let originalIDs = Set(originalLocation?.assets.map(\.assetID) ?? [])
        return assets.filter { !originalIDs.contains($0.assetID) }
    }

    func reloadConflict() async {
        guard case .editConflict(let latest) = saveError, !isSaving else { return }
        let discarded = stagedAssets
        photoSelectionGeneration &+= 1
        isLoadingPhotoSelection = false
        originalLocation = latest
        expectedRevision = latest.revision
        originalDestinationID = latest.collectionID
        selectedDestinationID = latest.collectionID
        candidate = Self.candidate(for: latest)
        enteredDisplayName = latest.displayName ?? String()
        enteredNotes = latest.notes ?? String()
        assets = latest.assets
        clearError()
        for asset in discarded { await mediaService?.discardPhoto(asset, draftID: mediaDraftID) }
    }

    func reapplyConflict() async {
        guard case .editConflict(let latest) = saveError, !isSaving else { return }
        expectedRevision = latest.revision
        // Only editable draft fields are reapplied; source identity stays current.
        candidate = Self.candidate(for: latest)
        await save()
    }

    func cancel() async {
        guard !isSaving, commit == nil else { return }
        cancelled = true
        photoSelectionGeneration &+= 1
        isLoadingPhotoSelection = false
        await mediaService?.cancelDraft(id: mediaDraftID)
        assets.removeAll()
    }
}
