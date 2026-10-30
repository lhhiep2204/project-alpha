//
//  CollectionEditorLifetimeTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 21/10/26.
//

import Foundation
import Testing
@testable import ProjectAlpha

private enum EditorLifetimeFixture {
    static let name = "Lifetime place"
    static let collectionName = "Lifetime collection"
    static let notes = "Keep these unsaved notes"
    static let photoToken = "photos/lifetime-staged.jpg"
    static let image = Data([1, 2, 3])
    static let date = Date(timeIntervalSince1970: 100)
}

/// Finite observation batches make each projection application awaitable without polling or clocks.
private actor EditorLifetimeRepository: LocationRepository {
    let original: SavedLocation
    private var projection: LocationLibrarySnapshot
    private var blockLookup = false
    private var lookupContinuation: CheckedContinuation<Void, Never>?
    private var lookupStarted = false
    private var lookupWaiter: CheckedContinuation<Void, Never>?
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var saveStarted = false
    private var saveWaiter: CheckedContinuation<Void, Never>?
    private var saveFails = false
    private(set) var updates: [UpdateLocationCommand] = []
    private(set) var creates: [CreateLocationCommand] = []

    init(original: SavedLocation, projection: LocationLibrarySnapshot) {
        self.original = original
        self.projection = projection
    }
    func project(_ projection: LocationLibrarySnapshot) { self.projection = projection }
    func suspendLookup() { blockLookup = true }
    func waitForLookup() async {
        if lookupStarted { return }
        await withCheckedContinuation { lookupWaiter = $0 }
    }
    func releaseLookup() { lookupContinuation?.resume(); lookupContinuation = nil }
    func waitForSave() async {
        if saveStarted { return }
        await withCheckedContinuation { saveWaiter = $0 }
    }
    func releaseSave(failing: Bool) {
        saveFails = failing
        saveContinuation?.resume()
        saveContinuation = nil
    }
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot { projection }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        let value = projection
        return AsyncThrowingStream { continuation in
            continuation.yield(value)
            continuation.finish()
        }
    }
    func location(id: UUID) async throws -> SavedLocation? {
        if blockLookup {
            await withCheckedContinuation { continuation in
                lookupContinuation = continuation
                lookupStarted = true
                lookupWaiter?.resume()
                lookupWaiter = nil
            }
        }
        return original.id == id ? original : nil
    }
    func updateLocation(_ command: UpdateLocationCommand) async throws -> LocationCommit {
        updates.append(command)
        await withCheckedContinuation { continuation in
            saveContinuation = continuation
            saveStarted = true
            saveWaiter?.resume()
            saveWaiter = nil
        }
        if saveFails { throw LocationWriteError.destinationMissing(original.collectionID) }
        let draft = command.draft
        return LocationCommit(location: SavedLocation(id: original.id,
            collectionID: draft.destinationCollectionID, placeIdentity: original.placeIdentity,
            source: original.source, name: original.name, displayName: draft.displayName,
            address: original.address, coordinate: original.coordinate, category: original.category,
            notes: draft.notes, assets: draft.assets, isFavorite: original.isFavorite,
            createdAt: original.createdAt, updatedAt: original.updatedAt,
            revision: original.revision + 1), libraryRevision: 3)
    }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        creates.append(command)
        throw LocationWriteError.storageFailure
    }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageFailure
    }
}

private struct EditorLifetimeCollections: CollectionRepository {
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

private actor EditorLifetimeMedia: LocationMediaService {
    let asset: LocalAssetReference
    private(set) var cancelled: [UUID] = []
    private(set) var finished: [UUID] = []
    private var cancellationWaiter: CheckedContinuation<Void, Never>?
    init() throws {
        asset = try LocalAssetReference(assetID: UUID(), relativeFileToken: EditorLifetimeFixture.photoToken)
    }
    func preparePhoto(data: Data, draftID: UUID) async throws -> LocalAssetReference { asset }
    func photoData(for asset: LocalAssetReference, thumbnail: Bool) async throws -> Data { EditorLifetimeFixture.image }
    func discardPhoto(_ asset: LocalAssetReference, draftID: UUID) async {}
    func cancelDraft(id: UUID) async {
        cancelled.append(id)
        cancellationWaiter?.resume()
        cancellationWaiter = nil
    }
    func finishDraft(id: UUID) async { finished.append(id) }
    func waitForCancellation() async {
        if !cancelled.isEmpty { return }
        await withCheckedContinuation { cancellationWaiter = $0 }
    }
}

/// P-05, AC-45 and docs 02/05: parent route pruning must respect the editor's lifetime.
/// These model tests do not establish actual SwiftUI sheet dismissal or device evidence.
@MainActor
struct CollectionEditorLifetimeTests {
    private struct Harness {
        let saved: SavedLocation
        let detail: CollectionDetailViewModel
        let router: Router<HomeRoute>
        let repository: EditorLifetimeRepository
        let media: EditorLifetimeMedia
        let unrelatedRoute: HomeRoute
    }

