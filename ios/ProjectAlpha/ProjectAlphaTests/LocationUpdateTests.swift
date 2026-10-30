//
//  LocationUpdateTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/10/26.
//

import Foundation
import SwiftData
import Testing
@testable import ProjectAlpha

private enum UpdateFixture {
    static let collection = "Original collection"
    static let destination = "Destination collection"
    static let name = "Museum"
    static let nearbyName = "Gallery"
    static let notes = "Original notes"
    static let editedNotes = "Edited notes"
    static let displayName = "My museum"
    static let identity = "apple-update-place"
    static let photoToken = "photos/update-original.jpg"
    static let contentType = "image/jpeg"
    static let created = Date(timeIntervalSince1970: 100)
    static let updated = Date(timeIntervalSince1970: 200)
}

private enum UpdateFailure: Error { case save }

/// AC-21/22/31/42, INV-02/03/05/06/07: edits exercise the real writer and fresh-context reloads.
@MainActor
struct LocationUpdateTests {
    private func setup(photo: Bool = false) async throws -> (ModelContainer, LibraryStore, SavedLocation) {
        let container = try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
        let store = LibraryStore(container: container, currentDate: { UpdateFixture.updated })
        let collectionID = UUID()
        _ = try await store.bootstrap(BootstrapCollectionCommand(id: collectionID,
            name: UpdateFixture.collection, createdAt: UpdateFixture.created))
        let candidate = try place()
        var assets: [LocalAssetReference] = []
        if photo {
            let asset = try LocalAssetReference(assetID: UUID(), relativeFileToken: UpdateFixture.photoToken)
            try await store.registerAsset(PreparedLocalAsset(id: asset.assetID,
                relativeFileToken: asset.relativeFileToken, contentType: UpdateFixture.contentType,
                pixelWidth: 100, pixelHeight: 100, createdAt: UpdateFixture.created))
            assets = [asset]
        }
        let commit = try await store.createLocation(CreateLocationCommand(draft: LocationDraft(id: UUID(),
            candidate: candidate, destinationCollectionID: collectionID, notes: UpdateFixture.notes,
            assets: assets, createdAt: UpdateFixture.created)))
        return (container, store, commit.location)
    }

    private func place(name: String = UpdateFixture.name, latitude: Double = 0) throws -> PlaceCandidate {
        PlaceCandidate(id: UUID(), source: .appleMaps,
            placeIdentity: try PlaceIdentity(primaryID: UpdateFixture.identity), name: name,
            address: nil, category: nil, coordinate: try Coordinate(latitude: latitude, longitude: 0))
    }

    private func draft(_ location: SavedLocation, destination: UUID? = nil,
                       assets: [LocalAssetReference]? = nil) -> LocationDraft {
        LocationDraft(id: location.id,
            candidate: PlaceCandidate(id: location.id, source: location.source,
                placeIdentity: location.placeIdentity, name: location.name, address: location.address,
                category: location.category, coordinate: location.coordinate),
            destinationCollectionID: destination ?? location.collectionID,
            displayName: UpdateFixture.displayName, notes: UpdateFixture.editedNotes,
            assets: assets ?? location.assets, createdAt: location.createdAt)
    }

