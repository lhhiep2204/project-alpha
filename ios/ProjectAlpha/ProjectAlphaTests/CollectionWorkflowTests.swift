//
//  CollectionWorkflowTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 26/9/26.
//

import Foundation
import SwiftData
import Testing
@testable import ProjectAlpha

private enum CollectionTestValue {
    static let defaultName = "My Places"
    static let tripName = "Trips"
    static let workName = "Work"
    static let renamedName = "Renamed Trips"
    static let localDraftName = "My Draft"
    static let competingName = "Other Scene"
    static let searchText = "  TRIP  "
    static let missingSearchText = "unmatched collection"
    static let invalidName = "   "
    static let paddedName = "  Trips  "
    static let overlongName = String(repeating: "A", count: CollectionNamePolicy.maximumGraphemeClusters + 1)
    static let locationName = "Saved Place"
    static let secondLocationName = "Another Saved Place"
    static let locationNotes = "A longer saved note with details"
    static let locationAddress = "123 Main Street"
    static let locationCategory = "landmark"
    static let locationDisplayName = "Custom Saved Place"
    static let metadataKey = "library"
    static let forbiddenIdiom = #"UIDevice\s*\.\s*(?:current\s*\.\s*)?userInterfaceIdiom"#
    static let forbiddenOrientation = #"interfaceOrientation"#
    static let forbiddenScreen = #"UIScreen\s*\.\s*main"#
    static let forbiddenDeviceModel = #"(?:iPhone|iPad)\s*\d+"#
    static let forbiddenWidth = #"(?:geometry|proxy|screen|window)\s*\.\s*(?:size\s*\.\s*)?width\s*[<>]=?\s*\d+"#
    static let appDirectory = "ProjectAlpha"
    static let swiftExtension = "swift"
}

private enum CollectionTestFailure: Error { case injectedSave }

/// A deterministic scheduling gate; cancellation does not release it implicitly.
private actor CollectionObservationGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

/// Opens the first subscription immediately and acknowledges a suspended re-registration.
private actor CollectionRestartRegistration {
    private var count = 0
    let started = CollectionObservationGate()
    let release = CollectionObservationGate()

    func wait() async {
        count += 1
        guard count == 2 else { return }
        await started.open()
        await release.wait()
    }
}

private actor CollectionObservationSessions {
    let streams: [AsyncThrowingStream<CollectionListSnapshot, any Error>]
    private var index = 0

    init(streams: [AsyncThrowingStream<CollectionListSnapshot, any Error>]) { self.streams = streams }

    func next() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        let stream = streams[index]
        index += 1
        return stream
    }
}

private struct SnapshotOnlyCollectionRepository: CollectionRepository {
    let stream: AsyncThrowingStream<CollectionListSnapshot, any Error>
    var registrationStarted: CollectionObservationGate? = nil
    var registrationGate: CollectionObservationGate? = nil
    var restartRegistration: CollectionRestartRegistration? = nil
    var sessions: CollectionObservationSessions? = nil

    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot {
        throw CollectionTestFailure.injectedSave
    }
    func snapshot() async throws -> CollectionListSnapshot { throw CollectionTestFailure.injectedSave }
    func collection(id: UUID) async throws -> CollectionSummary? { throw CollectionTestFailure.injectedSave }
    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        if let sessions { return await sessions.next() }
        await restartRegistration?.wait()
        await registrationStarted?.open()
        await registrationGate?.wait()
        return stream
    }
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        throw CollectionTestFailure.injectedSave
    }
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        throw CollectionTestFailure.injectedSave
    }
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit {
        throw CollectionTestFailure.injectedSave
    }
}

private actor CollectionCommandSpy: CollectionRepository {
    var created: [CreateCollectionCommand] = []
    var updated: [UpdateCollectionCommand] = []
    var deleted: [DeleteCollectionCommand] = []
    let resultCollection: Collection
    let failure: CollectionWriteError?

    init(collection: Collection, failure: CollectionWriteError? = nil) {
        self.resultCollection = collection
        self.failure = failure
    }

    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot {
        CollectionListSnapshot(collections: [], libraryRevision: 0)
    }
    func snapshot() async throws -> CollectionListSnapshot {
        CollectionListSnapshot(collections: [], libraryRevision: 0)
    }
    func collection(id: UUID) async throws -> CollectionSummary? { nil }
    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        created.append(command)
        if let failure { throw failure }
        return CollectionCommit(collection: resultCollection, libraryRevision: 1)
    }
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        updated.append(command)
        if let failure { throw failure }
        return CollectionCommit(collection: resultCollection, libraryRevision: 2)
    }
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit {
        deleted.append(command)
        if let failure { throw failure }
        return DeleteCollectionCommit(deletedCollectionID: command.id,
                                      deletedLocationCount: command.expectedLocationCount,
                                      libraryRevision: 3)
    }
}

/// D-01, AC-02/41, INV-01/04/05/07: use cases validate drafts and preserve commit expectations.
struct CollectionUseCaseTests {
    private func fixture(isDefault: Bool = false) -> Collection {
        Collection(id: UUID(), name: CollectionTestValue.tripName, isDefault: isDefault,
                   createdAt: Date(timeIntervalSince1970: 2),
                   updatedAt: Date(timeIntervalSince1970: 3), revision: 7)
    }

    /// AC-41/INV-05: invalid names never reach persistence; a valid name is trimmed once.
    @Test func createValidatesBeforeRepositoryAndKeepsDraftIdentity() async throws {
        let collection = fixture()
        let spy = CollectionCommandSpy(collection: collection)
        let useCases = CollectionUseCases(repository: spy)
        let command = createCommand(id: collection.id, name: CollectionTestValue.invalidName)
        do {
            _ = try await useCases.create.execute(command)
            Issue.record()
        } catch CollectionWriteError.validation(.collectionNameRequired) {
            // The draft remains uncommitted.
        }
        let longCommand = createCommand(id: collection.id, name: CollectionTestValue.overlongName)
        do {
            _ = try await useCases.create.execute(longCommand)
            Issue.record()
        } catch CollectionWriteError.validation(.collectionNameTooLong(let maximum)) {
            #expect(maximum == CollectionNamePolicy.maximumGraphemeClusters)
        }
        let rejectedCreates = await spy.created
        #expect(rejectedCreates.isEmpty)

        let valid = createCommand(id: collection.id, name: CollectionTestValue.paddedName)
        let commit = try await useCases.create.execute(valid)
        #expect(commit.collection == collection)
        let sent = await spy.created
        #expect(sent.count == 1)
        #expect(sent.first?.id == valid.id)
        #expect(sent.first?.createdAt == valid.createdAt)
        #expect(sent.first?.name == CollectionTestValue.tripName)
    }

