//
//  CollectionLocationActionTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 21/10/26.
//

import Foundation
import Testing
@testable import ProjectAlpha

private enum CollectionLocationActionFixture {
    static let collectionName = "Places"
    static let name = "Museum"
    static let displayName = "Weekend stop"
    static let emptyDisplayName = ""
    static let address = "12 Museum Road"
    static let photoToken = "locations/private-photo.jpg"
    static let latestNotes = "Updated by another scene"
    static let date = Date(timeIntervalSince1970: 100)
}

private actor CollectionLocationActionGate {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
            entered = true
            entryWaiter?.resume()
            entryWaiter = nil
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor CollectionLocationActionMedia: LocationMediaService {
    let finishGate: CollectionLocationActionGate
    private(set) var finished: [UUID] = []
    private(set) var cancelled: [UUID] = []
    private(set) var discarded: [LocalAssetReference] = []

    init(finishGate: CollectionLocationActionGate) { self.finishGate = finishGate }
    func preparePhoto(data: Data, draftID: UUID) async throws -> LocalAssetReference { throw LocationMediaError.storageFailure }
    func photoData(for asset: LocalAssetReference, thumbnail: Bool) async throws -> Data { throw LocationMediaError.storageFailure }
    func discardPhoto(_ asset: LocalAssetReference, draftID: UUID) async { discarded.append(asset) }
    func cancelDraft(id: UUID) async { cancelled.append(id) }
    func finishDraft(id: UUID) async {
        finished.append(id)
        await finishGate.suspend()
    }
}

private actor CollectionLocationActionRepository: LocationRepository {
    private var snapshot: LocationLibrarySnapshot
    private var current: SavedLocation?
    private var deleteFailure: LocationWriteError?
    private(set) var lookupIDs: [UUID] = []
    private(set) var deletions: [DeleteLocationCommand] = []
    private(set) var otherWriteCount = 0
    private var updateGate: CollectionLocationActionGate?
    private var lookupGate: CollectionLocationActionGate?

    init(snapshot: LocationLibrarySnapshot, current: SavedLocation?, deleteFailure: LocationWriteError? = nil) {
        self.snapshot = snapshot
        self.current = current
        self.deleteFailure = deleteFailure
    }

    func allowDeletion() { deleteFailure = nil }
    func allowUpdate(suspendingAt gate: CollectionLocationActionGate) { updateGate = gate }
    func holdLookup(at gate: CollectionLocationActionGate) { lookupGate = gate }
    func removeParentFromSnapshot() {
        snapshot = LocationLibrarySnapshot(collections: [], locations: [], libraryRevision: snapshot.libraryRevision + 1)
    }
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot { snapshot }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        let value = snapshot
        return AsyncThrowingStream { continuation in
            continuation.yield(value)
            continuation.finish()
        }
    }
    func location(id: UUID) async throws -> SavedLocation? {
        lookupIDs.append(id)
        await lookupGate?.suspend()
        return current?.id == id ? current : nil
    }
    func deleteLocation(_ command: DeleteLocationCommand) async throws -> DeleteLocationCommit {
        deletions.append(command)
        if let deleteFailure { throw deleteFailure }
        guard let current, current.id == command.id else { throw LocationWriteError.locationMissing(command.id) }
        guard current.revision == command.expectedRevision else { throw LocationWriteError.editConflict(latest: current) }
        self.current = nil
        return DeleteLocationCommit(deletedLocationID: command.id, libraryRevision: snapshot.libraryRevision + 1)
    }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        otherWriteCount += 1
        throw LocationWriteError.storageFailure
    }
    func updateLocation(_ command: UpdateLocationCommand) async throws -> LocationCommit {
        otherWriteCount += 1
        guard let updateGate, let original = current else { throw LocationWriteError.storageFailure }
        await updateGate.suspend()
        let draft = command.draft
        let updated = SavedLocation(id: original.id, collectionID: draft.destinationCollectionID,
            placeIdentity: original.placeIdentity, source: original.source, name: original.name,
            displayName: draft.displayName, address: original.address, coordinate: original.coordinate,
            category: original.category, notes: draft.notes, assets: draft.assets,
            isFavorite: original.isFavorite, createdAt: original.createdAt,
            updatedAt: CollectionLocationActionFixture.date, revision: original.revision + 1)
        current = updated
        return LocationCommit(location: updated, libraryRevision: snapshot.libraryRevision + 1)
    }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        otherWriteCount += 1
        throw LocationWriteError.storageFailure
    }
}

