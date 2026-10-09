//
//  CollectionMutationPolicy.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 25/9/26.
//

import Foundation

/// Pure guards reused by the serialized store before any collection mutation.
nonisolated enum CollectionMutationPolicy {
    static func requireCurrentRevision(
        of summary: CollectionSummary,
        expectedRevision: Int64
    ) throws {
        guard summary.collection.revision == expectedRevision else {
            throw CollectionWriteError.editConflict(
                latest: summary.collection,
                locationCount: summary.locationCount
            )
        }
    }

    static func requireDeletable(_ collection: Collection) throws {
        guard !collection.isDefault else {
            throw CollectionWriteError.protectedDefault(collection.id)
        }
    }
}
