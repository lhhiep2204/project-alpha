//
//  CollectionResults.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 25/9/26.
//

import Foundation

/// A collection and its count from one committed library revision.
nonisolated struct CollectionSummary: Hashable, Sendable, Identifiable {
    let collection: Collection
    let locationCount: Int

    var id: UUID { collection.id }
}

/// Data supplies the ordered rows from one consistent committed read.
nonisolated struct CollectionListSnapshot: Hashable, Sendable {
    let collections: [CollectionSummary]
    let libraryRevision: Int64
}

nonisolated struct CollectionCommit: Hashable, Sendable {
    let collection: Collection
    let libraryRevision: Int64
}

nonisolated struct DeleteCollectionCommit: Hashable, Sendable {
    let deletedCollectionID: UUID
    let deletedLocationCount: Int
    let libraryRevision: Int64
}

/// Storage maps implementation failures to these stable Domain cases.
nonisolated enum CollectionWriteError: Error, Equatable, Sendable {
    case validation(DomainValidationError)
    case collectionMissing(UUID)
    case protectedDefault(UUID)
    case editConflict(latest: Collection, locationCount: Int)
    case identifierConflict(UUID)
    case storageUnavailable
    case storageFailure
}