private struct CollectionLocationActionCollections: CollectionRepository {
    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot {
        throw LocationWriteError.storageFailure
    }
    func snapshot() async throws -> CollectionListSnapshot { throw LocationWriteError.storageFailure }
    func collection(id: UUID) async throws -> CollectionSummary? { nil }
    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        throw LocationWriteError.storageFailure
    }
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        throw LocationWriteError.storageFailure
    }
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit {
        throw LocationWriteError.storageFailure
    }
}

/// P-05, U-04/U-20, D-09/D-13: row actions use the existing editor and explicit destructive workflow.
@MainActor
struct CollectionLocationActionTests {
    /// AC-50/69, D-03/D-17: every list ShareLink stays disabled while the editor owns presentation.
    @Test func shareAvailabilityTracksLoadingPresentedAndDismissingEditor() async throws {
        let original = try location()
        let (detail, repository) = model(original, latest: original)
        #expect(!detail.canShareLocation)
        await detail.observe()
        #expect(detail.canShareLocation)
        let gate = CollectionLocationActionGate()
        await repository.holdLookup(at: gate)
        let loading = Task { await detail.editLocation(original) }
        await gate.waitUntilEntered()
        #expect(!detail.canShareLocation)
        await gate.release()
        await loading.value
        #expect(detail.editor != nil)
        #expect(!detail.canShareLocation)
        detail.editorDidPresent()
        detail.dismissEditor()
        #expect(!detail.canShareLocation)
        detail.editorDidDismiss()
        #expect(detail.canShareLocation)
        #expect(await repository.otherWriteCount == 0)
        #expect(await repository.deletions.isEmpty)
    }

    /// AC-24/50/69, D-03/D-13/D-14: native Share uses the preferred display title and
    /// public location text; extracting it neither resolves a record nor mutates the library.
    @Test(arguments: [nil, CollectionLocationActionFixture.emptyDisplayName,
                      CollectionLocationActionFixture.displayName])
    func sharePayloadContainsPublicFactsWithoutSideEffects(displayName: String?) async throws {
        let asset = try LocalAssetReference(assetID: UUID(), relativeFileToken: CollectionLocationActionFixture.photoToken)
        let original = try location(notes: CollectionLocationActionFixture.latestNotes,
                                    displayName: displayName, address: CollectionLocationActionFixture.address,
                                    assets: [asset])
        let (detail, repository) = model(original, latest: original)
        await detail.observe()
        detail.query = CollectionLocationActionFixture.name
        let filteredBeforeShare = detail.filteredLocations
        let first = detail.sharePayload(for: original)
        let repeated = detail.sharePayload(for: original)
        let expectedTitle = displayName == CollectionLocationActionFixture.displayName
            ? CollectionLocationActionFixture.displayName : original.name
        #expect(first == repeated)
        #expect(first.name == expectedTitle)
        #expect(first.address == original.address)
        #expect(first.coordinate == original.coordinate)
        #expect(first.notes == nil)
        let publicText = first.shareText(includeNotes: false)
        #expect(publicText.contains(expectedTitle))
        #expect(publicText.contains(CollectionLocationActionFixture.address))
        #expect(publicText.contains(first.coordinateText))
        #expect(publicText.contains(first.mapsURL.absoluteString))
        #expect(!publicText.contains(CollectionLocationActionFixture.latestNotes))
        #expect(!publicText.contains(original.id.uuidString))
        #expect(!publicText.contains(asset.assetID.uuidString))
        #expect(!publicText.contains(CollectionLocationActionFixture.photoToken))
        #expect(detail.query == CollectionLocationActionFixture.name)
        #expect(detail.filteredLocations == filteredBeforeShare)
        #expect(detail.editor == nil)
        #expect(detail.deleteTarget == nil)
        #expect(detail.canShareLocation)
        #expect(await repository.lookupIDs.isEmpty)
        #expect(await repository.otherWriteCount == 0)
        #expect(await repository.deletions.isEmpty)
        let unchanged = try await repository.locationSnapshot(collectionID: original.collectionID)
        #expect(unchanged.locations == [original])
    }

