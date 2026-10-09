//
//  LocalAssetReference.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/9/26.
//

import Foundation

/// A stable reference to app-managed local media; it never contains an absolute sandbox path.
nonisolated struct LocalAssetReference: Hashable, Sendable {
    private enum PathToken {
        static let separator = "/"
        static let parentDirectory = ".."
    }

    let assetID: UUID
    let relativeFileToken: String

    init(assetID: UUID, relativeFileToken: String) throws {
        let pathComponents = URL(fileURLWithPath: relativeFileToken).pathComponents
        guard !relativeFileToken.isEmpty,
              !relativeFileToken.hasPrefix(PathToken.separator),
              !pathComponents.contains(PathToken.parentDirectory)
        else {
            throw DomainValidationError.invalidAssetReference
        }

        self.assetID = assetID
        self.relativeFileToken = relativeFileToken
    }
}