    private func harness() throws -> Harness {
        let saved = SavedLocation(id: UUID(), collectionID: UUID(), placeIdentity: nil,
            source: .manualCoordinate, name: EditorLifetimeFixture.name, displayName: nil,
            address: nil, coordinate: try Coordinate(latitude: 0, longitude: 0), category: nil,
            notes: nil, assets: [], isFavorite: false, createdAt: EditorLifetimeFixture.date,
            updatedAt: EditorLifetimeFixture.date, revision: 1)
        let collection = Collection(id: saved.collectionID, name: EditorLifetimeFixture.collectionName,
            isDefault: false, createdAt: EditorLifetimeFixture.date, updatedAt: EditorLifetimeFixture.date, revision: 1)
        let projection = LocationLibrarySnapshot(collections: [CollectionSummary(collection: collection, locationCount: 1)],
            locations: [saved], libraryRevision: 1)
        let repository = EditorLifetimeRepository(original: saved, projection: projection)
        let unrelatedRoute = HomeRoute.collection(id: UUID())
        let router = Router<HomeRoute>(paths: [unrelatedRoute, .collection(id: saved.collectionID)], root: .root)
        let media = try EditorLifetimeMedia()
        return Harness(saved: saved, detail: CollectionDetailViewModel(collectionID: saved.collectionID,
            repository: EditorLifetimeCollections(), router: router, locationRepository: repository,
            mediaService: media), router: router, repository: repository, media: media, unrelatedRoute: unrelatedRoute)
    }

    private func removeParent(_ harness: Harness, revision: Int64 = 2) async {
        await harness.repository.project(LocationLibrarySnapshot(collections: [], locations: [], libraryRevision: revision))
        await harness.detail.observe()
    }

    /// AC-23/45, INV-08/09: missing-parent projections cannot discard dirty fields or staged photos.
    @Test func dirtyEditorSurvivesMissingParentUntilExplicitDiscardAndDismissal() async throws {
        let h = try harness()
        await h.detail.observe()
        await h.detail.editLocation(h.saved)
        let editor = try #require(h.detail.editor)
        h.detail.editorDidPresent()
        editor.notes = EditorLifetimeFixture.notes
        await editor.importPhoto(data: EditorLifetimeFixture.image)
        let draft = editor.draft
        let mediaID = editor.mediaDraftID
        let paths = h.router.paths
        await removeParent(h)
        await removeParent(h, revision: 3)
        #expect(h.detail.editor === editor)
        #expect(editor.draft == draft)
        #expect(editor.mediaDraftID == mediaID)
        #expect(editor.assets == [h.media.asset])
        #expect(h.router.paths == paths)
        #expect(!editor.isCancelled)
        #expect(await h.media.cancelled.isEmpty)
        #expect(await h.repository.updates.isEmpty)
        h.detail.dismissEditor()
        #expect(h.detail.editor == nil)
        #expect(h.router.paths == paths)
        await h.media.waitForCancellation()
        #expect(editor.isCancelled)
        #expect(await h.media.cancelled == [mediaID])
        h.detail.editorDidDismiss()
        #expect(h.router.paths == [h.unrelatedRoute])
        h.detail.editorDidDismiss()
        #expect(h.router.paths == [h.unrelatedRoute])
    }

    /// AC-45, docs 05 missing-entity path: clean editor dismissal completes before its parent route is pruned.
    @Test func cleanEditorWaitsForSheetDismissalBeforeTrimmingMissingParent() async throws {
        let h = try harness()
        await h.detail.observe()
        await h.detail.editLocation(h.saved)
        let editor = try #require(h.detail.editor)
        h.detail.editorDidPresent()
        let paths = h.router.paths
        #expect(!editor.isDirty)
        await removeParent(h)
        #expect(h.detail.editor == nil)
        #expect(h.router.paths == paths)
        h.detail.editorDidDismiss()
        #expect(h.router.paths == [h.unrelatedRoute])
        await h.media.waitForCancellation()
        #expect(editor.isCancelled)
        #expect(await h.repository.updates.isEmpty)
    }

    /// AC-45, docs 05: an editor created and invalidated before appearing has no dismissal to await.
    @Test func cleanNeverPresentedEditorDoesNotStrandMissingParentRoute() async throws {
        let h = try harness()
        await h.detail.observe()
        await h.detail.editLocation(h.saved)
        let editor = try #require(h.detail.editor)
        #expect(!editor.isDirty)
        await removeParent(h)
        #expect(h.detail.editor == nil)
        #expect(h.router.paths == [h.unrelatedRoute])
        await h.media.waitForCancellation()
        #expect(editor.isCancelled)
        #expect(await h.repository.updates.isEmpty)
        // No sheet appeared, so no editorDidDismiss callback is needed to release the route.
    }

