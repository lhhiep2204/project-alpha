//
//  LocationDeleteTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 21/10/26.
//

import Foundation
import SwiftData
import Testing
@testable import ProjectAlpha

private enum DeleteLocationFixture {
    static let collectionName = "Saved places"
    static let locationName = "Museum"
    static let otherName = "Library"
    static let photoToken = "photos/delete-location.jpg"
    static let contentType = "image/jpeg"
    static let createdAt = Date(timeIntervalSince1970: 100)
    static let deletedAt = Date(timeIntervalSince1970: 200)
}

private enum DeleteLocationFailure: Error { case save }

/// P-05, D-09, INV-02/05/06/07: deletion uses the actual serialized writer and persisted reloads.
@MainActor
struct LocationDeleteTests {
    private func setup(photo: Bool = false) async throws -> (ModelContainer, LibraryStore, SavedLocation) {
        let container = try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
        let store = LibraryStore(container: container, currentDate: { DeleteLocationFixture.deletedAt })
        let collectionID = UUID()
        _ = try await store.bootstrap(BootstrapCollectionCommand(id: collectionID,
            name: DeleteLocationFixture.collectionName, createdAt: DeleteLocationFixture.createdAt))
        var assets: [LocalAssetReference] = []
        if photo {
            let reference = try LocalAssetReference(assetID: UUID(), relativeFileToken: DeleteLocationFixture.photoToken)
            try await store.registerAsset(PreparedLocalAsset(id: reference.assetID,
                relativeFileToken: reference.relativeFileToken, contentType: DeleteLocationFixture.contentType,
                pixelWidth: 100, pixelHeight: 100, createdAt: DeleteLocationFixture.createdAt))
            assets = [reference]
        }
        let location = try await createLocation(store, collectionID: collectionID, assets: assets)
        return (container, store, location)
    }

