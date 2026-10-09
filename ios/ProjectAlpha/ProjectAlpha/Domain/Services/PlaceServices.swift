//
//  PlaceServices.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import Foundation

nonisolated protocol PlaceSearchService: Sendable {
    /// Each caller supplies a stable ID and owns an independent session. Creation starts no request.
    func makeSearchSession(id: UUID) async -> any PlaceSearchSession
}

nonisolated protocol PlaceSearchSession: Sendable {
    var id: UUID { get }

    /// Empty/whitespace-only query cancels previous suggestion work and returns no suggestions.
    /// New requests supersede previous suggestion work within this session only.
    func suggestions(for request: PlaceSearchRequest) async throws(PlaceServiceError) -> PlaceSuggestions
    func resolve(_ request: PlaceSuggestionResolutionRequest) async throws(PlaceServiceError) -> PlaceSuggestionResolution

    /// Ends this session, cancels its requests and releases provider state. Safe to call repeatedly.
    func cancel() async
}

nonisolated protocol PlaceIdentityResolutionService: Sendable {
    /// Resolves an opaque ID authoritatively and retains known primary/alternate IDs.
    func resolve(_ request: PlaceIdentityResolutionRequest) async throws(PlaceServiceError) -> PlaceIdentityResolution
}

nonisolated protocol ReverseGeocodingService: Sendable {
    /// Optional address text must not infer a nearby business identity or replace the input coordinate.
    func reverseGeocode(_ request: ReverseGeocodeRequest) async throws(PlaceServiceError) -> ReverseGeocodedAddress
}

nonisolated protocol RouteEstimationService: Sendable {
    func estimateRoute(_ request: RouteRequest) async throws(PlaceServiceError) -> RouteEstimate
}