    /// Docs 05 restore/missing-target behavior: no editor means no reason to retain an invalid route.
    @Test func missingParentWithoutEditorTrimsOnlyItsOwnRoute() async throws {
        let h = try harness()
        await h.detail.observe()
        await removeParent(h)
        #expect(h.detail.editor == nil)
        #expect(h.detail.phase == .unavailable)
        #expect(h.router.paths == [h.unrelatedRoute])
        #expect(await h.media.cancelled.isEmpty)
        #expect(await h.repository.updates.isEmpty)
    }

    /// AC-45, INV-07/08: an in-flight commit owns the sheet; failure keeps the same recoverable draft.
    @Test(arguments: [false, true], [false, true])
    func missingParentDuringSavePreservesOwnerUntilResultAndExplicitDismissal(failing: Bool, dirty: Bool) async throws {
        let h = try harness()
        await h.detail.observe()
        await h.detail.editLocation(h.saved)
        let editor = try #require(h.detail.editor)
        h.detail.editorDidPresent()
        if dirty {
            editor.notes = EditorLifetimeFixture.notes
            await editor.importPhoto(data: EditorLifetimeFixture.image)
        }
        #expect(editor.isDirty == dirty)
        let draft = editor.draft
        let paths = h.router.paths
        let saving = Task { await editor.save() }
        await h.repository.waitForSave()
        await removeParent(h)
        #expect(editor.isSaving)
        h.detail.dismissEditor()
        #expect(h.detail.editor === editor)
        #expect(editor.draft == draft)
        #expect(h.router.paths == paths)
        #expect(await h.media.cancelled.isEmpty)
        await h.repository.releaseSave(failing: failing)
        await saving.value
        #expect(!editor.isSaving)
        #expect(h.detail.editor === editor)
        #expect(h.router.paths == paths)
        #expect(await h.repository.updates.map(\.draft) == [draft])
        #expect(await h.repository.creates.isEmpty)
        if failing {
            #expect(editor.commit == nil)
            #expect(editor.saveError == .destinationMissing(h.saved.collectionID))
            #expect(editor.draft == draft)
            #expect(await h.media.finished.isEmpty)
        } else {
            #expect(editor.commit?.location.id == h.saved.id)
            #expect(editor.commit?.location.assets == draft.assets)
            #expect(await h.media.finished == [editor.mediaDraftID])
        }
        h.detail.dismissEditor()
        #expect(h.router.paths == paths)
        h.detail.editorDidDismiss()
        #expect(h.router.paths == [h.unrelatedRoute])
        if failing { await h.media.waitForCancellation() }
        else { #expect(await h.media.cancelled.isEmpty) }
    }


    /// AC-45, docs 05: newer valid data cancels deferred pruning while the same draft remains owned.
    @Test func reappearingParentCancelsDeferredRemovalBeforeEditorDismisses() async throws {
        let h = try harness()
        await h.detail.observe()
        await h.detail.editLocation(h.saved)
        let editor = try #require(h.detail.editor)
        h.detail.editorDidPresent()
        editor.notes = EditorLifetimeFixture.notes
        let paths = h.router.paths
        await removeParent(h)
        let collection = Collection(id: h.saved.collectionID, name: EditorLifetimeFixture.collectionName,
            isDefault: false, createdAt: EditorLifetimeFixture.date, updatedAt: EditorLifetimeFixture.date, revision: 2)
        await h.repository.project(LocationLibrarySnapshot(
            collections: [CollectionSummary(collection: collection, locationCount: 1)],
            locations: [h.saved], libraryRevision: 3))
        await h.detail.observe()
        #expect(h.detail.phase == .ready)
        #expect(h.detail.editor === editor)
        #expect(editor.notes == EditorLifetimeFixture.notes)
        h.detail.dismissEditor()
        h.detail.editorDidDismiss()
        #expect(h.router.paths == paths)
        await h.media.waitForCancellation()
        #expect(await h.repository.updates.isEmpty)
    }

    /// AC-45, docs 05 missing-route policy: a late lookup cannot reopen an editor after parent deletion.
    @Test func missingParentDuringLookupWaitsThenRejectsLateEditor() async throws {
        let h = try harness()
        await h.detail.observe()
        await h.repository.suspendLookup()
        let opening = Task { await h.detail.editLocation(h.saved) }
        await h.repository.waitForLookup()
        let paths = h.router.paths
        await removeParent(h)
        #expect(h.detail.editor == nil)
        #expect(h.router.paths == paths)
        await h.repository.releaseLookup()
        await opening.value
        #expect(h.detail.editor == nil)
        #expect(!h.detail.isPerformingAction)
        #expect(h.router.paths == [h.unrelatedRoute])
        #expect(await h.repository.updates.isEmpty)
        #expect(await h.media.cancelled.isEmpty)
    }
}