    /// AC-02/INV-01: protected default deletion stops before a repository call.
    @Test func protectedDefaultDeleteNeverReachesRepository() async throws {
        let collection = fixture(isDefault: true)
        let spy = CollectionCommandSpy(collection: collection)
        let summary = CollectionSummary(collection: collection, locationCount: 4)
        do {
            _ = try await CollectionUseCases(repository: spy).delete.execute(summary)
            Issue.record()
        } catch CollectionWriteError.protectedDefault(let id) {
            #expect(id == collection.id)
        }
        let sent = await spy.deleted
        #expect(sent.isEmpty)
    }

    /// INV-04/07: deletion forwards the confirmed record revision and child count in one call.
    @Test func deleteSendsOneAtomicCommandWithConfirmedExpectations() async throws {
        let collection = fixture()
        let spy = CollectionCommandSpy(collection: collection)
        let summary = CollectionSummary(collection: collection, locationCount: 4)
        let commit = try await CollectionUseCases(repository: spy).delete.execute(summary)
        let sent = await spy.deleted
        #expect(sent == [DeleteCollectionCommand(id: collection.id,
                                                  expectedRevision: collection.revision,
                                                  expectedLocationCount: summary.locationCount)])
        #expect(commit.deletedCollectionID == collection.id)
        #expect(commit.deletedLocationCount == summary.locationCount)
    }

    /// INV-05/07: editor revision and identity are forwarded; typed storage failures survive.
    @Test func updateForwardsRevisionAndPropagatesTypedFailure() async throws {
        let collection = fixture()
        let spy = CollectionCommandSpy(collection: collection, failure: .storageUnavailable)
        let command = UpdateCollectionCommand(id: collection.id,
                                              expectedRevision: collection.revision,
                                              name: CollectionTestValue.paddedName,
                                              updatedAt: Date(timeIntervalSince1970: 4))
        do {
            _ = try await CollectionUseCases(repository: spy).update.execute(command)
            Issue.record()
        } catch CollectionWriteError.storageUnavailable {
            // The error remains actionable for presentation.
        }
        let sent = await spy.updated
        #expect(sent.count == 1)
        #expect(sent.first?.id == command.id)
        #expect(sent.first?.expectedRevision == command.expectedRevision)
        #expect(sent.first?.updatedAt == command.updatedAt)
        #expect(sent.first?.name == CollectionTestValue.tripName)
    }
}

@MainActor
private func memoryContainer() throws -> ModelContainer {
    try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
}

private func bootstrapCommand(id: UUID = UUID()) -> BootstrapCollectionCommand {
    BootstrapCollectionCommand(
        id: id,
        name: CollectionTestValue.defaultName,
        createdAt: Date(timeIntervalSince1970: 1)
    )
}

private func createCommand(id: UUID = UUID(), name: String = CollectionTestValue.tripName, time: TimeInterval = 2) -> CreateCollectionCommand {
    CreateCollectionCommand(
        id: id,
        name: name,
        createdAt: Date(timeIntervalSince1970: time)
    )
}

/// AC-01/02/41/42/55; INV-01/05/07; U-26 and D-02 name-only collection persistence and default protection.
@MainActor
struct CollectionStoreTests {
    /// AC-31/42, INV-04/05/07, D-02/20: rich child records keep Home counts and
    /// single-collection lookups accurate across commit, failed write and reload.
    @Test func populatedSnapshotsAndLookupKeepCountsAcrossWritesAndRollback() async throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let date = Date(timeIntervalSince1970: 1)
        let defaultID = UUID()
        let targetID = UUID()
        context.insert(LibrarySchemaV1.CollectionLocal(
            id: defaultID, name: CollectionTestValue.defaultName, isDefault: true,
            createdAt: date, updatedAt: date, revision: 1
        ))
        context.insert(LibrarySchemaV1.CollectionLocal(
            id: targetID, name: CollectionTestValue.tripName, isDefault: false,
            createdAt: date, updatedAt: date, revision: 1
        ))
        context.insert(LibrarySchemaV1.LocationLocal(
            id: UUID(), collectionID: targetID, provider: nil, primaryPlaceID: nil,
            alternatePlaceIDs: [], source: LocationSource.manualCoordinate.rawValue,
            name: CollectionTestValue.locationName,
            displayName: CollectionTestValue.locationDisplayName,
            address: CollectionTestValue.locationAddress, latitude: 10, longitude: 20,
            category: CollectionTestValue.locationCategory,
            notes: CollectionTestValue.locationNotes, orderedAssetIDs: [],
            isFavorite: true, createdAt: date, updatedAt: date, revision: 1
        ))
        context.insert(LibrarySchemaV1.LocationLocal(
            id: UUID(), collectionID: targetID, provider: nil, primaryPlaceID: nil,
            alternatePlaceIDs: [], source: LocationSource.manualCoordinate.rawValue,
            name: CollectionTestValue.secondLocationName, displayName: nil,
            address: nil, latitude: 11, longitude: 21, category: nil,
            notes: nil, orderedAssetIDs: [], isFavorite: false,
            createdAt: date, updatedAt: date, revision: 1
        ))
        context.insert(LibrarySchemaV1.LocationLocal(
            id: UUID(), collectionID: defaultID, provider: nil, primaryPlaceID: nil,
            alternatePlaceIDs: [], source: LocationSource.manualCoordinate.rawValue,
            name: CollectionTestValue.locationName, displayName: nil,
            address: nil, latitude: 12, longitude: 22, category: nil,
            notes: nil, orderedAssetIDs: [], isFavorite: false,
            createdAt: date, updatedAt: date, revision: 1
        ))
        context.insert(LibrarySchemaV1.LibraryMetadataLocal(
            key: CollectionTestValue.metadataKey, revision: 2
        ))
        try context.save()

        let store = LibraryStore(container: container)
        let initial = try await store.snapshot()
        let target = try #require(initial.collections.first { $0.id == targetID })
        #expect(initial.collections.first { $0.id == defaultID }?.locationCount == 1)
        #expect(target.locationCount == 2)
        #expect(try await store.collection(id: targetID) == target)
        #expect(try await store.collection(id: UUID()) == nil)

