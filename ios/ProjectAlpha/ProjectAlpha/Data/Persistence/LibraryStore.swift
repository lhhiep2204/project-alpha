//
//  LibraryStore.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 25/9/26.
//

import Foundation
import SwiftData

enum LibraryStoreError: Error {
    case multipleDefaults
    case corruptMetadata
    case revisionOverflow
    case invalidStoredData
}

nonisolated struct PreparedLocalAsset: Sendable {
    let id: UUID
    let relativeFileToken: String
    let contentType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let createdAt: Date
}

nonisolated struct MediaCleanupTask: Sendable {
    let id: UUID
    let relativeFileToken: String
    let attemptCount: Int
    let nextAttemptAt: Date
    let enqueuedAt: Date
}

/// One app-owned writer. Callers receive copied Domain values, never model objects.
actor LibraryStore: ModelActor {
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer
    private enum MetadataKey {
        static let library = "library"
    }

    private var observers: [UUID: AsyncThrowingStream<CollectionListSnapshot, any Error>.Continuation] = [:]
    private var cachedCommittedSnapshot: CollectionListSnapshot?
    private struct LocationObserver {
        let collectionID: UUID?
        let continuation: AsyncThrowingStream<LocationLibrarySnapshot, any Error>.Continuation
    }
    private var locationObservers: [UUID: LocationObserver] = [:]

    private let currentDate: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let beforeSave: @Sendable () throws -> Void

    init(
        container: ModelContainer,
        currentDate: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init,
        beforeSave: @escaping @Sendable () throws -> Void = {}
    ) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = container
        self.currentDate = currentDate
        self.makeID = makeID
        self.beforeSave = beforeSave
    }

    func bootstrap(_ command: BootstrapCollectionCommand) throws -> CollectionListSnapshot {
        do {
            let defaults = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.CollectionLocal>(
                predicate: #Predicate { $0.isDefault }
            ))
            guard defaults.count <= 1 else { throw LibraryStoreError.multipleDefaults }
            if defaults.count == 1 {
                return try committedCollectionSnapshot()
            }

            let name = try validatedName(command.name)
            try requireAvailableCollectionID(command.id)
            let metadata = try metadataForMutation()
            let revision = try nextRevision(metadata.revision)
            modelContext.insert(LibrarySchemaV1.CollectionLocal(
                id: command.id,
                name: name,
                isDefault: true,
                createdAt: command.createdAt,
                updatedAt: command.createdAt,
                revision: 1
            ))
            metadata.revision = revision
            let snapshot = try collectionSnapshot()
            try beforeSave()
            try modelContext.save()
            publishCommittedSnapshot()
            return snapshot
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func snapshot() throws -> CollectionListSnapshot {
        try committedCollectionSnapshot()
    }

    func collection(id: UUID) throws -> CollectionSummary? {
        let defaultCount = try modelContext.fetchCount(FetchDescriptor<LibrarySchemaV1.CollectionLocal>(
            predicate: #Predicate { $0.isDefault }
        ))
        guard defaultCount <= 1 else { throw LibraryStoreError.multipleDefaults }
        _ = try currentRevision()
        guard let local = try collectionLocal(id: id) else { return nil }
        return try summary(for: local)
    }

    func observeSnapshots() -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        let observerID = UUID()
        do {
            // Registration and initial read execute in one non-suspending actor turn.
            let initial = try committedCollectionSnapshot()
            let pending = AsyncThrowingStream<CollectionListSnapshot, any Error>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            pending.continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(observerID) }
            }
            observers[observerID] = pending.continuation
            let observation = LibrarySnapshotObservation(
                initial: initial,
                stream: pending.stream,
                continuation: pending.continuation
            )
            return AsyncThrowingStream(unfolding: { try await observation.next() })
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    /// Parent summaries and scoped locations are copied in one actor turn.
    func locationSnapshot(collectionID: UUID?) throws -> LocationLibrarySnapshot {
        let collections = try committedCollectionSnapshot()
        let rows: [LibrarySchemaV1.LocationLocal]
        if let collectionID {
            rows = try locationsLocal(collectionID: collectionID)
        } else {
            rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.LocationLocal>())
        }
        let parentIDs = Set(collections.collections.map(\.id))
        guard rows.allSatisfy({ parentIDs.contains($0.collectionID) }) else {
            throw LibraryStoreError.invalidStoredData
        }
        let tokens = try assetTokens(for: rows)
        let locations = try rows.map { try LibraryMappers.location($0, assetTokens: tokens) }
            .sorted(by: Self.locationSort)
        return LocationLibrarySnapshot(
            collections: collections.collections,
            locations: locations,
            libraryRevision: collections.libraryRevision
        )
    }

    func location(id: UUID) throws -> SavedLocation? {
        _ = try currentRevision()
        guard let local = try locationLocal(id: id) else { return nil }
        guard try collectionLocal(id: local.collectionID) != nil else {
            throw LibraryStoreError.invalidStoredData
        }
        return try LibraryMappers.location(local, assetTokens: assetTokens(for: [local]))
    }

    func observeLocations(collectionID: UUID?) -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        let observerID = UUID()
        do {
            let initial = try locationSnapshot(collectionID: collectionID)
            let pending = AsyncThrowingStream<LocationLibrarySnapshot, any Error>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            pending.continuation.onTermination = { [weak self] _ in
                Task { await self?.removeLocationObserver(observerID) }
            }
            locationObservers[observerID] = LocationObserver(
                collectionID: collectionID,
                continuation: pending.continuation
            )
            let observation = LibrarySnapshotObservation(
                initial: initial, stream: pending.stream, continuation: pending.continuation
            )
            return AsyncThrowingStream(unfolding: { try await observation.next() })
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    func createLocation(_ command: CreateLocationCommand) throws -> LocationCommit {
        do {
            let draft = command.draft
            do { try LocationDraftPolicy.validate(draft) }
            catch let error { throw LocationWriteError.validation(error) }
            try requireBootstrappedDefault()
            guard try collectionLocal(id: draft.destinationCollectionID) != nil else {
                throw LocationWriteError.destinationMissing(draft.destinationCollectionID)
            }
            if let existing = try locationLocal(id: draft.id) {
                let value = try LibraryMappers.location(existing, assetTokens: assetTokens(for: [existing]))
                guard Self.matchesCreate(value, draft: draft) else {
                    throw LocationWriteError.identifierConflict(draft.id)
                }
                return LocationCommit(location: value, libraryRevision: try currentRevision())
            }
            try validateAssets(draft.assets)
            let destinationLocations = try locationsLocal(collectionID: draft.destinationCollectionID)
            let tokens = try assetTokens(for: destinationLocations)
            let current = try destinationLocations.map { try LibraryMappers.location($0, assetTokens: tokens) }
            switch DuplicatePlacePolicy.evaluate(
                draftID: draft.id,
                destinationCollectionID: draft.destinationCollectionID,
                candidate: draft.candidate,
                against: current
            ) {
            case .allowed:
                break
            case let .blockingDuplicate(existingLocationID, reason):
                throw LocationWriteError.blockingDuplicate(existingLocationID: existingLocationID, reason: reason)
            case let .possibleDuplicates(candidateIDs, evaluationToken):
                guard command.acknowledgedWarning == evaluationToken else {
                    throw LocationWriteError.possibleDuplicates(
                        candidateIDs: candidateIDs, evaluationToken: evaluationToken
                    )
                }
            }
            let metadata = try metadataForMutation()
            let revision = try nextRevision(metadata.revision)
            let candidate = draft.candidate
            let local = LibrarySchemaV1.LocationLocal(
                id: draft.id,
                collectionID: draft.destinationCollectionID,
                provider: candidate.placeIdentity?.provider.rawValue,
                primaryPlaceID: candidate.placeIdentity?.primaryID,
                alternatePlaceIDs: candidate.placeIdentity?.alternateIDs.sorted() ?? [],
                source: candidate.source.rawValue,
                name: candidate.name.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: LocationDraftPolicy.optionalText(draft.displayName),
                address: LocationDraftPolicy.optionalText(candidate.address),
                latitude: candidate.coordinate.latitude,
                longitude: candidate.coordinate.longitude,
                category: LocationDraftPolicy.optionalText(candidate.category),
                notes: LocationDraftPolicy.optionalText(draft.notes),
                orderedAssetIDs: draft.assets.map(\.assetID),
                isFavorite: false,
                createdAt: draft.createdAt,
                updatedAt: draft.createdAt,
                revision: 1
            )
            modelContext.insert(local)
            metadata.revision = revision
            let value = try LibraryMappers.location(local, assetTokens: assetTokens(for: [local]))
            try beforeSave()
            try modelContext.save()
            publishCommittedSnapshot()
            return LocationCommit(location: value, libraryRevision: revision)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Fetch, validate and save in one actor turn. The draft cannot replace the
    /// committed place or replay a stale favorite/identity snapshot.
    func updateLocation(_ command: UpdateLocationCommand) throws -> LocationCommit {
        do {
            let draft = command.draft
            try requireBootstrappedDefault()
            guard let local = try locationLocal(id: draft.id) else {
                throw LocationWriteError.locationMissing(draft.id)
            }
            guard try collectionLocal(id: local.collectionID) != nil else {
                throw LibraryStoreError.invalidStoredData
            }
            let latest = try LibraryMappers.location(local, assetTokens: assetTokens(for: [local]))
            guard latest.revision == command.expectedRevision else {
                throw LocationWriteError.editConflict(latest: latest)
            }
            let candidate = PlaceCandidate(
                id: latest.id,
                source: latest.source,
                placeIdentity: latest.placeIdentity,
                name: latest.name,
                address: latest.address,
                category: latest.category,
                coordinate: latest.coordinate
            )
            let validatedDraft = LocationDraft(
                id: latest.id,
                candidate: candidate,
                destinationCollectionID: draft.destinationCollectionID,
                displayName: draft.displayName,
                notes: draft.notes,
                assets: draft.assets,
                createdAt: latest.createdAt
            )
            do { try LocationDraftPolicy.validate(validatedDraft) }
            catch let error { throw LocationWriteError.validation(error) }
            guard try collectionLocal(id: draft.destinationCollectionID) != nil else {
                throw LocationWriteError.destinationMissing(draft.destinationCollectionID)
            }
            try validateAssets(draft.assets)
            let destinationLocations = try locationsLocal(collectionID: draft.destinationCollectionID)
            let tokens = try assetTokens(for: destinationLocations)
            let current = try destinationLocations.map { try LibraryMappers.location($0, assetTokens: tokens) }
            switch DuplicatePlacePolicy.evaluate(
                draftID: draft.id,
                destinationCollectionID: draft.destinationCollectionID,
                candidate: candidate,
                against: current,
                excluding: latest.id
            ) {
            case .allowed:
                break
            case let .blockingDuplicate(existingLocationID, reason):
                throw LocationWriteError.blockingDuplicate(existingLocationID: existingLocationID, reason: reason)
            case let .possibleDuplicates(candidateIDs, evaluationToken):
                guard command.acknowledgedWarning == evaluationToken else {
                    throw LocationWriteError.possibleDuplicates(
                        candidateIDs: candidateIDs, evaluationToken: evaluationToken
                    )
                }
            }
            let date = currentDate()
            guard date.timeIntervalSinceReferenceDate.isFinite else {
                throw LocationWriteError.validation(.invalidDate)
            }
            let metadata = try metadataForMutation()
            let revision = try nextRevision(metadata.revision)
            let recordRevision = try nextRevision(local.revision)
            let removedAssetIDs = Set(local.orderedAssetIDs).subtracting(draft.assets.map(\.assetID))
            local.collectionID = draft.destinationCollectionID
            local.displayName = LocationDraftPolicy.optionalText(draft.displayName)
            local.notes = LocationDraftPolicy.optionalText(draft.notes)
            local.orderedAssetIDs = draft.assets.map(\.assetID)
            local.updatedAt = date
            local.revision = recordRevision
            try enqueueAndRemoveUnreferencedAssets(
                removedAssetIDs, at: date, excludingLocationIDs: [latest.id]
            )
            metadata.revision = revision
            let value = try LibraryMappers.location(local, assetTokens: assetTokens(for: [local]))
            try beforeSave()
            try modelContext.save()
            publishCommittedSnapshot()
            return LocationCommit(location: value, libraryRevision: revision)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Validate and remove one record and enqueue obsolete media in the same commit.
    func deleteLocation(_ command: DeleteLocationCommand) throws -> DeleteLocationCommit {
        do {
            try requireBootstrappedDefault()
            guard let local = try locationLocal(id: command.id) else {
                throw LocationWriteError.locationMissing(command.id)
            }
            guard try collectionLocal(id: local.collectionID) != nil else {
                throw LibraryStoreError.invalidStoredData
            }
            let latest = try LibraryMappers.location(local, assetTokens: assetTokens(for: [local]))
            guard latest.revision == command.expectedRevision else {
                throw LocationWriteError.editConflict(latest: latest)
            }
            let metadata = try metadataForMutation()
            let revision = try nextRevision(metadata.revision)
            let assetIDs = Set(local.orderedAssetIDs)
            modelContext.delete(local)
            try enqueueAndRemoveUnreferencedAssets(assetIDs, at: currentDate(), excludingLocationIDs: [command.id])
            metadata.revision = revision
            try beforeSave()
            try modelContext.save()
            publishCommittedSnapshot()
            return DeleteLocationCommit(deletedLocationID: command.id, libraryRevision: revision)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Patch only the current favorite field; never replay a stale entity.
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) throws -> LocationCommit {
        do {
            guard command.updatedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw LocationWriteError.validation(.invalidDate)
            }
            try requireBootstrappedDefault()
            guard let local = try locationLocal(id: command.id) else {
                throw LocationWriteError.locationMissing(command.id)
            }
            guard try collectionLocal(id: local.collectionID) != nil else {
                throw LocationWriteError.destinationMissing(local.collectionID)
            }
            let tokens = try assetTokens(for: [local])
            if local.isFavorite == command.isFavorite {
                return LocationCommit(
                    location: try LibraryMappers.location(local, assetTokens: tokens),
                    libraryRevision: try currentRevision()
                )
            }
            let metadata = try metadataForMutation()
            let revision = try nextRevision(metadata.revision)
            let recordRevision = try nextRevision(local.revision)
            local.isFavorite = command.isFavorite
            local.updatedAt = command.updatedAt
            local.revision = recordRevision
            metadata.revision = revision
            let value = try LibraryMappers.location(local, assetTokens: tokens)
            try beforeSave()
            try modelContext.save()
            publishCommittedSnapshot()
            return LocationCommit(location: value, libraryRevision: revision)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func create(_ command: CreateCollectionCommand) throws -> CollectionCommit {
        do {
            let name = try validatedName(command.name)
            try requireAvailableCollectionID(command.id)
            let metadata = try metadataForMutation()
            let revision = try nextRevision(metadata.revision)
            let local = LibrarySchemaV1.CollectionLocal(
                id: command.id,
                name: name,
                isDefault: false,
                createdAt: command.createdAt,
                updatedAt: command.createdAt,
                revision: 1
            )
            modelContext.insert(local)
            metadata.revision = revision
            let value = try LibraryMappers.collection(local)
            try beforeSave()
            try modelContext.save()
            publishCommittedSnapshot()
            return CollectionCommit(collection: value, libraryRevision: revision)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func update(_ command: UpdateCollectionCommand) throws -> CollectionCommit {
        do {
            guard let local = try collectionLocal(id: command.id) else {
                throw CollectionWriteError.collectionMissing(command.id)
            }
            guard !local.isDefault else {
                throw CollectionWriteError.protectedDefault(local.id)
            }
            let summary = try summary(for: local)
            try CollectionMutationPolicy.requireCurrentRevision(of: summary, expectedRevision: command.expectedRevision)
            let name = try validatedName(command.name)
            let metadata = try metadataForMutation()
            let revision = try nextRevision(metadata.revision)
            let recordRevision = try nextRevision(local.revision)
            local.name = name
            local.updatedAt = command.updatedAt
            local.revision = recordRevision
            metadata.revision = revision
            let value = try LibraryMappers.collection(local)
            try beforeSave()
            try modelContext.save()
            publishCommittedSnapshot()
            return CollectionCommit(collection: value, libraryRevision: revision)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func delete(_ command: DeleteCollectionCommand) throws -> DeleteCollectionCommit {
        do {
            guard let local = try collectionLocal(id: command.id) else {
                throw CollectionWriteError.collectionMissing(command.id)
            }
            let summary = try summary(for: local)
            try CollectionMutationPolicy.requireDeletable(summary.collection)
            try CollectionMutationPolicy.requireCurrentRevision(of: summary, expectedRevision: command.expectedRevision)
            let children = try locationsLocal(collectionID: command.id)
            guard children.count == command.expectedLocationCount else {
                throw CollectionWriteError.editConflict(
                    latest: summary.collection,
                    locationCount: children.count
                )
            }
            let metadata = try metadataForMutation()
            let revision = try nextRevision(metadata.revision)
            let removedAssetIDs = Set(children.flatMap(\.orderedAssetIDs))
            for child in children { modelContext.delete(child) }
            modelContext.delete(local)
            try enqueueAndRemoveUnreferencedAssets(
                removedAssetIDs,
                at: currentDate(),
                excludingLocationIDs: Set(children.map(\.id))
            )
            metadata.revision = revision
            try beforeSave()
            try modelContext.save()
            publishCommittedSnapshot()
            return DeleteCollectionCommit(
                deletedCollectionID: command.id,
                deletedLocationCount: children.count,
                libraryRevision: revision
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Reads all parent/child records in one actor turn for widget projection.
    func consistentProjection() throws -> LibraryReadProjection {
        let collectionRows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.CollectionLocal>())
        let locationRows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.LocationLocal>())
        let assetRows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.AssetLocal>())
        let revision = try currentRevision()
        let collections = try collectionRows.map(LibraryMappers.collection)
        let validParentIDs = Set(collections.map(\.id))
        guard locationRows.allSatisfy({ validParentIDs.contains($0.collectionID) }) else {
            throw LibraryStoreError.invalidStoredData
        }
        let tokens = Dictionary(uniqueKeysWithValues: assetRows.map { ($0.id, $0.relativeFileToken) })
        let locations = try locationRows.map { try LibraryMappers.location($0, assetTokens: tokens) }
        return LibraryReadProjection(collections: collections, locations: locations, libraryRevision: revision)
    }

    /// Media registration is preparatory maintenance. It never publishes a
    /// library revision; the following location command does that.
    func registerAsset(_ asset: PreparedLocalAsset) throws {
        do {
            _ = try LocalAssetReference(assetID: asset.id, relativeFileToken: asset.relativeFileToken)
            let assetID = asset.id
            let token = asset.relativeFileToken
            let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.AssetLocal>(
                predicate: #Predicate { $0.id == assetID || $0.relativeFileToken == token }
            ))
            let matches = rows.filter { $0.id == asset.id }
            guard matches.count <= 1 else { throw LibraryStoreError.invalidStoredData }
            // A cleanup consumer may already own this token. Final tokens must
            // never be resurrected while that deletion is queued or in flight.
            guard try !hasQueuedCleanup(for: [token]) else {
                throw LibraryStoreError.invalidStoredData
            }
            if let existing = matches.first {
                guard existing.relativeFileToken == asset.relativeFileToken,
                      existing.contentType == asset.contentType,
                      existing.pixelWidth == asset.pixelWidth,
                      existing.pixelHeight == asset.pixelHeight else {
                    throw CollectionWriteError.identifierConflict(asset.id)
                }
                return
            }
            guard !rows.contains(where: { $0.relativeFileToken == asset.relativeFileToken }) else {
                throw LibraryStoreError.invalidStoredData
            }
            modelContext.insert(LibrarySchemaV1.AssetLocal(
                id: asset.id,
                relativeFileToken: asset.relativeFileToken,
                contentType: asset.contentType,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                createdAt: asset.createdAt
            ))
            try beforeSave()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func assetToken(id: UUID) throws -> String? {
        let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.AssetLocal>(
            predicate: #Predicate { $0.id == id }
        ))
        guard rows.count <= 1 else { throw LibraryStoreError.invalidStoredData }
        return rows.first?.relativeFileToken
    }

    /// Returns only assets currently referenced by committed locations.
    func referencedAssetIDsAndTokens() throws -> [UUID: String] {
        var descriptor = FetchDescriptor<LibrarySchemaV1.LocationLocal>()
        descriptor.propertiesToFetch = [\.orderedAssetIDs]
        let locations = try modelContext.fetch(descriptor)
        let referenced = Set(locations.flatMap(\.orderedAssetIDs))
        let assets = try assetRows(withIDs: referenced)
        let tokens = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0.relativeFileToken) })
        guard referenced.allSatisfy({ tokens[$0] != nil }) else {
            throw LibraryStoreError.invalidStoredData
        }
        return tokens
    }

    /// Removes an abandoned registration only after checking live references.
    /// The returned token is queued for deletion after this database save.
    func discardUnreferencedAsset(id: UUID) throws -> MediaCleanupTask? {
        do {
            let referenced = try referencedAssetIDsAndTokens()
            guard referenced[id] == nil else { return nil }
            let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.AssetLocal>(
                predicate: #Predicate { $0.id == id }
            ))
            guard rows.count <= 1 else { throw LibraryStoreError.invalidStoredData }
            guard let asset = rows.first else { return nil }
            let date = currentDate()
            let cleanup = LibrarySchemaV1.MediaCleanupLocal(
                id: makeID(),
                relativeFileToken: asset.relativeFileToken,
                attemptCount: 0,
                nextAttemptAt: date,
                enqueuedAt: date
            )
            modelContext.insert(cleanup)
            modelContext.delete(asset)
            try beforeSave()
            try modelContext.save()
            return Self.cleanupTask(cleanup)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func dueCleanupTasks(at date: Date) throws -> [MediaCleanupTask] {
        try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.MediaCleanupLocal>(
            predicate: #Predicate { $0.nextAttemptAt <= date }
        ))
            .map(Self.cleanupTask)
    }

    func markCleanupSucceeded(id: UUID) throws {
        do {
            let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.MediaCleanupLocal>(
                predicate: #Predicate { $0.id == id }
            ))
            guard rows.count <= 1 else { throw LibraryStoreError.invalidStoredData }
            guard let task = rows.first else { return }
            modelContext.delete(task)
            try beforeSave()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func markCleanupFailed(id: UUID, nextAttemptAt: Date) throws {
        do {
            let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.MediaCleanupLocal>(
                predicate: #Predicate { $0.id == id }
            ))
            guard rows.count <= 1 else { throw LibraryStoreError.invalidStoredData }
            guard let task = rows.first else { return }
            task.attemptCount += 1
            task.nextAttemptAt = nextAttemptAt
            try beforeSave()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func cleanupTask(_ local: LibrarySchemaV1.MediaCleanupLocal) -> MediaCleanupTask {
        MediaCleanupTask(
            id: local.id,
            relativeFileToken: local.relativeFileToken,
            attemptCount: local.attemptCount,
            nextAttemptAt: local.nextAttemptAt,
            enqueuedAt: local.enqueuedAt
        )
    }

    private func committedCollectionSnapshot() throws -> CollectionListSnapshot {
        // The app routes all library writes through this actor. A cached value
        // is reusable only while the durable library revision is unchanged.
        let revision = try currentRevision()
        if let cachedCommittedSnapshot, cachedCommittedSnapshot.libraryRevision == revision {
            return cachedCommittedSnapshot
        }
        let snapshot = try collectionSnapshot()
        cachedCommittedSnapshot = snapshot
        return snapshot
    }

    private func collectionSnapshot() throws -> CollectionListSnapshot {
        let collections = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.CollectionLocal>())
        let defaults = collections.filter(\.isDefault)
        guard defaults.count <= 1 else { throw LibraryStoreError.multipleDefaults }
        // Home needs ownership counts, not the notes, media IDs, and place data
        // carried by every saved location.
        var countDescriptor = FetchDescriptor<LibrarySchemaV1.LocationLocal>()
        countDescriptor.propertiesToFetch = [\.collectionID]
        let locations = try modelContext.fetch(countDescriptor)
        var counts: [UUID: Int] = [:]
        for location in locations { counts[location.collectionID, default: 0] += 1 }
        let summaries = try collections.map { local in
            CollectionSummary(collection: try LibraryMappers.collection(local), locationCount: counts[local.id, default: 0])
        }.sorted(by: Self.collectionSort)
        return CollectionListSnapshot(collections: summaries, libraryRevision: try currentRevision())
    }

    private func summary(for local: LibrarySchemaV1.CollectionLocal) throws -> CollectionSummary {
        let collectionID = local.id
        let count = try modelContext.fetchCount(FetchDescriptor<LibrarySchemaV1.LocationLocal>(
            predicate: #Predicate { $0.collectionID == collectionID }
        ))
        return CollectionSummary(collection: try LibraryMappers.collection(local), locationCount: count)
    }

    private static func collectionSort(_ lhs: CollectionSummary, _ rhs: CollectionSummary) -> Bool {
        if lhs.collection.isDefault != rhs.collection.isDefault { return lhs.collection.isDefault }
        if lhs.collection.createdAt != rhs.collection.createdAt {
            return lhs.collection.createdAt > rhs.collection.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func collectionLocal(id: UUID) throws -> LibrarySchemaV1.CollectionLocal? {
        let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.CollectionLocal>(
            predicate: #Predicate { $0.id == id }
        ))
        guard rows.count <= 1 else { throw LibraryStoreError.invalidStoredData }
        return rows.first
    }

    private func locationsLocal(collectionID: UUID) throws -> [LibrarySchemaV1.LocationLocal] {
        try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.LocationLocal>(
            predicate: #Predicate { $0.collectionID == collectionID }
        ))
    }

    private func locationLocal(id: UUID) throws -> LibrarySchemaV1.LocationLocal? {
        let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.LocationLocal>(
            predicate: #Predicate { $0.id == id }
        ))
        guard rows.count <= 1 else { throw LibraryStoreError.invalidStoredData }
        return rows.first
    }

    private func requireBootstrappedDefault() throws {
        let count = try modelContext.fetchCount(FetchDescriptor<LibrarySchemaV1.CollectionLocal>(
            predicate: #Predicate { $0.isDefault }
        ))
        guard count <= 1 else { throw LibraryStoreError.multipleDefaults }
        guard count == 1 else { throw LibraryStoreError.invalidStoredData }
    }

    private func assetTokens(for locations: [LibrarySchemaV1.LocationLocal]) throws -> [UUID: String] {
        let requiredIDs = Set(locations.flatMap(\.orderedAssetIDs))
        let rows = try assetRows(withIDs: requiredIDs)
        var tokens: [UUID: String] = [:]
        for row in rows {
            guard tokens.updateValue(row.relativeFileToken, forKey: row.id) == nil else {
                throw LibraryStoreError.invalidStoredData
            }
        }
        guard requiredIDs.allSatisfy({ tokens[$0] != nil }) else {
            throw LocationWriteError.invalidAssets
        }
        return tokens
    }

    private func validateAssets(_ references: [LocalAssetReference]) throws {
        let ids = Set(references.map(\.assetID))
        let tokens = Set(references.map(\.relativeFileToken))
        guard ids.count == references.count, tokens.count == references.count else {
            throw LocationWriteError.invalidAssets
        }
        guard !references.isEmpty else { return }
        let rows = try assetRows(withIDs: ids)
        guard try !hasQueuedCleanup(for: Array(tokens)) else {
            throw LocationWriteError.invalidAssets
        }
        for reference in references {
            let matches = rows.filter { $0.id == reference.assetID }
            guard matches.count == 1,
                  matches.first?.relativeFileToken == reference.relativeFileToken else {
                throw LocationWriteError.invalidAssets
            }
        }
    }

    /// Both a single-location lookup and a full snapshot use one scoped fetch.
    /// Only identity/token fields are needed for mapping and reference cleanup.
    private func assetRows(withIDs ids: Set<UUID>) throws -> [LibrarySchemaV1.AssetLocal] {
        guard !ids.isEmpty else { return [] }
        let requiredIDs = Array(ids)
        var descriptor = FetchDescriptor<LibrarySchemaV1.AssetLocal>(
            predicate: #Predicate { requiredIDs.contains($0.id) }
        )
        descriptor.propertiesToFetch = [\.id, \.relativeFileToken]
        return try modelContext.fetch(descriptor)
    }

    private func hasQueuedCleanup(for tokens: [String]) throws -> Bool {
        guard !tokens.isEmpty else { return false }
        return try modelContext.fetchCount(FetchDescriptor<LibrarySchemaV1.MediaCleanupLocal>(
            predicate: #Predicate { tokens.contains($0.relativeFileToken) }
        )) > 0
    }

    private static func matchesCreate(_ location: SavedLocation, draft: LocationDraft) -> Bool {
        let candidate = draft.candidate
        return location.collectionID == draft.destinationCollectionID
            && location.placeIdentity == candidate.placeIdentity
            && location.source == candidate.source
            && location.name == candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            && location.displayName == LocationDraftPolicy.optionalText(draft.displayName)
            && location.address == LocationDraftPolicy.optionalText(candidate.address)
            && location.coordinate == candidate.coordinate
            && location.category == LocationDraftPolicy.optionalText(candidate.category)
            && location.notes == LocationDraftPolicy.optionalText(draft.notes)
            && location.assets == draft.assets
            && location.createdAt == draft.createdAt
    }

    private static func locationSort(_ lhs: SavedLocation, _ rhs: SavedLocation) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func requireAvailableCollectionID(_ id: UUID) throws {
        guard try collectionLocal(id: id) == nil else { throw CollectionWriteError.identifierConflict(id) }
    }

    private func validatedName(_ raw: String) throws -> String {
        do { return try CollectionNamePolicy.validated(raw) }
        catch let error as DomainValidationError { throw CollectionWriteError.validation(error) }
    }

    private func metadataForMutation() throws -> LibrarySchemaV1.LibraryMetadataLocal {
        let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.LibraryMetadataLocal>())
        guard rows.count <= 1, rows.allSatisfy({ $0.key == MetadataKey.library }) else {
            throw LibraryStoreError.corruptMetadata
        }
        if let first = rows.first { return first }
        let metadata = LibrarySchemaV1.LibraryMetadataLocal(key: MetadataKey.library, revision: 0)
        modelContext.insert(metadata)
        return metadata
    }

    private func currentRevision() throws -> Int64 {
        let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.LibraryMetadataLocal>())
        guard rows.count <= 1, rows.allSatisfy({ $0.key == MetadataKey.library }) else {
            throw LibraryStoreError.corruptMetadata
        }
        return rows.first?.revision ?? 0
    }

    private func nextRevision(_ revision: Int64) throws -> Int64 {
        guard revision >= 0, revision < Int64.max else { throw LibraryStoreError.revisionOverflow }
        return revision + 1
    }

    private func enqueueAndRemoveUnreferencedAssets(
        _ assetIDs: Set<UUID>,
        at date: Date,
        excludingLocationIDs: Set<UUID> = []
    ) throws {
        guard !assetIDs.isEmpty else { return }
        var descriptor = FetchDescriptor<LibrarySchemaV1.LocationLocal>()
        descriptor.propertiesToFetch = [\.id, \.orderedAssetIDs]
        let locations = try modelContext.fetch(descriptor)
        let stillReferenced = Set(locations.filter { !excludingLocationIDs.contains($0.id) }.flatMap(\.orderedAssetIDs))
        let assets = try assetRows(withIDs: assetIDs.subtracting(stillReferenced))
        for asset in assets {
            modelContext.insert(LibrarySchemaV1.MediaCleanupLocal(
                id: makeID(),
                relativeFileToken: asset.relativeFileToken,
                attemptCount: 0,
                nextAttemptAt: date,
                enqueuedAt: date
            ))
            modelContext.delete(asset)
        }
    }

    private func publishCommittedSnapshot() {
        cachedCommittedSnapshot = nil
        if !observers.isEmpty {
            do { publish(try committedCollectionSnapshot()) }
            catch {
                for continuation in observers.values { continuation.finish(throwing: error) }
                observers.removeAll()
            }
        }
        // Equal scopes share one copied projection per commit, not per screen.
        var snapshots: [UUID?: LocationLibrarySnapshot] = [:]
        var failedObserverIDs: [UUID] = []
        for (id, observer) in locationObservers {
            do {
                let snapshot: LocationLibrarySnapshot
                if let cached = snapshots[observer.collectionID] {
                    snapshot = cached
                } else {
                    snapshot = try locationSnapshot(collectionID: observer.collectionID)
                    snapshots[observer.collectionID] = snapshot
                }
                observer.continuation.yield(snapshot)
            } catch {
                observer.continuation.finish(throwing: error)
                failedObserverIDs.append(id)
            }
        }
        for id in failedObserverIDs { locationObservers.removeValue(forKey: id) }
    }

    private func removeLocationObserver(_ id: UUID) {
        locationObservers.removeValue(forKey: id)
    }

    private func publish(_ snapshot: CollectionListSnapshot) {
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
}

/// A slow consumer retains its registration snapshot and at most one newer
/// committed snapshot. The store retains only the bounded stream continuation,
/// so releasing the outer stream/iterator also releases this lifetime owner.
private actor LibrarySnapshotObservation<Value: Sendable> {
    private var initial: Value?
    private var iterator: AsyncThrowingStream<Value, any Error>.Iterator
    private let continuation: AsyncThrowingStream<Value, any Error>.Continuation

    init(
        initial: Value,
        stream: AsyncThrowingStream<Value, any Error>,
        continuation: AsyncThrowingStream<Value, any Error>.Continuation
    ) {
        self.initial = initial
        self.iterator = stream.makeAsyncIterator()
        self.continuation = continuation
    }

    deinit { continuation.finish() }

    func next() async throws -> Value? {
        let continuation = continuation
        return try await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            if let initial {
                self.initial = nil
                return initial
            }
            // AsyncSequence iteration is sequential. Keep the one observer's
            // iterator alive across pulls and explicitly preserve actor isolation.
            var iterator = self.iterator
            let next = try await iterator.next(isolation: self)
            self.iterator = iterator
            return next
        } onCancel: {
            continuation.finish()
        }
    }
}

nonisolated struct LibraryReadProjection: Sendable {
    let collections: [Collection]
    let locations: [SavedLocation]
    let libraryRevision: Int64
}
