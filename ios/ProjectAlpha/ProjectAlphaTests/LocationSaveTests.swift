//
//  LocationSaveTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation
import SwiftData
import Testing
@testable import ProjectAlpha

private enum SaveFixture {
    static let collectionName = "My Places"
    static let otherCollectionName = "Travel"
    static let placeName = "Museum"
    static let normalizedName = "  MUSEUM  "
    static let nearbyName = "Gallery"
    static let notes = "Keep these personal notes"
    static let changedNotes = "Changed personal notes"
    static let primary = "apple-place-A"
    static let aliasPrimary = "apple-place-B"
    static let repeatedCharacter = "A"
    static let blankName = "  "
    static let assetToken = "photos/validation.jpg"
    static let date = Date(timeIntervalSince1970: 100)
}

private enum SaveInjectedFailure: Error { case save }

/// AC-12–16/20/21/31/47–49; INV-02–05/07: exercise the real serialized writer and reload.
@MainActor
struct LocationSaveTests {
    private func setup() async throws -> (ModelContainer, LibraryStore, UUID) {
        let container = try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
        let store = LibraryStore(container: container)
        let id = UUID()
        _ = try await store.bootstrap(BootstrapCollectionCommand(id: id, name: SaveFixture.collectionName,
                                                               createdAt: SaveFixture.date))
        return (container, store, id)
    }

    private func candidate(name: String = SaveFixture.placeName, latitude: Double = 0,
                           identity: PlaceIdentity? = nil) throws -> PlaceCandidate {
        PlaceCandidate(id: UUID(), source: identity == nil ? .manualCoordinate : .appleMaps,
                       placeIdentity: identity, name: name, address: nil, category: nil,
                       coordinate: try Coordinate(latitude: latitude, longitude: 0))
    }

    private func command(destination: UUID, candidate: PlaceCandidate, id: UUID = UUID(),
                         notes: String = SaveFixture.notes) -> CreateLocationCommand {
        CreateLocationCommand(draft: LocationDraft(id: id, candidate: candidate,
            destinationCollectionID: destination, notes: notes, createdAt: SaveFixture.date))
    }

    private func warning(_ store: LibraryStore, _ command: CreateLocationCommand) async throws -> DuplicateWarningToken {
        do {
            _ = try await store.createLocation(command)
            Issue.record()
        } catch LocationWriteError.possibleDuplicates(_, let token) { return token }
        throw SaveInjectedFailure.save
    }