        let renamed = try await store.update(UpdateCollectionCommand(
            id: targetID, expectedRevision: target.collection.revision,
            name: CollectionTestValue.renamedName,
            updatedAt: Date(timeIntervalSince1970: 2)
        ))
        // AC-31: a write with no observer must be visible through this same store.
        let afterRename = try await store.snapshot()
        #expect(afterRename.libraryRevision == renamed.libraryRevision)
        #expect(afterRename.collections.first { $0.id == targetID }?.locationCount == 2)
        #expect(try await store.collection(id: targetID)?.collection.name == CollectionTestValue.renamedName)
        #expect(try await store.collection(id: targetID)?.locationCount == 2)
        let stream = await store.observeSnapshots()
        var events = stream.makeAsyncIterator()
        #expect(try await events.next() == afterRename)

        let failing = LibraryStore(container: container, beforeSave: { throw CollectionTestFailure.injectedSave })
        #expect(try await failing.snapshot() == afterRename)
        do {
            _ = try await failing.delete(DeleteCollectionCommand(
                id: targetID, expectedRevision: renamed.collection.revision,
                expectedLocationCount: 2
            ))
            Issue.record()
        } catch CollectionTestFailure.injectedSave {
            // INV-04/05: the entire deletion is rolled back before success.
        } catch {
            throw error
        }
        #expect(try await failing.snapshot() == afterRename)
        #expect(try await failing.collection(id: targetID)?.locationCount == 2)
        #expect(try await LibraryStore(container: container).snapshot() == afterRename)

