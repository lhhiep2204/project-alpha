//
//  LocationCommands.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation

/// One identity and timestamp survive destination changes, optional details and retries.
nonisolated struct LocationDraft: Hashable, Sendable, Identifiable {
    let id: UUID
    let candidate: PlaceCandidate
    let destinationCollectionID: UUID
    let displayName: String?
    let notes: String?
    let assets: [LocalAssetReference]
    let createdAt: Date

    init(id: UUID, candidate: PlaceCandidate, destinationCollectionID: UUID,
         displayName: String? = nil, notes: String? = nil,
         assets: [LocalAssetReference] = [], createdAt: Date) {
        self.id = id
        self.candidate = candidate
        self.destinationCollectionID = destinationCollectionID
        self.displayName = displayName
        self.notes = notes
        self.assets = assets
        self.createdAt = createdAt
    }
}

nonisolated struct CreateLocationCommand: Hashable, Sendable {
    let draft: LocationDraft
    let acknowledgedWarning: DuplicateWarningToken?

    init(draft: LocationDraft, acknowledgedWarning: DuplicateWarningToken? = nil) {
        self.draft = draft
        self.acknowledgedWarning = acknowledgedWarning
    }
}

/// Editing changes user details and ownership while retaining the committed place.
nonisolated struct UpdateLocationCommand: Hashable, Sendable {
    let draft: LocationDraft
    let expectedRevision: Int64
    let acknowledgedWarning: DuplicateWarningToken?

    init(draft: LocationDraft, expectedRevision: Int64,
         acknowledgedWarning: DuplicateWarningToken? = nil) {
        self.draft = draft
        self.expectedRevision = expectedRevision
        self.acknowledgedWarning = acknowledgedWarning
    }
}

nonisolated struct DeleteLocationCommand: Hashable, Sendable {
    let id: UUID
    let expectedRevision: Int64
}

nonisolated struct SetLocationFavoriteCommand: Hashable, Sendable {
    let id: UUID
    let isFavorite: Bool
    let updatedAt: Date
}
