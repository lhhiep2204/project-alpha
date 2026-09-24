import Foundation

nonisolated enum CollectionIcon: Hashable, Sendable {
    case symbol(name: String)
    case photo(assetID: UUID)
}