        let deleted = try await store.delete(DeleteCollectionCommand(
            id: targetID, expectedRevision: renamed.collection.revision,
            expectedLocationCount: 2
        ))
        #expect(deleted.deletedLocationCount == 2)
        let afterDelete = try #require(try await events.next())
        #expect(afterDelete.libraryRevision == deleted.libraryRevision)
        #expect(afterDelete.collections.map(\.id) == [defaultID])
        #expect(afterDelete.collections.first?.locationCount == 1)
        #expect(try await store.collection(id: targetID) == nil)
        #expect(try await LibraryStore(container: container).snapshot() == afterDelete)
    }

    @Test func concurrentBootstrapIsIdempotentAndDefaultIsProtected() async throws {
        let container = try memoryContainer()
        let store = LibraryStore(container: container)
        let command = bootstrapCommand()
        async let first = store.bootstrap(command)
        async let second = store.bootstrap(command)
        let (firstSnapshot, secondSnapshot) = try await (first, second)
        #expect(firstSnapshot.collections.count == 1)
        #expect(secondSnapshot.collections.count == 1)
        let initial = try await store.snapshot()
        let sole = try #require(initial.collections.first)
        #expect(sole.id == command.id)
        #expect(sole.collection.isDefault)
        #expect(initial.libraryRevision == 1)

        do {
            _ = try await store.delete(DeleteCollectionCommand(
                id: sole.id,
                expectedRevision: sole.collection.revision,
                expectedLocationCount: sole.locationCount
            ))
            Issue.record()
        } catch CollectionWriteError.protectedDefault(let id) {
            #expect(id == sole.id)
        } catch {
            throw error
        }
        do {
            _ = try await store.update(UpdateCollectionCommand(
                id: sole.id,
                expectedRevision: sole.collection.revision,
                name: CollectionTestValue.renamedName,
                updatedAt: Date(timeIntervalSince1970: 2)
            ))
            Issue.record()
        } catch CollectionWriteError.protectedDefault(let id) {
            #expect(id == sole.id)
        } catch {
            throw error
        }
        let reloaded = try await LibraryStore(container: container).snapshot()
        #expect(reloaded == initial)
        #expect(reloaded.collections.first?.collection.name == CollectionTestValue.defaultName)
        #expect(reloaded.collections.first?.collection.revision == sole.collection.revision)
        #expect(reloaded.libraryRevision == initial.libraryRevision)
    }

    @Test func createUpdateDeleteReloadAndOrderRemainCommitted() async throws {
        let container = try memoryContainer()
        let writer = LibraryStore(container: container)
        let defaultID = UUID()
        _ = try await writer.bootstrap(bootstrapCommand(id: defaultID))
        let trip = try await writer.create(createCommand())
        let work = try await writer.create(createCommand(name: CollectionTestValue.workName, time: 3))
        let afterCreate = try await LibraryStore(container: container).snapshot()
        #expect(afterCreate.collections.map(\.id) == [defaultID, work.collection.id, trip.collection.id])
        #expect(afterCreate.collections.first?.collection.isDefault == true)
        #expect(afterCreate.collections.allSatisfy { $0.locationCount == 0 })
        #expect(afterCreate.libraryRevision == 3)

        let updated = try await writer.update(UpdateCollectionCommand(
            id: trip.collection.id,
            expectedRevision: trip.collection.revision,
            name: CollectionTestValue.renamedName,
            updatedAt: Date(timeIntervalSince1970: 4)
        ))
        #expect(updated.collection.id == trip.collection.id)
        #expect(updated.collection.createdAt == trip.collection.createdAt)
        #expect(updated.collection.revision == trip.collection.revision + 1)
        #expect(updated.libraryRevision == 4)
        let reloaded = try await LibraryStore(container: container).snapshot()
        #expect(reloaded.collections.first { $0.id == trip.collection.id }?.collection.name == CollectionTestValue.renamedName)
        #expect(reloaded.libraryRevision == 4)

        let deleted = try await writer.delete(DeleteCollectionCommand(
            id: work.collection.id,
            expectedRevision: work.collection.revision,
            expectedLocationCount: 0
        ))
        #expect(deleted.deletedCollectionID == work.collection.id)
        #expect(deleted.deletedLocationCount == 0)
        #expect(deleted.libraryRevision == 5)
        let final = try await LibraryStore(container: container).snapshot()
        #expect(final.collections.map(\.id) == [defaultID, trip.collection.id])
        #expect(final.libraryRevision == 5)
    }

    @Test func failedWriteRollsBackWithoutAdvancingCommittedRevision() async throws {
        let container = try memoryContainer()
        let writer = LibraryStore(container: container)
        _ = try await writer.bootstrap(bootstrapCommand())
        let before = try await writer.snapshot()
        let failing = LibraryStore(container: container, beforeSave: { throw CollectionTestFailure.injectedSave })
        let stream = await failing.observeSnapshots()
        var events = stream.makeAsyncIterator()
        #expect(try await events.next() == before)

        do {
            _ = try await failing.create(createCommand())
            Issue.record()
        } catch CollectionTestFailure.injectedSave {
            // Expected failure is injected immediately before persistence.
        } catch {
            throw error
        }
        #expect(try await failing.snapshot() == before)
        #expect(try await LibraryStore(container: container).snapshot() == before)
    }

    @Test func failedDeleteKeepsCollectionAfterReload() async throws {
        let container = try memoryContainer()
        let writer = LibraryStore(container: container)
        _ = try await writer.bootstrap(bootstrapCommand())
        let created = try await writer.create(createCommand())
        let before = try await writer.snapshot()
        let failing = LibraryStore(container: container, beforeSave: { throw CollectionTestFailure.injectedSave })
        do {
            _ = try await failing.delete(DeleteCollectionCommand(
                id: created.collection.id,
                expectedRevision: created.collection.revision,
                expectedLocationCount: 0
            ))
            Issue.record()
        } catch CollectionTestFailure.injectedSave {
            // Delete must roll back its in-memory context changes.
        } catch {
            throw error
        }
        #expect(try await failing.snapshot() == before)
        #expect(try await LibraryStore(container: container).snapshot() == before)
    }

    @Test func changedChildCountRejectsStaleDeleteAndPreservesChild() async throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let date = Date(timeIntervalSince1970: 1)
        let defaultID = UUID()
        let targetID = UUID()
        let childID = UUID()
        context.insert(LibrarySchemaV1.CollectionLocal(
            id: defaultID,
            name: CollectionTestValue.defaultName,
            isDefault: true,
            createdAt: date,
            updatedAt: date,
            revision: 1
        ))
        context.insert(LibrarySchemaV1.CollectionLocal(
            id: targetID,
            name: CollectionTestValue.tripName,
            isDefault: false,
            createdAt: date,
            updatedAt: date,
            revision: 1
        ))
        context.insert(LibrarySchemaV1.LocationLocal(
            id: childID,
            collectionID: targetID,
            provider: nil,
            primaryPlaceID: nil,
            alternatePlaceIDs: [],
            source: LocationSource.manualCoordinate.rawValue,
            name: CollectionTestValue.locationName,
            displayName: nil,
            address: nil,
            latitude: 0,
            longitude: 0,
            category: nil,
            notes: nil,
            orderedAssetIDs: [],
            isFavorite: false,
            createdAt: date,
            updatedAt: date,
            revision: 1
        ))
        context.insert(LibrarySchemaV1.LibraryMetadataLocal(
            key: CollectionTestValue.metadataKey,
            revision: 2
        ))
        try context.save()

        let store = LibraryStore(container: container)
        let before = try await store.snapshot()
        let target = try #require(before.collections.first { $0.id == targetID })
        #expect(target.locationCount == 1)
        do {
            _ = try await store.delete(DeleteCollectionCommand(
                id: targetID,
                expectedRevision: target.collection.revision,
                expectedLocationCount: 0
            ))
            Issue.record()
        } catch CollectionWriteError.editConflict(let latest, let count) {
            #expect(latest.id == targetID)
            #expect(count == 1)
        } catch {
            throw error
        }
        #expect(try await store.snapshot() == before)
        let reloaded = LibraryStore(container: container)
        let projection = try await reloaded.consistentProjection()
        #expect(projection.collections.contains { $0.id == targetID })
        #expect(projection.locations.contains { $0.id == childID && $0.collectionID == targetID })
        #expect(projection.libraryRevision == before.libraryRevision)
    }

    @Test func observationEmitsInitialAndCommittedSnapshots() async throws {
        let store = LibraryStore(container: try memoryContainer())
        let initial = try await store.bootstrap(bootstrapCommand())
        let stream = await store.observeSnapshots()
        var events = stream.makeAsyncIterator()
        #expect(try await events.next() == initial)
        let created = try await store.create(createCommand())
        let observed = try #require(try await events.next())
        #expect(observed.libraryRevision == created.libraryRevision)
        #expect(observed.collections.contains { $0.id == created.collection.id })
    }

    /// AC-31/INV-07, D-02/20: registration delivers its coherent initial result
    /// even when the consumer starts after a burst, followed by current data.
    @Test func delayedObservationKeepsInitialThenLatestCommittedSnapshot() async throws {
        let container = try memoryContainer()
        let store = LibraryStore(container: container)
        let initial = try await store.bootstrap(bootstrapCommand())
        let stream = await store.observeSnapshots()
        for index in 0..<8 {
            _ = try await store.create(createCommand(time: TimeInterval(index + 2)))
        }
        let latest = try await LibraryStore(container: container).snapshot()
        var events = stream.makeAsyncIterator()
        #expect(try await events.next() == initial)
        #expect(try await events.next() == latest)
        #expect(latest.libraryRevision == initial.libraryRevision + 8)
        #expect(latest.collections.count == initial.collections.count + 8)
    }

    /// AC-31/INV-07, D-02/20: a slow consumer skips superseded updates without
    /// receiving a revision paired with stale collection membership.
    @Test func slowObservationCoalescesBurstToLatestCoherentSnapshot() async throws {
        let container = try memoryContainer()
        let store = LibraryStore(container: container)
        let initial = try await store.bootstrap(bootstrapCommand())
        let stream = await store.observeSnapshots()
        var events = stream.makeAsyncIterator()
        #expect(try await events.next() == initial)
        let created = try await store.create(createCommand())
        let renamed = try await store.update(UpdateCollectionCommand(
            id: created.collection.id, expectedRevision: created.collection.revision,
            name: CollectionTestValue.renamedName, updatedAt: Date(timeIntervalSince1970: 3)
        ))
        _ = try await store.create(createCommand(name: CollectionTestValue.workName, time: 4))
        _ = try await store.delete(DeleteCollectionCommand(
            id: renamed.collection.id, expectedRevision: renamed.collection.revision,
            expectedLocationCount: 0
        ))
        let latest = try await LibraryStore(container: container).snapshot()
        #expect(try await events.next() == latest)
        #expect(latest.libraryRevision == initial.libraryRevision + 4)
        #expect(!latest.collections.contains { $0.id == created.collection.id })
        #expect(latest.collections.contains { $0.collection.name == CollectionTestValue.workName })
    }

    /// AC-31, D-02/20: each scene owns an independent initial result and update
    /// sequence; a fast reader cannot consume the slow reader's latest update.
    @Test func observersKeepIndependentInitialResultsAndConsumption() async throws {
        let store = LibraryStore(container: try memoryContainer())
        let initial = try await store.bootstrap(bootstrapCommand())
        let slowStream = await store.observeSnapshots()
        _ = try await store.create(createCommand())
        let secondInitial = try await store.snapshot()
        let fastStream = await store.observeSnapshots()
        var fast = fastStream.makeAsyncIterator()
        #expect(try await fast.next() == secondInitial)
        for index in 0..<4 {
            _ = try await store.create(createCommand(time: TimeInterval(index + 3)))
            let committed = try await store.snapshot()
            #expect(try await fast.next() == committed)
        }
        let latest = try await store.snapshot()
        var slow = slowStream.makeAsyncIterator()
        #expect(try await slow.next() == initial)
        #expect(try await slow.next() == latest)
    }

    /// AC-31/D-02/20 lifecycle: cancellation before the first request suppresses
    /// the retained initial value and completes without waiting for a commit.
    @Test func cancelledObservationBeforeInitialDeliveryCompletes() async throws {
        let store = LibraryStore(container: try memoryContainer())
        _ = try await store.bootstrap(bootstrapCommand())
        let stream = await store.observeSnapshots()
        let gate = CollectionObservationGate()
        let consumer = Task {
            await gate.wait()
            var events = stream.makeAsyncIterator()
            return try await events.next()
        }
        consumer.cancel()
        await gate.open()
        #expect(try await consumer.value == nil)
        _ = try await store.create(createCommand())
        #expect(try await store.snapshot().collections.count == 2)
    }

    /// AC-31/D-02/20 lifecycle: cancelling after the initial result ends the
    /// outstanding next request without needing another database mutation.
    @Test func cancelledObservationAfterInitialCompletesWithoutAnotherCommit() async throws {
        let store = LibraryStore(container: try memoryContainer())
        let initial = try await store.bootstrap(bootstrapCommand())
        let stream = await store.observeSnapshots()
        let (ready, readiness) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let consumer = Task {
            var events = stream.makeAsyncIterator()
            #expect(try await events.next() == initial)
            readiness.yield(())
            readiness.finish()
            return try await events.next()
        }
        for await _ in ready { break }
        consumer.cancel()
        #expect(try await consumer.value == nil)
        #expect(try await store.snapshot() == initial)
    }

    @Test func staleRevisionCannotReplaceCommittedData() async throws {
        let container = try memoryContainer()
        let writer = LibraryStore(container: container)
        _ = try await writer.bootstrap(bootstrapCommand())
        let original = try await writer.create(createCommand())
        let latest = try await writer.update(UpdateCollectionCommand(
            id: original.collection.id,
            expectedRevision: original.collection.revision,
            name: CollectionTestValue.competingName,
            updatedAt: Date(timeIntervalSince1970: 3)
        ))
        do {
            _ = try await writer.update(UpdateCollectionCommand(
                id: original.collection.id,
                expectedRevision: original.collection.revision,
                name: CollectionTestValue.localDraftName,
                updatedAt: Date(timeIntervalSince1970: 4)
            ))
            Issue.record()
        } catch CollectionWriteError.editConflict(let current, let count) {
            #expect(current == latest.collection)
            #expect(count == 0)
        } catch {
            throw error
        }
        let reloaded = try await LibraryStore(container: container).snapshot()
        #expect(reloaded.collections.first { $0.id == original.collection.id }?.collection == latest.collection)
        #expect(reloaded.libraryRevision == latest.libraryRevision)
    }

    @Test func invalidNameNeverCreatesCollectionOrAdvancesRevision() async throws {
        let store = LibraryStore(container: try memoryContainer())
        _ = try await store.bootstrap(bootstrapCommand())
        let before = try await store.snapshot()
        do {
            _ = try await store.create(createCommand(name: CollectionTestValue.invalidName))
            Issue.record()
        } catch CollectionWriteError.validation(.collectionNameRequired) {
            // The invalid draft remains outside committed storage.
        } catch {
            throw error
        }
        #expect(try await store.snapshot() == before)
    }
}

