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
            cachedCommittedSnapshot = snapshot
            publish(snapshot)
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
            let observation = CollectionSnapshotObservation(
                initial: initial,
                stream: pending.stream,
                continuation: pending.continuation
            )
            return AsyncThrowingStream(unfolding: { try await observation.next() })
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
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
    /// collection revision; the following collection command does that.
    func registerAsset(_ asset: PreparedLocalAsset) throws {
        do {
            _ = try LocalAssetReference(assetID: asset.id, relativeFileToken: asset.relativeFileToken)
            let rows = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.AssetLocal>())
            if let existing = rows.first(where: { $0.id == asset.id }) {
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
        let locations = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.LocationLocal>())
        let referenced = Set(locations.flatMap(\.orderedAssetIDs))
        let assets = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.AssetLocal>())
        let tokens = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0.relativeFileToken) })
        guard referenced.allSatisfy({ tokens[$0] != nil }) else {
            throw LibraryStoreError.invalidStoredData
        }
        return tokens.filter { referenced.contains($0.key) }
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
        try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.MediaCleanupLocal>())
            .filter { $0.nextAttemptAt <= date }
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
        let locations = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.LocationLocal>())
        let stillReferenced = Set(locations.filter { !excludingLocationIDs.contains($0.id) }.flatMap(\.orderedAssetIDs))
        let assets = try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.AssetLocal>())
        for asset in assets where assetIDs.contains(asset.id) && !stillReferenced.contains(asset.id) {
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
        guard !observers.isEmpty else { return }
        do { publish(try committedCollectionSnapshot()) }
        catch {
            for continuation in observers.values { continuation.finish(throwing: error) }
            observers.removeAll()
        }
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
private actor CollectionSnapshotObservation {
    private var initial: CollectionListSnapshot?
    private var iterator: AsyncThrowingStream<CollectionListSnapshot, any Error>.Iterator
    private let continuation: AsyncThrowingStream<CollectionListSnapshot, any Error>.Continuation

    init(
        initial: CollectionListSnapshot,
        stream: AsyncThrowingStream<CollectionListSnapshot, any Error>,
        continuation: AsyncThrowingStream<CollectionListSnapshot, any Error>.Continuation
    ) {
        self.initial = initial
        self.iterator = stream.makeAsyncIterator()
        self.continuation = continuation
    }

    deinit { continuation.finish() }

    func next() async throws -> CollectionListSnapshot? {
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
