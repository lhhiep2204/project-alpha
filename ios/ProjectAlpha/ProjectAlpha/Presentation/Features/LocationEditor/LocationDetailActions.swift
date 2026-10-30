//
//  LocationDetailActions.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 26/10/26.
//

import Foundation
import Observation

enum LocationDetailFailedAction: Equatable {
    case favorite
    case delete
}

/// Mutation state belongs to its map session. The repository remains the only writer.
@MainActor @Observable
final class LocationDetailActionModel {
    private let repository: (any LocationRepository)?
    private let clock: () -> Date
    private(set) var isPerformingAction = false
    private(set) var deleteTarget: SavedLocation?
    private(set) var deletingLocationID: UUID?
    var deleteNeedsConfirmation = false
    var actionError: LocationWriteError?
    private(set) var failedAction: LocationDetailFailedAction?
    private(set) var actionLocationID: UUID?

    init(repository: (any LocationRepository)?, clock: @escaping () -> Date = { .now }) {
        self.repository = repository
        self.clock = clock
    }

    var canMutate: Bool { repository != nil && !isPerformingAction }

    func hasFeedback(for locationID: UUID?) -> Bool {
        locationID != nil && actionLocationID == locationID
    }

    func requestDelete(_ location: SavedLocation) {
        guard canMutate else { return }
        actionError = nil
        failedAction = nil
        deleteTarget = location
        actionLocationID = location.id
        deleteNeedsConfirmation = true
    }

    func cancelDelete() {
        guard !isPerformingAction else { return }
        deleteTarget = nil
        deleteNeedsConfirmation = false
        actionError = nil
        failedAction = nil
    }

    func toggleFavorite(_ location: SavedLocation) async -> LocationCommit? {
        guard let repository, !isPerformingAction else { return nil }
        isPerformingAction = true
        actionLocationID = location.id
        actionError = nil
        failedAction = nil
        defer { isPerformingAction = false }
        do {
            guard let latest = try await repository.location(id: location.id) else {
                throw LocationWriteError.locationMissing(location.id)
            }
            guard !Task.isCancelled else { return nil }
            return try await repository.setLocationFavorite(SetLocationFavoriteCommand(
                id: latest.id, isFavorite: !latest.isFavorite, updatedAt: clock()))
        } catch {
            actionError = (error as? LocationWriteError) ?? .storageFailure
            failedAction = .favorite
            return nil
        }
    }

    /// Called only by the explicit destructive confirmation, never by an error retry.
    func deleteLocation() async -> DeleteLocationCommit? {
        guard let repository, let target = deleteTarget, !isPerformingAction else { return nil }
        isPerformingAction = true
        deletingLocationID = target.id
        deleteNeedsConfirmation = false
        actionError = nil
        failedAction = nil
        defer {
            isPerformingAction = false
            deletingLocationID = nil
        }
        do {
            let commit = try await repository.deleteLocation(DeleteLocationCommand(
                id: target.id, expectedRevision: target.revision))
            deleteTarget = nil
            return commit
        } catch LocationWriteError.editConflict(let latest) {
            deleteTarget = latest
            actionError = .editConflict(latest: latest)
        } catch {
            actionError = (error as? LocationWriteError) ?? .storageFailure
        }
        failedAction = .delete
        return nil
    }
}

/// Copy and share keep full coordinate precision, independent of locale/distance units.
struct LocationDetailPayload: Equatable {
    let name: String
    let address: String?
    let coordinate: Coordinate
    let notes: String?

    var coordinateText: String {
        String(coordinate.latitude) + Tokens.coordinateSeparator + String(coordinate.longitude)
    }

    var locationInfo: String {
        [name, address, coordinateText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: Tokens.newline)
    }

    var mapsURL: URL {
        var components = URLComponents()
        components.scheme = Tokens.scheme
        components.host = Tokens.host
        components.path = Tokens.path
        components.queryItems = [
            URLQueryItem(name: Tokens.coordinateQuery, value: coordinateText),
            URLQueryItem(name: Tokens.nameQuery, value: name)
        ]
        return components.url!
    }

    func shareText(includeNotes: Bool) -> String {
        var fields = [locationInfo, mapsURL.absoluteString]
        if includeNotes, let notes, !notes.isEmpty { fields.append(notes) }
        return fields.joined(separator: Tokens.newline)
    }

    private enum Tokens {
        static let coordinateSeparator = ", "
        static let newline = "\n"
        static let scheme = "https"
        static let host = "maps.apple.com"
        static let path = "/"
        static let coordinateQuery = "ll"
        static let nameQuery = "q"
    }
}
