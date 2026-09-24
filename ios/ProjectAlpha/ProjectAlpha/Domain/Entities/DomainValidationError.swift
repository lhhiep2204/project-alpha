import Foundation

/// Typed validation failures. Presentation supplies localized user-facing copy.
nonisolated enum DomainValidationError: Error, Equatable, Sendable {
    case invalidCoordinate
    case invalidPlaceIdentity
    case invalidAssetReference
}
