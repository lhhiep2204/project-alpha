//
//  LocationResults.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation

/// Collections and scoped lightweight location values from one committed revision.
nonisolated struct LocationLibrarySnapshot: Hashable, Sendable {
    let collections: [CollectionSummary]
    let locations: [SavedLocation]
    let libraryRevision: Int64
}

nonisolated struct LocationCommit: Hashable, Sendable {
    let location: SavedLocation
    let libraryRevision: Int64
}

nonisolated struct DeleteLocationCommit: Hashable, Sendable {
    let deletedLocationID: UUID
    let libraryRevision: Int64
}

nonisolated enum LocationWriteError: Error, Equatable, Sendable {
    case validation(LocationValidationError)
    case destinationMissing(UUID)
    case locationMissing(UUID)
    case editConflict(latest: SavedLocation)
    case blockingDuplicate(existingLocationID: UUID, reason: BlockingDuplicateReason)
    case possibleDuplicates(candidateIDs: [UUID], evaluationToken: DuplicateWarningToken)
    case identifierConflict(UUID)
    case invalidAssets
    case storageUnavailable
    case storageFailure
}

nonisolated enum LocationValidationError: Error, Equatable, Sendable {
    case nameRequired
    case manualNameTooLong
    case displayNameTooLong
    case notesTooLong
    case tooManyPhotos
    case invalidDate
}
