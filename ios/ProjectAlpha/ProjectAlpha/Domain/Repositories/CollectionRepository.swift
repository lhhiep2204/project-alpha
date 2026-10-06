import Foundation

/// The single committed-library boundary used by collection workflows.
/// Each observer receives its own initial snapshot followed by committed revisions.
nonisolated protocol CollectionRepository: Sendable {
    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot
    func snapshot() async throws -> CollectionListSnapshot
    func collection(id: UUID) async throws -> CollectionSummary?
    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error>
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit
}