    /// AC-50/69, D-17: an outstanding destructive confirmation disables native row Share.
    @Test func shareAvailabilityRecoversAfterDeleteCancellation() async throws {
        let original = try location()
        let (detail, repository) = model(original, latest: original)
        await detail.observe()
        detail.requestDelete(original)
        #expect(!detail.canShareLocation)
        detail.deleteNeedsConfirmation = false
        #expect(detail.canShareLocation)
        #expect(await repository.lookupIDs.isEmpty)
        #expect(await repository.otherWriteCount == 0)
        #expect(await repository.deletions.isEmpty)
    }

    /// AC-50/69, D-03: preparing a native ShareLink payload creates no app-owned
    /// presentation whose dismissal could delay removal of a deleted parent route.
    @Test func parentRemovalAfterSharePayloadExtractionRemovesRouteImmediately() async throws {
        let original = try location()
        let collection = Collection(id: original.collectionID, name: CollectionLocationActionFixture.collectionName,
            isDefault: false, createdAt: CollectionLocationActionFixture.date,
            updatedAt: CollectionLocationActionFixture.date, revision: 1)
        let snapshot = LocationLibrarySnapshot(collections: [CollectionSummary(collection: collection, locationCount: 1)],
            locations: [original], libraryRevision: 3)
        let repository = CollectionLocationActionRepository(snapshot: snapshot, current: original)
        let router = Router<HomeRoute>(paths: [.collection(id: collection.id)], root: .root)
        let detail = CollectionDetailViewModel(collectionID: collection.id,
            repository: CollectionLocationActionCollections(), router: router, locationRepository: repository)
        await detail.observe()
        let payload = detail.sharePayload(for: original)
        await repository.removeParentFromSnapshot()
        await detail.observe()
        #expect(router.paths.isEmpty)
        #expect(!detail.canShareLocation)
        #expect(payload.name == original.name)
        #expect(await repository.otherWriteCount == 0)
        #expect(await repository.deletions.isEmpty)
    }

    private func location(id: UUID = UUID(), collectionID: UUID = UUID(), revision: Int64 = 1,
                          notes: String? = nil, displayName: String? = nil,
                          address: String? = nil, assets: [LocalAssetReference] = []) throws -> SavedLocation {
        SavedLocation(id: id, collectionID: collectionID, placeIdentity: nil, source: .manualCoordinate,
            name: CollectionLocationActionFixture.name, displayName: displayName, address: address,
            coordinate: try Coordinate(latitude: 0, longitude: 0), category: nil, notes: notes,
            assets: assets, isFavorite: false, createdAt: CollectionLocationActionFixture.date,
            updatedAt: CollectionLocationActionFixture.date, revision: revision)
    }

    private func model(_ original: SavedLocation, latest: SavedLocation?, failure: LocationWriteError? = nil)
        -> (CollectionDetailViewModel, CollectionLocationActionRepository) {
        let collection = Collection(id: original.collectionID, name: CollectionLocationActionFixture.collectionName,
            isDefault: true, createdAt: CollectionLocationActionFixture.date,
            updatedAt: CollectionLocationActionFixture.date, revision: 1)
        let snapshot = LocationLibrarySnapshot(collections: [CollectionSummary(collection: collection, locationCount: 1)],
            locations: [original], libraryRevision: 3)
        let repository = CollectionLocationActionRepository(snapshot: snapshot, current: latest, deleteFailure: failure)
        return (CollectionDetailViewModel(collectionID: original.collectionID,
            repository: CollectionLocationActionCollections(), router: Router<HomeRoute>(root: .root),
            locationRepository: repository), repository)
    }

