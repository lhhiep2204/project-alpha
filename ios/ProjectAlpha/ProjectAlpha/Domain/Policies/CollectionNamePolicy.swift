import Foundation

/// The persisted collection name is literal user content after trimming.
nonisolated enum CollectionNamePolicy {
    static let maximumGraphemeClusters = 30

    static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainValidationError.collectionNameRequired
        }
        guard trimmed.count <= maximumGraphemeClusters else {
            throw DomainValidationError.collectionNameTooLong(maximum: maximumGraphemeClusters)
        }
        return trimmed
    }
}
