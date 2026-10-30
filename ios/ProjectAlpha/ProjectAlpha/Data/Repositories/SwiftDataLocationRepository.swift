//
//  SwiftDataLocationRepository.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation

/// Shares the app-owned store with collection operations and media maintenance.
struct SwiftDataLocationRepository: LocationRepository {
    let store: LibraryStore

    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        try await store.locationSnapshot(collectionID: collectionID)
    }

    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        await store.observeLocations(collectionID: collectionID)
    }

    func location(id: UUID) async throws -> SavedLocation? {
        try await store.location(id: id)
    }

    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        try await store.createLocation(command)
    }

    func updateLocation(_ command: UpdateLocationCommand) async throws -> LocationCommit {
        try await store.updateLocation(command)
    }

    func deleteLocation(_ command: DeleteLocationCommand) async throws -> DeleteLocationCommit {
        try await store.deleteLocation(command)
    }

    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        try await store.setLocationFavorite(command)
    }
}
