import Foundation

/// Immutable committed value. Editing belongs to a separate draft/command.
nonisolated struct Collection: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let isDefault: Bool
    let createdAt: Date
    let updatedAt: Date
    let revision: Int64
}
