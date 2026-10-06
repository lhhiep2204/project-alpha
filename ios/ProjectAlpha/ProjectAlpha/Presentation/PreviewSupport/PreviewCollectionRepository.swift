import Foundation

/// Deterministic preview data; never opens the user's SwiftData store.
actor PreviewCollectionRepository: CollectionRepository {
    private let value = CollectionListSnapshot(
        collections: [CollectionSummary(collection: .mock, locationCount: 0)],
        libraryRevision: 1
    )

    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot { value }
    func snapshot() async throws -> CollectionListSnapshot { value }
    func collection(id: UUID) async throws -> CollectionSummary? {
        value.collections.first { $0.id == id }
    }
    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        let snapshot = value
        return AsyncThrowingStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        throw CollectionWriteError.storageUnavailable
    }
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        throw CollectionWriteError.storageUnavailable
    }
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit {
        throw CollectionWriteError.storageUnavailable
    }
}