/// AC-52: identical collection labels gain creation-time context on the same day.
@MainActor
struct CollectionRowDatePresentationTests {
    @Test func matchingNameCountAndDayShowsDistinctTimes() {
        let locale = Locale(identifier: LanguageCode.english)
        let firstDate = Date(timeIntervalSince1970: 6 * 3_600)
        let secondDate = Date(timeIntervalSince1970: 7 * 3_600)
        func summary(id: UUID, date: Date) -> CollectionSummary {
            CollectionSummary(collection: Collection(
                id: id,
                name: CollectionTestValue.tripName,
                isDefault: false,
                createdAt: date,
                updatedAt: date,
                revision: 1
            ), locationCount: 0)
        }
        let first = summary(id: UUID(), date: firstDate)
        let second = summary(id: UUID(), date: secondDate)
        let firstText = CollectionRowDatePresentation.text(for: first, among: [first, second], locale: locale)
        let secondText = CollectionRowDatePresentation.text(for: second, among: [first, second], locale: locale)
        #expect(firstText == firstDate.formatted(Date.FormatStyle(date: .abbreviated, time: .complete).locale(locale)))
        #expect(secondText == secondDate.formatted(Date.FormatStyle(date: .abbreviated, time: .complete).locale(locale)))
        #expect(firstText != secondText)
        #expect(CollectionRowDatePresentation.text(for: first, among: [first], locale: locale)
            == firstDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
    }