    /// INV-07, AC-31/42: editing a record excludes itself and preserves immutable identity and favorite.
    @Test func successfulEditReloadsSameRecordWithNewRevisionAndEvent() async throws {
        let (container, store, original) = try await setup()
        let favorite = try await store.setLocationFavorite(SetLocationFavoriteCommand(id: original.id,
            isFavorite: true, updatedAt: UpdateFixture.updated))
        let before = try await store.locationSnapshot(collectionID: original.collectionID)
        let stream = await store.observeLocations(collectionID: original.collectionID)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == before)
        let commit = try await store.updateLocation(UpdateLocationCommand(draft: draft(favorite.location),
            expectedRevision: favorite.location.revision))
        let saved = commit.location
        #expect(saved.id == original.id)
        #expect(saved.createdAt == original.createdAt)
        #expect(saved.coordinate == original.coordinate)
        #expect(saved.placeIdentity == original.placeIdentity)
        #expect(saved.source == original.source)
        #expect(saved.isFavorite)
        #expect(saved.notes == UpdateFixture.editedNotes)
        #expect(saved.displayName == UpdateFixture.displayName)
        #expect(saved.revision == favorite.location.revision + 1)
        #expect(saved.updatedAt == UpdateFixture.updated)
        #expect(commit.libraryRevision == before.libraryRevision + 1)
        let reload = try await LibraryStore(container: container).locationSnapshot(collectionID: original.collectionID)
        #expect(reload.locations == [saved])
        #expect(reload.collections.first?.locationCount == 1)
        #expect(try await iterator.next() == reload)
    }

    /// AC-31, INV-02/07: move and personal edits form one commit with both list counts updated.
    @Test func movingEditUpdatesBothScopedSnapshots() async throws {
        let (container, store, original) = try await setup()
        let destination = try await store.create(CreateCollectionCommand(id: UUID(), name: UpdateFixture.destination,
            createdAt: UpdateFixture.created)).collection.id
        let commit = try await store.updateLocation(UpdateLocationCommand(draft: draft(original, destination: destination),
            expectedRevision: original.revision))
        let reloaded = LibraryStore(container: container)
        let source = try await reloaded.locationSnapshot(collectionID: original.collectionID)
        let target = try await reloaded.locationSnapshot(collectionID: destination)
        #expect(source.locations.isEmpty)
        #expect(target.locations == [commit.location])
        #expect(source.collections.first { $0.id == original.collectionID }?.locationCount == 0)
        #expect(target.collections.first { $0.id == destination }?.locationCount == 1)
        #expect(commit.location.id == original.id)
    }

    /// AC-42/55, INV-07: stale editor carries latest value and never overwrites another scene's favorite.
    @Test func staleRevisionReturnsLatestWithoutChangingDraftOrLibrary() async throws {
        let (container, store, original) = try await setup()
        let latest = try await store.setLocationFavorite(SetLocationFavoriteCommand(id: original.id,
            isFavorite: true, updatedAt: UpdateFixture.updated))
        let before = try await store.locationSnapshot(collectionID: original.collectionID)
        let local = draft(original)
        do {
            _ = try await store.updateLocation(UpdateLocationCommand(draft: local, expectedRevision: original.revision))
            Issue.record()
        } catch LocationWriteError.editConflict(let value) { #expect(value == latest.location) }
        #expect(local.notes == UpdateFixture.editedNotes)
        #expect(try await LibraryStore(container: container).locationSnapshot(collectionID: original.collectionID) == before)
    }

    /// INV-02/03, AC-12/16: failed move keeps source ownership and all original user content.
    @Test(arguments: [false, true])
    func missingOrDuplicateDestinationRejectsWholeEdit(duplicate: Bool) async throws {
        let (container, store, original) = try await setup()
        let destination = UUID()
        var duplicateID: UUID?
        if duplicate {
            _ = try await store.create(CreateCollectionCommand(id: destination, name: UpdateFixture.destination,
                createdAt: UpdateFixture.created))
            duplicateID = try await store.createLocation(CreateLocationCommand(draft: LocationDraft(id: UUID(),
                candidate: place(), destinationCollectionID: destination, createdAt: UpdateFixture.created))).location.id
        }
        let before = try await store.locationSnapshot(collectionID: nil)
        do {
            _ = try await store.updateLocation(UpdateLocationCommand(draft: draft(original, destination: destination),
                expectedRevision: original.revision))
            Issue.record()
        } catch LocationWriteError.destinationMissing(let id) { #expect(!duplicate && id == destination) }
        catch LocationWriteError.blockingDuplicate(let id, _) { #expect(duplicate && id == duplicateID) }
        #expect(try await LibraryStore(container: container).locationSnapshot(collectionID: nil) == before)
    }

    /// AC-15/49: self is excluded, while a different nearby record still needs explicit acknowledgement.
    @Test func moveRequiresCurrentProximityWarningAcknowledgement() async throws {
        let (_, store, original) = try await setup()
        let destination = try await store.create(CreateCollectionCommand(id: UUID(), name: UpdateFixture.destination,
            createdAt: UpdateFixture.created)).collection.id
        let nearby = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: UpdateFixture.nearbyName, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 0.0001, longitude: 0))
        let neighbor = try await store.createLocation(CreateLocationCommand(draft: LocationDraft(id: UUID(),
            candidate: nearby, destinationCollectionID: destination, createdAt: UpdateFixture.created)))
        let edit = draft(original, destination: destination)
        var warning: DuplicateWarningToken?
        do {
            _ = try await store.updateLocation(UpdateLocationCommand(draft: edit, expectedRevision: original.revision))
            Issue.record()
        } catch LocationWriteError.possibleDuplicates(let ids, let token) {
            #expect(ids == [neighbor.location.id])
            warning = token
        }
        #expect(try await store.location(id: original.id) == original)
        let token = try #require(warning)
        let saved = try await store.updateLocation(UpdateLocationCommand(draft: edit,
            expectedRevision: original.revision, acknowledgedWarning: token))
        #expect(saved.location.collectionID == destination)
        #expect(saved.location.id == original.id)
    }

    /// AC-22, INV-05/06: failed removal rolls back references, cleanup work, counts and revisions.
    @Test func failedPhotoRemovalPreservesCommittedAssetAndCanRetry() async throws {
        let (container, store, original) = try await setup(photo: true)
        let before = try await store.locationSnapshot(collectionID: nil)
        let failing = LibraryStore(container: container, currentDate: { UpdateFixture.updated },
            beforeSave: { throw UpdateFailure.save })
        let command = UpdateLocationCommand(draft: draft(original, assets: []), expectedRevision: original.revision)
        do { _ = try await failing.updateLocation(command); Issue.record() }
        catch UpdateFailure.save { }
        let reload = LibraryStore(container: container)
        #expect(try await reload.locationSnapshot(collectionID: nil) == before)
        #expect(try await reload.referencedAssetIDsAndTokens()[original.assets[0].assetID] == UpdateFixture.photoToken)
        #expect(try await reload.dueCleanupTasks(at: UpdateFixture.updated).isEmpty)
        let saved = try await store.updateLocation(command)
        #expect(saved.location.assets.isEmpty)
        #expect(saved.libraryRevision == before.libraryRevision + 1)
        let committed = LibraryStore(container: container)
        #expect(try await committed.referencedAssetIDsAndTokens().isEmpty)
        #expect(try await committed.dueCleanupTasks(at: UpdateFixture.updated).map(\.relativeFileToken) == [UpdateFixture.photoToken])
    }

    /// INV-07/AC-42: competing editors cannot both commit the same starting revision.
    @Test func concurrentEditsHaveOneWinnerAndOneConflict() async throws {
        let (_, store, original) = try await setup()
        let command = UpdateLocationCommand(draft: draft(original), expectedRevision: original.revision)
        let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { _ = try await store.updateLocation(command); return true }
                    catch LocationWriteError.editConflict { return false }
                    catch { Issue.record(error); return false }
                }
            }
            var result: [Bool] = []
            for await outcome in group { result.append(outcome) }
            return result
        }
        #expect(outcomes.filter { $0 }.count == 1)
        #expect(try await store.location(id: original.id)?.revision == original.revision + 1)
    }
}
