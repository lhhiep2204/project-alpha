//
//  PlaceServiceRequests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import Foundation

/// Provider failures remain separate from saved-library and storage failures.
nonisolated enum PlaceServiceError: Error, Equatable, Sendable {
    case networkUnavailable
    case providerUnavailable
    case rateLimited
    case notFound
    case noRoute
    case invalidRequest
    case invalidResponse
    case sessionEnded
    case superseded
    case cancelled
}

/// Geographic search bias captured at request creation; it is not a saved-library scope.
nonisolated struct PlaceSearchRegion: Hashable, Sendable {
    let center: Coordinate
    let latitudeDelta: Double
    let longitudeDelta: Double

    init(center: Coordinate, latitudeDelta: Double, longitudeDelta: Double) throws(PlaceServiceError) {
        guard latitudeDelta.isFinite, longitudeDelta.isFinite,
              latitudeDelta > 0, latitudeDelta <= 180,
              longitudeDelta > 0, longitudeDelta <= 360
        else { throw .invalidRequest }
        self.center = center
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}

/// The caller owns generation changes and passes its chosen locale explicitly.
nonisolated struct PlaceSearchRequest: Hashable, Sendable {
    let sessionID: UUID
    let generation: UInt64
    let query: String
    let region: PlaceSearchRegion?
    let localeIdentifier: String?
}

nonisolated struct PlaceSuggestions: Hashable, Sendable {
    let request: PlaceSearchRequest
    let suggestions: [PlaceSuggestion]
}

/// Retains the suggestion's original request, preventing resolution in a different session.
nonisolated struct PlaceSuggestionResolutionRequest: Hashable, Sendable {
    let searchRequest: PlaceSearchRequest
    let generation: UInt64
    let suggestion: PlaceSuggestion
    let candidateID: UUID
}

nonisolated struct PlaceSuggestionResolution: Hashable, Sendable {
    let request: PlaceSuggestionResolutionRequest
    let candidate: PlaceCandidate
}

nonisolated struct PlaceIdentityResolutionRequest: Hashable, Sendable {
    let identity: PlaceIdentity
    let candidateID: UUID
    let generation: UInt64
    let localeIdentifier: String?
}

nonisolated struct PlaceIdentityResolution: Hashable, Sendable {
    let request: PlaceIdentityResolutionRequest
    let candidate: PlaceCandidate
}

nonisolated struct ReverseGeocodeRequest: Hashable, Sendable {
    let coordinate: Coordinate
    let generation: UInt64
    let localeIdentifier: String?
}

/// Address enrichment only. The exact input coordinate is retained and no business identity exists.
nonisolated struct ReverseGeocodedAddress: Hashable, Sendable {
    let request: ReverseGeocodeRequest
    let address: String?

    var coordinate: Coordinate { request.coordinate }
}