    /// AC-52/U-28: a scene time-zone change can change both the displayed day
    /// and whether equal-name/count rows require creation-time context.
    @Test func sameCollectionsUseSceneTimeZoneForDateAndDisambiguation() throws {
        let locale = Locale(identifier: LanguageCode.english)
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let east = try #require(TimeZone(secondsFromGMT: 2 * 3_600))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let firstDate = Date(timeIntervalSince1970: 23 * 3_600)
        let secondDate = Date(timeIntervalSince1970: 24 * 3_600 + 1_800)
        func summary(date: Date) -> CollectionSummary {
            CollectionSummary(collection: Collection(
                id: UUID(), name: CollectionTestValue.tripName, isDefault: false,
                createdAt: date, updatedAt: date, revision: 1
            ), locationCount: 2)
        }
        let first = summary(date: firstDate)
        let second = summary(date: secondDate)
        let collections = [first, second]

        let utcTexts = CollectionRowDatePresentation.texts(
            for: collections, locale: locale, calendar: calendar, timeZone: utc
        )
        let eastTexts = CollectionRowDatePresentation.texts(
            for: collections, locale: locale, calendar: calendar, timeZone: east
        )
        let utcDay = Date.FormatStyle(
            date: .abbreviated, time: .omitted,
            locale: locale, calendar: calendar, timeZone: utc
        )
        let eastTime = Date.FormatStyle(
            date: .abbreviated, time: .complete,
            locale: locale, calendar: calendar, timeZone: east
        )
        #expect(utcTexts[first.id] == firstDate.formatted(utcDay))
        #expect(utcTexts[second.id] == secondDate.formatted(utcDay))
        #expect(eastTexts[first.id] == firstDate.formatted(eastTime))
        #expect(eastTexts[second.id] == secondDate.formatted(eastTime))
        #expect(utcTexts[first.id] != eastTexts[first.id])
        #expect(eastTexts[first.id] != eastTexts[second.id])
    }
}

/// J-02, AC-55/62/63, U-26/29/30 and D-19: Home and editor behavior preserves user state.
@MainActor
struct CollectionPresentationTests {
    /// AC-41/U-26: only a valid name is needed to create a committed collection.
    @Test func nameOnlyEditorCreatesPersistedCollection() async throws {
        let container = try memoryContainer()
        let store = LibraryStore(container: container)
        let repository = SwiftDataCollectionRepository(store: store)
        _ = try await repository.bootstrap(bootstrapCommand())
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 6)
        let model = CollectionEditorViewModel(
            useCases: CollectionUseCases(repository: repository),
            target: .create(id: id, createdAt: createdAt)
        )
        #expect(model.name.isEmpty)
        #expect(!model.isDirty)
        #expect(!model.isNameValid)
        #expect(await model.save(now: createdAt) == false)
        #expect(try await repository.collection(id: id) == nil)