    private func createLocation(_ store: LibraryStore, collectionID: UUID,
                                assets: [LocalAssetReference] = [], other: Bool = false) async throws -> SavedLocation {
        let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: other ? DeleteLocationFixture.otherName : DeleteLocationFixture.locationName,
            address: nil, category: nil,
            coordinate: try Coordinate(latitude: other ? 1 : 0, longitude: 0))
        return try await store.createLocation(CreateLocationCommand(draft: LocationDraft(id: UUID(),
            candidate: candidate, destinationCollectionID: collectionID,
            assets: assets, createdAt: DeleteLocationFixture.createdAt))).location
    }

    /// U-04, INV-02/05/07: one deletion updates location and collection observers after persistence.
    @Test func deletionPreservesParentAndOtherLocationAndPublishesCommittedCounts() async throws {
        let (container, store, original) = try await setup()
        let other = try await createLocation(store, collectionID: original.collectionID, other: true)
        let before = try await store.locationSnapshot(collectionID: original.collectionID)
        let locations = await store.observeLocations(collectionID: original.collectionID)
        let collections = await store.observeSnapshots()
        var locationEvents = locations.makeAsyncIterator()
        var collectionEvents = collections.makeAsyncIterator()
        #expect(try await locationEvents.next() == before)
        #expect(try await collectionEvents.next()?.collections.first?.locationCount == 2)

        let commit = try await store.deleteLocation(DeleteLocationCommand(id: original.id,
            expectedRevision: original.revision))
        let reload = LibraryStore(container: container)
        let after = try await reload.locationSnapshot(collectionID: original.collectionID)
        #expect(commit.deletedLocationID == original.id)
        #expect(commit.libraryRevision == before.libraryRevision + 1)
        #expect(after.libraryRevision == commit.libraryRevision)
        #expect(after.locations == [other])
        #expect(after.collections.map(\.id) == [original.collectionID])
        #expect(after.collections.first?.locationCount == 1)
        #expect(try await reload.location(id: original.id) == nil)
        #expect(try await locationEvents.next() == after)
        let countEvent = try #require(try await collectionEvents.next())
        #expect(countEvent.libraryRevision == commit.libraryRevision)
        #expect(countEvent.collections.first?.locationCount == 1)
    }

    /// AC-22/23, INV-06: committed reference removal schedules recoverable cleanup exactly once.
    @Test func deletingLastPhotoReferenceQueuesCleanupAfterCommit() async throws {
        let (container, store, original) = try await setup(photo: true)
        _ = try await store.deleteLocation(DeleteLocationCommand(id: original.id,
            expectedRevision: original.revision))
        let reload = LibraryStore(container: container)
        #expect(try await reload.locationSnapshot(collectionID: nil).locations.isEmpty)
        #expect(try await reload.referencedAssetIDsAndTokens().isEmpty)
        let cleanup = try await reload.dueCleanupTasks(at: DeleteLocationFixture.deletedAt)
        #expect(cleanup.map(\.relativeFileToken) == [DeleteLocationFixture.photoToken])
        #expect(cleanup.first?.attemptCount == 0)
    }

    /// AC-22/23, INV-06: deleting one record never queues an asset still used by another record.
    @Test func deletingSharedPhotoReferencePreservesSurvivingRecordAndAsset() async throws {
        let (container, store, original) = try await setup(photo: true)
        let other = try await createLocation(store, collectionID: original.collectionID,
            assets: original.assets, other: true)
        _ = try await store.deleteLocation(DeleteLocationCommand(id: original.id,
            expectedRevision: original.revision))
        let reload = LibraryStore(container: container)
        #expect(try await reload.location(id: other.id) == other)
        #expect(try await reload.referencedAssetIDsAndTokens()[original.assets[0].assetID]
            == DeleteLocationFixture.photoToken)
        #expect(try await reload.dueCleanupTasks(at: DeleteLocationFixture.deletedAt).isEmpty)
    }

    /// AC-22, INV-05/06/07: save failure rolls back record, count, revision and cleanup; retry succeeds.
    @Test func failedDeletePreservesPhotoAndLibraryAndCanRetry() async throws {
        let (container, store, original) = try await setup(photo: true)
        let before = try await store.locationSnapshot(collectionID: nil)
        let failing = LibraryStore(container: container, currentDate: { DeleteLocationFixture.deletedAt },
            beforeSave: { throw DeleteLocationFailure.save })
        let command = DeleteLocationCommand(id: original.id, expectedRevision: original.revision)
        do { _ = try await failing.deleteLocation(command); Issue.record() }
        catch DeleteLocationFailure.save { }
        #expect(try await failing.locationSnapshot(collectionID: nil) == before)
        let reload = LibraryStore(container: container)
        #expect(try await reload.locationSnapshot(collectionID: nil) == before)
        #expect(try await reload.referencedAssetIDsAndTokens()[original.assets[0].assetID]
            == DeleteLocationFixture.photoToken)
        #expect(try await reload.dueCleanupTasks(at: DeleteLocationFixture.deletedAt).isEmpty)
        let retried = try await store.deleteLocation(command)
        #expect(retried.libraryRevision == before.libraryRevision + 1)
        let final = LibraryStore(container: container)
        #expect(try await final.location(id: original.id) == nil)
        #expect(try await final.dueCleanupTasks(at: DeleteLocationFixture.deletedAt).map(\.relativeFileToken)
            == [DeleteLocationFixture.photoToken])
    }

    /// AC-42/55, INV-07: a stale destructive action cannot discard another scene's committed change.
    @Test func staleRevisionReturnsLatestWithoutDeletingOrQueuingMedia() async throws {
        let (container, store, original) = try await setup(photo: true)
        let latest = try await store.setLocationFavorite(SetLocationFavoriteCommand(id: original.id,
            isFavorite: true, updatedAt: DeleteLocationFixture.deletedAt))
        let before = try await store.locationSnapshot(collectionID: nil)
        do {
            _ = try await store.deleteLocation(DeleteLocationCommand(id: original.id,
                expectedRevision: original.revision))
            Issue.record()
        } catch LocationWriteError.editConflict(let value) { #expect(value == latest.location) }
        let reload = LibraryStore(container: container)
        #expect(try await reload.locationSnapshot(collectionID: nil) == before)
        #expect(try await reload.dueCleanupTasks(at: DeleteLocationFixture.deletedAt).isEmpty)
    }

    /// INV-05/06/07: competing or repeated requests commit once, with no extra revision or cleanup.
    @Test func concurrentRepeatedDeletionHasExactlyOneCommit() async throws {
        let (container, store, original) = try await setup(photo: true)
        let before = try await store.locationSnapshot(collectionID: nil)
        let command = DeleteLocationCommand(id: original.id, expectedRevision: original.revision)
        let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { _ = try await store.deleteLocation(command); return true }
                    catch LocationWriteError.locationMissing(let id) { #expect(id == original.id); return false }
                    catch { Issue.record(error); return false }
                }
            }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }
        #expect(outcomes.filter { $0 }.count == 1)
        do { _ = try await store.deleteLocation(command); Issue.record() }
        catch LocationWriteError.locationMissing(let id) { #expect(id == original.id) }
        let reload = LibraryStore(container: container)
        let after = try await reload.locationSnapshot(collectionID: nil)
        #expect(after.locations.isEmpty)
        #expect(after.collections.first?.locationCount == 0)
        #expect(after.libraryRevision == before.libraryRevision + 1)
        #expect(try await reload.dueCleanupTasks(at: DeleteLocationFixture.deletedAt).map(\.relativeFileToken)
            == [DeleteLocationFixture.photoToken])
    }
}
