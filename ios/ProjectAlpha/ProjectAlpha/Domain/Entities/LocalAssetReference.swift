import Foundation

/// A stable reference to app-managed local media; it never contains an absolute sandbox path.
nonisolated struct LocalAssetReference: Hashable, Sendable {
    let assetID: UUID
    let relativeFileToken: String

    init(assetID: UUID, relativeFileToken: String) throws {
        let pathComponents = URL(fileURLWithPath: relativeFileToken).pathComponents
        guard !relativeFileToken.isEmpty,
              !relativeFileToken.hasPrefix("/"),
              !pathComponents.contains("..")
        else {
            throw DomainValidationError.invalidAssetReference
        }

        self.assetID = assetID
        self.relativeFileToken = relativeFileToken
    }
}