        model.name = CollectionTestValue.tripName
        #expect(model.isDirty)
        #expect(model.isNameValid)
        #expect(await model.save(now: createdAt))
        let committed = try #require(try await LibraryStore(container: container).collection(id: id))
        #expect(committed.collection.name == CollectionTestValue.tripName)
        #expect(committed.collection.createdAt == createdAt)
    }

    @Test func homeFiltersNamesAndOpensStableCollectionID() async throws {
        let store = LibraryStore(container: try memoryContainer())
        let repository = SwiftDataCollectionRepository(store: store)
        _ = try await repository.bootstrap(bootstrapCommand())
        let trip = try await repository.create(createCommand())
        _ = try await repository.create(createCommand(name: CollectionTestValue.workName, time: 3))
        let router = Router<HomeRoute>(root: .root)
        let model = HomeViewModel(router: router, repository: repository,
                                  useCases: CollectionUseCases(repository: repository))
        await model.reload()
        #expect(model.phase == .ready)
        #expect(model.collections.count == 3)
        model.searchText = CollectionTestValue.searchText
        #expect(model.visibleCollections.map(\.id) == [trip.collection.id])
        model.open(try #require(model.visibleCollections.first))
        #expect(router.paths == [.collection(id: trip.collection.id)])
        model.searchText = CollectionTestValue.missingSearchText
        #expect(model.visibleCollections.isEmpty)
        #expect(model.collections.count == 3)
        #expect(router.paths == [.collection(id: trip.collection.id)])
    }

    /// AC-62/INV-05: a sole filtered Home row disappears on success and remains on failed commit.
    @Test func successfulDeleteRemovesHomeRowAndFailedDeleteKeepsIt() async throws {
        let container = try memoryContainer()
        let writer = LibraryStore(container: container)
        _ = try await writer.bootstrap(bootstrapCommand())
        let trip = try await writer.create(createCommand())
        let work = try await writer.create(createCommand(name: CollectionTestValue.workName, time: 3))
        let repository = SwiftDataCollectionRepository(store: writer)
        let home = HomeViewModel(router: Router<HomeRoute>(root: .root), repository: repository,
                                 useCases: CollectionUseCases(repository: repository))
        await home.reload()
        home.searchText = CollectionTestValue.searchText
        #expect(home.visibleCollections.map(\.id) == [trip.collection.id])
        let tripRow = try #require(home.visibleCollections.first { $0.id == trip.collection.id })
        await home.delete(tripRow)
        #expect(home.visibleCollections.isEmpty)
        #expect(home.searchText == CollectionTestValue.searchText)
        #expect(home.collections.contains { $0.id == work.collection.id })
        #expect(!home.deletionError)
        #expect(try await LibraryStore(container: container).collection(id: trip.collection.id) == nil)

        let failingStore = LibraryStore(container: container, beforeSave: {
            throw CollectionTestFailure.injectedSave
        })
        let failingHome = HomeViewModel(
            router: Router<HomeRoute>(root: .root),
            repository: SwiftDataCollectionRepository(store: failingStore),
            useCases: CollectionUseCases(repository: SwiftDataCollectionRepository(store: failingStore))
        )
        await failingHome.reload()
        failingHome.searchText = CollectionTestValue.workName
        #expect(failingHome.visibleCollections.map(\.id) == [work.collection.id])
        let workRow = try #require(failingHome.visibleCollections.first { $0.id == work.collection.id })
        await failingHome.delete(workRow)
        #expect(failingHome.visibleCollections.map(\.id) == [work.collection.id])
        #expect(failingHome.searchText == CollectionTestValue.workName)
        #expect(failingHome.deletionError)
        #expect(try await LibraryStore(container: container).collection(id: work.collection.id) != nil)
    }

    /// AC-63/D-19: display hints stay scene-local while the route contains only an ID.
    @Test func titleHintBelongsToSelectingSceneAndRouteKeepsOnlyID() {
        let first = SceneCoordinator()
        let second = SceneCoordinator()
        let id = UUID()
        first.setCollectionTitleHint(id: id, name: CollectionTestValue.tripName)
        first.homeRouter.push(.collection(id: id))
        #expect(first.collectionTitleHint(for: id) == CollectionTestValue.tripName)
        #expect(second.collectionTitleHint(for: id) == nil)
        #expect(first.homeRouter.paths == [.collection(id: id)])

        first.setCollectionTitleHint(id: id, name: CollectionTestValue.renamedName)
        #expect(first.collectionTitleHint(for: id) == CollectionTestValue.renamedName)
        first.clearCollectionTitleHint(for: id)
        #expect(first.collectionTitleHint(for: id) == nil)
        #expect(first.homeRouter.paths == [.collection(id: id)])
    }

    /// AC-63/D-19: a pending query uses the tapped title and a current result replaces it.
    @Test func collectionTitleUsesHintBeforeQueryThenLatestLoadedName() async {
        let id = UUID()
        let router = Router<HomeRoute>(root: .root)
        router.push(.collection(id: id))
        let (stream, continuation) = AsyncThrowingStream<CollectionListSnapshot, any Error>.makeStream()
        let model = CollectionDetailViewModel(
            collectionID: id,
            repository: SnapshotOnlyCollectionRepository(stream: stream),
            router: router
        )
        #expect(model.phase == .loading)
        #expect(model.displayTitle(hint: CollectionTestValue.tripName) == CollectionTestValue.tripName)

        let observation = Task { await model.observe() }
        let current = Collection(
            id: id,
            name: CollectionTestValue.renamedName,
            isDefault: false,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            revision: 2
        )
        continuation.yield(CollectionListSnapshot(
            collections: [CollectionSummary(collection: current, locationCount: 0)],
            libraryRevision: 2
        ))
        continuation.finish()
        await observation.value
        #expect(model.phase == .ready)
        #expect(model.displayTitle(hint: CollectionTestValue.tripName) == CollectionTestValue.renamedName)
        #expect(router.paths == [.collection(id: id)])
    }

    /// AC-05/63, D-01/03: an older observer failure cannot replace the newer scene list.
    @Test func supersededDetailObserverFailureCannotReplaceNewReadyState() async {
        let id = UUID()
        let collection = Collection(id: id, name: CollectionTestValue.renamedName, isDefault: false,
                                    createdAt: Date(timeIntervalSince1970: 1),
                                    updatedAt: Date(timeIntervalSince1970: 2), revision: 2)
        let enteredOldNext = CollectionObservationGate()
        let releaseOldFailure = CollectionObservationGate()
        let oldStream = AsyncThrowingStream<CollectionListSnapshot, any Error>(unfolding: {
            await enteredOldNext.open()
            await releaseOldFailure.wait()
            throw CollectionTestFailure.injectedSave
        })
        let currentStream = AsyncThrowingStream<CollectionListSnapshot, any Error> { continuation in
            continuation.yield(CollectionListSnapshot(
                collections: [CollectionSummary(collection: collection, locationCount: 0)], libraryRevision: 2
            ))
            continuation.finish()
        }
        let sessions = CollectionObservationSessions(streams: [oldStream, currentStream])
        let repository = SnapshotOnlyCollectionRepository(stream: oldStream, sessions: sessions)
        let router = Router<HomeRoute>(paths: [.collection(id: id)], root: .root)
        let model = CollectionDetailViewModel(collectionID: id, repository: repository, router: router)
        let older = Task { await model.observe() }
        await enteredOldNext.wait()
        await model.observe()
        #expect(model.phase == .ready)
        await releaseOldFailure.open()
        await older.value
        #expect(model.phase == .ready)
        #expect(model.collection?.collection == collection)
        #expect(model.displayTitle(hint: nil) == CollectionTestValue.renamedName)
        #expect(router.paths == [.collection(id: id)])
    }

    /// AC-05/63, D-01/19: cancellation while re-registering cannot leave ready content loading forever.
    @Test func cancellationDuringDetailReregistrationRetainsLoadedList() async {
        let id = UUID()
        let collection = Collection(id: id, name: CollectionTestValue.tripName, isDefault: false,
                                    createdAt: Date(timeIntervalSince1970: 1),
                                    updatedAt: Date(timeIntervalSince1970: 1), revision: 1)
        let initial = AsyncThrowingStream<CollectionListSnapshot, any Error> { continuation in
            continuation.yield(CollectionListSnapshot(
                collections: [CollectionSummary(collection: collection, locationCount: 0)], libraryRevision: 1
            ))
            continuation.finish()
        }
        let registration = CollectionRestartRegistration()
        let repository = SnapshotOnlyCollectionRepository(stream: initial, restartRegistration: registration)
        let router = Router<HomeRoute>(paths: [.collection(id: id)], root: .root)
        let model = CollectionDetailViewModel(collectionID: id, repository: repository, router: router)
        await model.observe()
        #expect(model.phase == .ready)
        let restart = Task { await model.observe() }
        await registration.started.wait()
        restart.cancel()
        await registration.release.open()
        await restart.value
        #expect(model.phase == .ready)
        #expect(model.collection?.collection == collection)
        #expect(model.displayTitle(hint: nil) == CollectionTestValue.tripName)
        #expect(router.paths == [.collection(id: id)])
    }

    /// AC-05/63, D-01/19: dismiss/re-enter cancellation cannot hide an already loaded list.
    @Test func cancelledDetailRestartRetainsReadyCollectionAndRoute() async {
        let id = UUID()
        let collection = Collection(id: id, name: CollectionTestValue.tripName, isDefault: false,
                                    createdAt: Date(timeIntervalSince1970: 1),
                                    updatedAt: Date(timeIntervalSince1970: 1), revision: 1)
        let initial = AsyncThrowingStream<CollectionListSnapshot, any Error> { continuation in
            continuation.yield(CollectionListSnapshot(
                collections: [CollectionSummary(collection: collection, locationCount: 0)], libraryRevision: 1
            ))
            continuation.finish()
        }
        let started = CollectionObservationGate()
        let release = CollectionObservationGate()
        let repository = SnapshotOnlyCollectionRepository(stream: initial,
                                                          registrationStarted: started,
                                                          registrationGate: release)
        let router = Router<HomeRoute>(paths: [.collection(id: id)], root: .root)
        let model = CollectionDetailViewModel(collectionID: id, repository: repository, router: router)
        let first = Task { await model.observe() }
        await started.wait()
        await release.open()
        await first.value
        #expect(model.phase == .ready)

        let enterRestart = CollectionObservationGate()
        let restart = Task {
            await enterRestart.wait()
            await model.observe()
        }
        // Cancellation is established before re-entry, without a scheduler timing assumption.
        restart.cancel()
        await enterRestart.open()
        await restart.value
        #expect(model.phase == .ready)
        #expect(model.collection?.collection == collection)
        #expect(model.displayTitle(hint: nil) == CollectionTestValue.tripName)
        #expect(router.paths == [.collection(id: id)])
    }

    @Test func editorConflictRetainsDraftAndCanReapplyAgainstLatestRevision() async throws {
        let store = LibraryStore(container: try memoryContainer())
        let repository = SwiftDataCollectionRepository(store: store)
        _ = try await repository.bootstrap(bootstrapCommand())
        let original = try await repository.create(createCommand())
        let model = CollectionEditorViewModel(
            useCases: CollectionUseCases(repository: repository),
            target: .edit(original.collection)
        )
        model.name = CollectionTestValue.localDraftName
        let latest = try await repository.update(UpdateCollectionCommand(
            id: original.collection.id,
            expectedRevision: original.collection.revision,
            name: CollectionTestValue.competingName,
            updatedAt: Date(timeIntervalSince1970: 3)
        ))
        #expect(await model.save(now: Date(timeIntervalSince1970: 4)) == false)
        #expect(model.name == CollectionTestValue.localDraftName)
        #expect(model.latestConflict == latest.collection)
        #expect(try await repository.collection(id: original.collection.id)?.collection == latest.collection)
        #expect(await model.reapply(now: Date(timeIntervalSince1970: 5)))
        let committed = try #require(try await repository.collection(id: original.collection.id)?.collection)
        #expect(committed.name == CollectionTestValue.localDraftName)
        #expect(committed.revision == latest.collection.revision + 1)
    }

    @Test func detailObservationFailureKeepsRouteForRetry() async {
        let collectionID = UUID()
        let stream = AsyncThrowingStream<CollectionListSnapshot, any Error> { continuation in
            continuation.finish(throwing: CollectionTestFailure.injectedSave)
        }
        let router = Router<HomeRoute>(root: .root)
        router.push(.collection(id: collectionID))
        let model = CollectionDetailViewModel(
            collectionID: collectionID,
            repository: SnapshotOnlyCollectionRepository(stream: stream),
            router: router
        )
        await model.observe()
        #expect(model.phase == .failed)
        #expect(router.paths == [.collection(id: collectionID)])
    }

    /// AC-63/D-19: missing data clears the scene hint before its ID-only route is pruned.
    @Test func deletedCollectionSnapshotRemovesOnlyItsRoute() async {
        let collectionID = UUID()
        let otherID = UUID()
        let scene = SceneCoordinator()
        scene.setCollectionTitleHint(id: collectionID, name: CollectionTestValue.tripName)
        let collection = Collection(
            id: collectionID,
            name: CollectionTestValue.tripName,
            isDefault: false,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            revision: 1
        )
        let stream = AsyncThrowingStream<CollectionListSnapshot, any Error> { continuation in
            continuation.yield(CollectionListSnapshot(
                collections: [CollectionSummary(collection: collection, locationCount: 0)],
                libraryRevision: 1
            ))
            continuation.yield(CollectionListSnapshot(collections: [], libraryRevision: 2))
            continuation.finish()
        }
        let router = Router<HomeRoute>(root: .root)
        router.push(.collection(id: otherID))
        router.push(.collection(id: collectionID))
        let model = CollectionDetailViewModel(
            collectionID: collectionID,
            repository: SnapshotOnlyCollectionRepository(stream: stream),
            router: router
        )
        #expect(model.displayTitle(hint: CollectionTestValue.tripName) == CollectionTestValue.tripName)
        await model.observe(onUnavailable: {
            #expect(router.paths == [.collection(id: otherID), .collection(id: collectionID)])
            scene.clearCollectionTitleHint(for: collectionID)
        })
        #expect(model.phase == .unavailable)
        #expect(model.collection == nil)
        #expect(model.displayTitle(hint: CollectionTestValue.tripName).isEmpty)
        #expect(scene.collectionTitleHint(for: collectionID) == nil)
        #expect(router.paths == [.collection(id: otherID)])
    }

    /// AC-63/INV-07: an older observation cannot erase a newer title or collection route.
    @Test func olderCollectionSnapshotCannotReplaceCurrentTitleOrRoute() async {
        let collectionID = UUID()
        let current = Collection(
            id: collectionID,
            name: CollectionTestValue.renamedName,
            isDefault: false,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 3),
            revision: 3
        )
        let stream = AsyncThrowingStream<CollectionListSnapshot, any Error> { continuation in
            continuation.yield(CollectionListSnapshot(
                collections: [CollectionSummary(collection: current, locationCount: 0)],
                libraryRevision: 3
            ))
            continuation.yield(CollectionListSnapshot(collections: [], libraryRevision: 2))
            continuation.finish()
        }
        let router = Router<HomeRoute>(root: .root)
        router.push(.collection(id: collectionID))
        let model = CollectionDetailViewModel(
            collectionID: collectionID,
            repository: SnapshotOnlyCollectionRepository(stream: stream),
            router: router
        )
        var unavailableCalls = 0
        await model.observe(onUnavailable: { unavailableCalls += 1 })
        #expect(unavailableCalls == 0)
        #expect(model.phase == .ready)
        #expect(model.collection?.collection == current)
        #expect(model.displayTitle(hint: CollectionTestValue.tripName) == CollectionTestValue.renamedName)
        #expect(router.paths == [.collection(id: collectionID)])
    }
}

/// AC-57/D-16 source audit for prohibited device-derived layout decisions.
struct AdaptiveLayoutSourceAuditTests {
    @Test func appLayoutDoesNotDependOnDeviceOrFixedScreenBreakpoints() throws {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(CollectionTestValue.appDirectory)
        let enumerator = try #require(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
        let patterns = [
            CollectionTestValue.forbiddenIdiom,
            CollectionTestValue.forbiddenOrientation,
            CollectionTestValue.forbiddenScreen,
            CollectionTestValue.forbiddenDeviceModel,
            CollectionTestValue.forbiddenWidth
        ]
        for case let url as URL in enumerator where url.pathExtension == CollectionTestValue.swiftExtension {
            let source = try String(contentsOf: url, encoding: .utf8)
            for pattern in patterns {
                #expect(source.range(of: pattern, options: .regularExpression) == nil,
                        "Forbidden adaptive layout source in \(url.lastPathComponent): \(pattern)")
            }
        }
    }
}
