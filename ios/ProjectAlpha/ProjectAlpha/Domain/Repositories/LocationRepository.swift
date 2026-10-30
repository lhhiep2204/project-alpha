//
//  LocationRepository.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation

nonisolated protocol LocationRepository: Sendable {
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error>
    func location(id: UUID) async throws -> SavedLocation?
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit
    func updateLocation(_ command: UpdateLocationCommand) async throws -> LocationCommit
    func deleteLocation(_ command: DeleteLocationCommand) async throws -> DeleteLocationCommit
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit
}

extension LocationRepository {
    nonisolated func deleteLocation(_ command: DeleteLocationCommand) async throws -> DeleteLocationCommit {
        throw LocationWriteError.storageUnavailable
    }

    /// Adapters without edit support must never report an unpersisted success.
    nonisolated func updateLocation(_ command: UpdateLocationCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageUnavailable
    }
}
