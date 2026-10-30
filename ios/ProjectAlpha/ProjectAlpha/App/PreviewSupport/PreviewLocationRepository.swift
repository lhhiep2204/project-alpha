//
//  PreviewLocationRepository.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation

/// App-composition previews never open the persistent library or media directories.
actor PreviewLocationRepository: LocationRepository {
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        LocationLibrarySnapshot(
            collections: [CollectionSummary(collection: .mock, locationCount: 0)],
            locations: [], libraryRevision: 1
        )
    }

    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        let snapshot = try? await locationSnapshot(collectionID: collectionID)
        return AsyncThrowingStream { continuation in
            if let snapshot { continuation.yield(snapshot) }
            continuation.finish()
        }
    }

    func location(id: UUID) async throws -> SavedLocation? { nil }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageUnavailable
    }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageUnavailable
    }
}