    /// AC-04/42/55, D-13: Edit resolves current values rather than replaying a stale list row or writing.
    @Test func editResolvesLatestRecordAndRepeatedActionKeepsSameEditor() async throws {
        let original = try location()
        let latest = try location(id: original.id, collectionID: original.collectionID, revision: 4,
            notes: CollectionLocationActionFixture.latestNotes)
        let (detail, repository) = model(original, latest: latest)
        await detail.observe()
        await detail.editLocation(original)
        let editor = try #require(detail.editor)
        #expect(editor.id == latest.id)
        #expect(editor.expectedRevision == latest.revision)
        #expect(editor.notes == latest.notes)
        #expect(editor.destinationCollectionID == latest.collectionID)
        #expect(editor.candidate.coordinate == latest.coordinate)
        #expect(!editor.isDirty)
        #expect(detail.actionError == nil)
        #expect(!detail.isPerformingAction)
        await detail.editLocation(original)
        #expect(detail.editor === editor)
        #expect(await repository.lookupIDs == [original.id])
        #expect(await repository.deletions.isEmpty)
        #expect(await repository.otherWriteCount == 0)
    }

    /// AC-04, INV-07: a removed UUID cannot open a new or unrelated editor.
    @Test func missingRecordShowsErrorWithoutOpeningOrWriting() async throws {
        let original = try location()
        let (detail, repository) = model(original, latest: nil)
        await detail.editLocation(original)
        #expect(detail.editor == nil)
        #expect(detail.actionError == .locationMissing(original.id))
        #expect(!detail.isPerformingAction)
        #expect(await repository.lookupIDs == [original.id])
        #expect(await repository.deletions.isEmpty)
        #expect(await repository.otherWriteCount == 0)
    }

    /// D-09, AC-04, INV-05: a cancelled delete cannot become an unrelated failed Edit's retry target.
    @Test func failedEditAfterCancelledDeleteClearsOldDestructiveTarget() async throws {
        let first = try location()
        let second = try location(collectionID: first.collectionID)
        let (detail, repository) = model(first, latest: nil)
        await detail.observe()
        detail.requestDelete(first)
        detail.deleteNeedsConfirmation = false
        await detail.editLocation(second)
        #expect(detail.actionError == .locationMissing(second.id))
        #expect(detail.editor == nil)
        #expect(detail.deleteTarget == nil)
        #expect(!detail.deleteNeedsConfirmation)
        #expect(detail.locations == [first])
        #expect(await repository.lookupIDs == [second.id])
        #expect(await repository.deletions.isEmpty)
        // Even a stale Retry callback cannot delete the previous action's record.
        await detail.deleteLocation()
        #expect(detail.actionError == .locationMissing(second.id))
        #expect(await repository.deletions.isEmpty)
        #expect(await repository.otherWriteCount == 0)
    }

    /// D-09, INV-05: requesting the destructive confirmation does not optimistically remove or write a row.
    @Test func requestDeleteOnlyArmsConfirmationAndPreservesVisibleRow() async throws {
        let original = try location()
        let (detail, repository) = model(original, latest: original)
        await detail.observe()
        detail.requestDelete(original)
        #expect(detail.deleteTarget == original)
        #expect(detail.deleteNeedsConfirmation)
        #expect(detail.locations == [original])
        #expect(detail.filteredLocations == [original])
        #expect(detail.editor == nil)
        #expect(await repository.deletions.isEmpty)
        #expect(await repository.otherWriteCount == 0)
    }

    /// AC-42/55, D-09, INV-07: stale deletion returns latest target without automatically retrying.
    /// Native alert/reconfirmation interaction itself remains a UI acceptance case.
    @Test func staleDeleteRetainsLatestTargetUntilExplicitReconfirmation() async throws {
        let original = try location()
        let latest = try location(id: original.id, collectionID: original.collectionID, revision: 2,
            notes: CollectionLocationActionFixture.latestNotes)
        let (detail, repository) = model(original, latest: latest)
        await detail.observe()
        detail.requestDelete(original)
        detail.deleteNeedsConfirmation = false
        #expect(await detail.deleteLocation() == false)
        #expect(detail.deleteTarget == latest)
        #expect(detail.actionError == .editConflict(latest: latest))
        #expect(!detail.deleteNeedsConfirmation)
        #expect(detail.locations == [original])
        #expect(!detail.isPerformingAction)
        #expect(await repository.deletions == [DeleteLocationCommand(id: original.id, expectedRevision: original.revision)])
        detail.requestDelete(latest)
        #expect(detail.actionError == nil)
        #expect(detail.deleteNeedsConfirmation)
        #expect(await repository.deletions.count == 1)
        detail.deleteNeedsConfirmation = false
        #expect(await detail.deleteLocation() == true)
        #expect(detail.deleteTarget == nil)
        #expect(detail.actionError == nil)
        #expect(await repository.deletions.map(\.expectedRevision) == [original.revision, latest.revision])
    }

