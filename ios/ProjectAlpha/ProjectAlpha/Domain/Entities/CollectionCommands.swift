import Foundation

/// App supplied localized initial title and deterministic identity for a fresh store.
/// A later bootstrap keeps the already committed default collection unchanged.
nonisolated struct BootstrapCollectionCommand: Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
}

/// Keep this ID and timestamp with a draft so a retry has the same intent.
nonisolated struct CreateCollectionCommand: Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
}

/// User commands cannot set or clear the system controlled default flag.
nonisolated struct UpdateCollectionCommand: Hashable, Sendable {
    let id: UUID
    let expectedRevision: Int64
    let name: String
    let updatedAt: Date
}

nonisolated struct DeleteCollectionCommand: Hashable, Sendable {
    let id: UUID
    let expectedRevision: Int64
    let expectedLocationCount: Int
}
