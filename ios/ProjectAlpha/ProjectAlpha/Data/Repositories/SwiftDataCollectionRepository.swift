import Foundation

/// App-owned adapter; all reads and writes are serialized by LibraryStore.
struct SwiftDataCollectionRepository: CollectionRepository {
    let store: LibraryStore

    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot {
        try await store.bootstrap(command)
    }

    func snapshot() async throws -> CollectionListSnapshot {
        try await store.snapshot()
    }

    func collection(id: UUID) async throws -> CollectionSummary? {
        try await store.collection(id: id)
    }

    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        await store.observeSnapshots()
    }

    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        try await store.create(command)
    }

    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        try await store.update(command)
    }

    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit {
        try await store.delete(command)
    }
}