    /// INV-05/07, D-09: persistence failure retains the visible row and exact target for explicit retry.
    @Test func failedDeleteRetainsRowAndTargetThenAllowsRetry() async throws {
        let original = try location()
        let (detail, repository) = model(original, latest: original, failure: .storageFailure)
        await detail.observe()
        detail.requestDelete(original)
        detail.deleteNeedsConfirmation = false
        #expect(await detail.deleteLocation() == false)
        #expect(detail.actionError == .storageFailure)
        #expect(detail.deleteTarget == original)
        #expect(detail.locations == [original])
        #expect(detail.filteredLocations == [original])
        #expect(!detail.isPerformingAction)
        await repository.allowDeletion()
        #expect(await detail.deleteLocation() == true)
        #expect(detail.actionError == nil)
        #expect(detail.deleteTarget == nil)
        #expect(!detail.isPerformingAction)
        let command = DeleteLocationCommand(id: original.id, expectedRevision: original.revision)
        #expect(await repository.deletions == [command, command])
        #expect(await repository.otherWriteCount == 0)
    }

    /// AC-04/45/58, INV-05/06/09: committed editor dismissal must not wait for media bookkeeping.
    /// The parent's unavailable route survives until the actual sheet dismissal acknowledgement.
    @Test func committedEditorDismissesWhileMediaFinalizationIsSuspended() async throws {
        let original = try location()
        let updateGate = CollectionLocationActionGate()
        let finishGate = CollectionLocationActionGate()
        let media = CollectionLocationActionMedia(finishGate: finishGate)
        let snapshot = LocationLibrarySnapshot(collections: [], locations: [original], libraryRevision: 3)
        let repository = CollectionLocationActionRepository(snapshot: snapshot, current: original)
        await repository.allowUpdate(suspendingAt: updateGate)
        let router = Router<HomeRoute>(root: .root)
        router.push(.collection(id: original.collectionID))
        let detail = CollectionDetailViewModel(collectionID: original.collectionID,
            repository: CollectionLocationActionCollections(), router: router,
            locationRepository: repository, mediaService: media)
        await detail.editLocation(original)
        let editor = try #require(detail.editor)
        detail.editorDidPresent()
        editor.notes = CollectionLocationActionFixture.latestNotes
        let saving = Task { await editor.save() }
        await updateGate.waitUntilEntered()
        #expect(editor.isSaving)
        #expect(editor.commit == nil)
        detail.dismissEditor()
        #expect(detail.editor === editor)

        await updateGate.release()
        await finishGate.waitUntilEntered()
        #expect(editor.isSaving)
        #expect(editor.commit?.location.id == original.id)
        #expect(editor.commit?.location.notes == CollectionLocationActionFixture.latestNotes)
        await repository.removeParentFromSnapshot()
        await detail.observe()
        #expect(detail.phase == .unavailable)
        #expect(router.paths == [.collection(id: original.collectionID)])
        detail.dismissEditor()
        #expect(detail.editor == nil)
        #expect(router.paths == [.collection(id: original.collectionID)])
        detail.editorDidDismiss()
        #expect(router.paths.isEmpty)
        #expect(await media.finished == [editor.mediaDraftID])
        #expect(await media.cancelled.isEmpty)
        #expect(await media.discarded.isEmpty)
        #expect(!editor.isCancelled)
        await finishGate.release()
        await saving.value
        // A subsequent lifecycle cancellation also preserves the committed media session.
        await editor.cancel()
        #expect(!editor.isSaving)
        #expect(!editor.isCancelled)
        #expect(await media.cancelled.isEmpty)
        #expect(await media.discarded.isEmpty)
        #expect(await repository.otherWriteCount == 1)
    }
}