    /// AC-21: rejected bounds produce field-specific errors and leave committed state unchanged.
    @Test(arguments: [0, 1, 2, 3, 4])
    func invalidDraftNeverPersists(field: Int) async throws {
        let (_, store, id) = try await setup()
        let initial = try await store.locationSnapshot(collectionID: id)
        let name = field == 0 ? SaveFixture.blankName : field == 1
            ? String(repeating: SaveFixture.repeatedCharacter, count: 81) : SaveFixture.placeName
        let displayName = field == 2 ? String(repeating: SaveFixture.repeatedCharacter, count: 51) : nil
        let notes = field == 3 ? String(repeating: SaveFixture.repeatedCharacter, count: 10_001) : nil
        let asset = try LocalAssetReference(assetID: UUID(), relativeFileToken: SaveFixture.assetToken)
        let draft = LocationDraft(id: UUID(), candidate: try candidate(name: name), destinationCollectionID: id,
            displayName: displayName, notes: notes, assets: field == 4 ? Array(repeating: asset, count: 6) : [],
            createdAt: SaveFixture.date)
        let errors: [LocationValidationError] = [.nameRequired, .manualNameTooLong, .displayNameTooLong,
                                                 .notesTooLong, .tooManyPhotos]
        do { _ = try await store.createLocation(CreateLocationCommand(draft: draft)); Issue.record() }
        catch LocationWriteError.validation(let error) { #expect(error == errors[field]) }
        #expect(try await store.locationSnapshot(collectionID: id) == initial)
    }

    /// AC-12/14/48: aliases and normalized no-ID fallback block without overwriting metadata.
    @Test(arguments: [false, true])
    func hardDuplicatePreservesOriginal(alias: Bool) async throws {
        let (container, store, collectionID) = try await setup()
        let identity = alias ? try PlaceIdentity(primaryID: SaveFixture.primary) : nil
        let original = try await store.createLocation(command(destination: collectionID,
            candidate: candidate(identity: identity)))
        let duplicateIdentity = alias ? try PlaceIdentity(primaryID: SaveFixture.aliasPrimary,
                                                         alternateIDs: [SaveFixture.primary]) : nil
        let duplicate = command(destination: collectionID,
            candidate: try candidate(name: SaveFixture.normalizedName, identity: duplicateIdentity),
            notes: SaveFixture.changedNotes)
        do {
            _ = try await store.createLocation(duplicate)
            Issue.record()
        } catch LocationWriteError.blockingDuplicate(let id, let reason) {
            #expect(id == original.location.id)
            #expect(reason == (alias ? .providerIdentity : .normalizedCoordinateAndName))
        }
        let reload = try await LibraryStore(container: container).locationSnapshot(collectionID: collectionID)
        #expect(reload.locations == [original.location])
        #expect(reload.collections.first?.locationCount == 1)
    }

    /// AC-13/20: offline coordinate-only copies have independent UUIDs and favorite metadata.
    @Test func crossCollectionCopiesAreIndependentAndZeroCoordinateIsValid() async throws {
        let (_, store, firstID) = try await setup()
        let second = try await store.create(CreateCollectionCommand(id: UUID(), name: SaveFixture.otherCollectionName,
                                                                    createdAt: SaveFixture.date))
        let place = try candidate()
        let first = try await store.createLocation(command(destination: firstID, candidate: place))
        let other = try await store.createLocation(command(destination: second.collection.id, candidate: place,
                                                           notes: SaveFixture.changedNotes))
        _ = try await store.setLocationFavorite(SetLocationFavoriteCommand(id: first.location.id, isFavorite: true,
                                                                           updatedAt: SaveFixture.date))
        #expect(first.location.id != other.location.id)
        #expect(try await store.location(id: other.location.id) == other.location)
        #expect(other.location.notes == SaveFixture.changedNotes)
        #expect(other.location.coordinate.latitude == 0)
        #expect(other.location.coordinate.longitude == 0)
    }

    /// AC-16/47, INV-07: successful redelivery returns latest state and never replays stale favorite.
    @Test func idempotentRetryPreservesLaterFavoriteAndRejectsChangedContent() async throws {
        let (_, store, id) = try await setup()
        let create = command(destination: id, candidate: try candidate())
        let original = try await store.createLocation(create)
        let favorite = try await store.setLocationFavorite(SetLocationFavoriteCommand(
            id: original.location.id, isFavorite: true, updatedAt: SaveFixture.date.addingTimeInterval(1)))
        let retried = try await store.createLocation(create)
        #expect(retried == favorite)
        let changed = command(destination: id, candidate: create.draft.candidate, id: create.draft.id,
                              notes: SaveFixture.changedNotes)
        do {
            _ = try await store.createLocation(changed)
            Issue.record()
        } catch LocationWriteError.identifierConflict(let conflictID) { #expect(conflictID == create.draft.id) }
        #expect(try await store.locationSnapshot(collectionID: id).locations == [favorite.location])
    }

    /// AC-15/49: re-evaluate warning matches after another mutation; remote equal names are allowed.
    @Test func warningAcknowledgementIsInvalidatedByMatchedRevision() async throws {
        let (_, store, id) = try await setup()
        let first = try await store.createLocation(command(destination: id, candidate: candidate()))
        let near = command(destination: id, candidate: try candidate(name: SaveFixture.nearbyName, latitude: 0.0001))
        let old = try await warning(store, near)
        _ = try await store.setLocationFavorite(SetLocationFavoriteCommand(id: first.location.id,
            isFavorite: true, updatedAt: SaveFixture.date.addingTimeInterval(1)))
        let acknowledged = CreateLocationCommand(draft: near.draft, acknowledgedWarning: old)
        let current = try await warning(store, acknowledged)
        #expect(current != old)
        let saved = try await store.createLocation(CreateLocationCommand(draft: near.draft, acknowledgedWarning: current))
        #expect(saved.location.id == near.draft.id)
        _ = try await store.createLocation(command(destination: id,
            candidate: candidate(latitude: 1)))
        #expect(try await store.locationSnapshot(collectionID: id).locations.count == 3)
    }

    /// AC-15: changed destination and a newly committed hard match cannot reuse Save Anyway.
    @Test func warningCannotAuthorizeDifferentDestinationOrNewHardDuplicate() async throws {
        let (_, store, id) = try await setup()
        _ = try await store.createLocation(command(destination: id, candidate: candidate()))
        let near = command(destination: id, candidate: try candidate(name: SaveFixture.nearbyName, latitude: 0.0001))
        let token = try await warning(store, near)
        let second = try await store.create(CreateCollectionCommand(id: UUID(), name: SaveFixture.otherCollectionName,
                                                                    createdAt: SaveFixture.date))
        _ = try await store.createLocation(command(destination: second.collection.id, candidate: candidate()))
        let changed = command(destination: second.collection.id, candidate: near.draft.candidate, id: near.draft.id)
        let replacement = try await warning(store, CreateLocationCommand(draft: changed.draft, acknowledgedWarning: token))
        #expect(replacement.destinationCollectionID == second.collection.id)
        let competing = command(destination: id, candidate: near.draft.candidate)
        let competingToken = try await warning(store, competing)
        let winner = try await store.createLocation(CreateLocationCommand(draft: competing.draft,
                                                                          acknowledgedWarning: competingToken))
        do {
            _ = try await store.createLocation(CreateLocationCommand(draft: near.draft, acknowledgedWarning: token))
            Issue.record()
        } catch LocationWriteError.blockingDuplicate(let existing, _) { #expect(existing == winner.location.id) }
    }

    /// AC-16/INV-03: the actor rechecks two competing same-place creates atomically.
    @Test func concurrentSamePlaceHasExactlyOneCommit() async throws {
        let (_, store, id) = try await setup()
        let first = command(destination: id, candidate: try candidate())
        let second = command(destination: id, candidate: first.draft.candidate)
        let commands = [first, second]
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for command in commands {
                group.addTask {
                    do { _ = try await store.createLocation(command); return true }
                    catch LocationWriteError.blockingDuplicate { return false }
                    catch { Issue.record(error); return false }
                }
            }
            var outcomes: [Bool] = []
            for await outcome in group { outcomes.append(outcome) }
            return outcomes
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(try await store.locationSnapshot(collectionID: id).locations.count == 1)
    }

    /// INV-05: injected save failure rolls back location, counts and revision in an actual reload.
    @Test func saveFailureLeavesNoCommittedLocationOrCount() async throws {
        let (container, store, id) = try await setup()
        let initial = try await store.locationSnapshot(collectionID: id)
        let failing = LibraryStore(container: container, beforeSave: { throw SaveInjectedFailure.save })
        let create = command(destination: id, candidate: try candidate())
        do { _ = try await failing.createLocation(create); Issue.record() }
        catch SaveInjectedFailure.save { }
        #expect(try await failing.locationSnapshot(collectionID: id) == initial)
        #expect(try await LibraryStore(container: container).locationSnapshot(collectionID: id) == initial)
        let retried = try await store.createLocation(create)
        #expect(retried.location.id == create.draft.id)
        #expect(retried.libraryRevision == initial.libraryRevision + 1)
    }

    /// AC-31/INV-04: slow consumers retain initial/latest snapshots; cascade emits zero children.
    @Test func observationKeepsInitialAndLatestCommittedCountsThenCascade() async throws {
        let (_, store, _) = try await setup()
        let collection = try await store.create(CreateCollectionCommand(id: UUID(), name: SaveFixture.otherCollectionName,
                                                                        createdAt: SaveFixture.date))
        let initial = try await store.locationSnapshot(collectionID: collection.collection.id)
        let stream = await store.observeLocations(collectionID: collection.collection.id)
        var iterator = stream.makeAsyncIterator()
        _ = try await store.createLocation(command(destination: collection.collection.id, candidate: candidate()))
        _ = try await store.createLocation(command(destination: collection.collection.id, candidate: candidate(latitude: 1)))
        let latest = try await store.locationSnapshot(collectionID: collection.collection.id)
        #expect(try await iterator.next() == initial)
        #expect(try await iterator.next() == latest)
        #expect(latest.locations.count == 2)
        _ = try await store.delete(DeleteCollectionCommand(id: collection.collection.id,
            expectedRevision: collection.collection.revision, expectedLocationCount: 2))
        let deleted = try #require(try await iterator.next())
        #expect(deleted.locations.isEmpty)
        #expect(deleted.collections.allSatisfy { $0.id != collection.collection.id })
    }
}
