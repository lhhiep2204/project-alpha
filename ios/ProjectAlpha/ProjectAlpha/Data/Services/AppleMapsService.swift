//
//  AppleMapsService.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import CoreLocation
import Foundation
import MapKit

@MainActor
protocol AppleMapsDriver {
    @MainActor func reverseGeocode(_ request: ReverseGeocodeRequest) -> AppleServiceOperation<ReverseGeocodedAddress>
    @MainActor func resolve(_ request: PlaceIdentityResolutionRequest) -> AppleServiceOperation<PlaceIdentityResolution>
    @MainActor func estimateRoute(_ request: RouteRequest) -> AppleServiceOperation<RouteEstimate>
}

@MainActor
final class AppleMapsService: PlaceSearchService, PlaceIdentityResolutionService,
    ReverseGeocodingService, RouteEstimationService {
    private let driver: any AppleMapsDriver
    private let makeSearchDriver: @MainActor () -> any ApplePlaceSearchDriver

    init(
        driver: any AppleMapsDriver = MapKitMapsDriver(),
        makeSearchDriver: @escaping @MainActor () -> any ApplePlaceSearchDriver = { MapKitPlaceSearchDriver() }
    ) {
        self.driver = driver
        self.makeSearchDriver = makeSearchDriver
    }

    @MainActor func makeSearchSession(id: UUID) async -> any PlaceSearchSession {
        ApplePlaceSearchSession(id: id, makeDriver: makeSearchDriver)
    }

    @MainActor func reverseGeocode(_ request: ReverseGeocodeRequest) async throws(PlaceServiceError) -> ReverseGeocodedAddress {
        try await driver.reverseGeocode(request).value()
    }

    @MainActor func resolve(_ request: PlaceIdentityResolutionRequest) async throws(PlaceServiceError) -> PlaceIdentityResolution {
        try await driver.resolve(request).value()
    }

    @MainActor func estimateRoute(_ request: RouteRequest) async throws(PlaceServiceError) -> RouteEstimate {
        try await driver.estimateRoute(request).value()
    }
}

@MainActor
struct MapKitMapsDriver: AppleMapsDriver {
    private let clock: any ServiceClock
    init(clock: any ServiceClock = SystemServiceClock()) { self.clock = clock }

    @MainActor func reverseGeocode(_ request: ReverseGeocodeRequest) -> AppleServiceOperation<ReverseGeocodedAddress> {
        let sdkRequest = MKReverseGeocodingRequest(location: Self.location(request.coordinate))
        if let localeIdentifier = request.localeIdentifier { sdkRequest?.preferredLocale = Locale(identifier: localeIdentifier) }
        return AppleServiceOperation { completion in
            guard let sdkRequest else { completion(.failure(.invalidRequest)); return }
            sdkRequest.getMapItems { items, error in
                if let error { completion(.failure(AppleServiceErrorMapper.map(error))); return }
                // An address enriches the exact input point; a nearby provider identity is never exposed.
                completion(.success(ReverseGeocodedAddress(request: request, address: items?.first?.address?.fullAddress)))
            }
        } cancel: { sdkRequest?.cancel() }
    }

    @MainActor func resolve(_ request: PlaceIdentityResolutionRequest) -> AppleServiceOperation<PlaceIdentityResolution> {
        let sdkRequest = MKMapItem.Identifier(rawValue: request.identity.primaryID).map { MKMapItemRequest(mapItemIdentifier: $0) }
        return AppleServiceOperation { completion in
            guard let sdkRequest else { completion(.failure(.invalidRequest)); return }
            sdkRequest.getMapItem { item, error in
                if let error { completion(.failure(AppleServiceErrorMapper.map(error))); return }
                guard let item else { completion(.failure(.notFound)); return }
                do {
                    let candidate = try AppleMapItemMapper.candidate(
                        item, id: request.candidateID, knownIdentity: request.identity
                    )
                    completion(.success(PlaceIdentityResolution(request: request, candidate: candidate)))
                } catch { completion(.failure(.invalidResponse)) }
            }
        } cancel: { sdkRequest?.cancel() }
    }

    @MainActor func estimateRoute(_ request: RouteRequest) -> AppleServiceOperation<RouteEstimate> {
        let sdkRequest = MKDirections.Request()
        sdkRequest.source = MKMapItem(location: Self.location(request.origin.coordinate), address: nil)
        sdkRequest.destination = MKMapItem(location: Self.location(request.destination.coordinate), address: nil)
        sdkRequest.transportType = request.mode == .walking ? .walking : .automobile
        sdkRequest.requestsAlternateRoutes = false
        let directions = MKDirections(request: sdkRequest)
        let clock = clock
        return AppleServiceOperation(asyncRequest: {
            try Task.checkCancellation()
            let response = try await directions.calculate()
            guard let route = response.routes.first else { throw PlaceServiceError.noRoute }
            return try RouteEstimate(
                request: request, distanceMetres: route.distance,
                duration: route.expectedTravelTime, computedAt: clock.now()
            )
        }, cancel: { directions.cancel() })
    }

    private static func location(_ coordinate: Coordinate) -> CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

@MainActor
enum AppleMapItemMapper {
    private enum Text { static let missingName = "" }

    /// SDK aliases are nonexhaustive; preserve all known opaque IDs without interpreting them.
    nonisolated static func resolvedIdentity(
        primaryID: String?, alternateIDs: Set<String>, knownIdentity: PlaceIdentity?
    ) throws -> PlaceIdentity? {
        guard let primaryID = primaryID ?? knownIdentity?.primaryID else { return nil }
        return try PlaceIdentity(
            primaryID: primaryID,
            alternateIDs: alternateIDs.union(knownIdentity?.allIDs ?? [])
        )
    }

    static func candidate(_ item: MKMapItem, id: UUID, knownIdentity: PlaceIdentity? = nil) throws -> PlaceCandidate {
        let coordinate = try Coordinate(latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
        let identity = try resolvedIdentity(
            primaryID: item.identifier?.rawValue,
            alternateIDs: Set(item.alternateIdentifiers.map(\.rawValue)),
            knownIdentity: knownIdentity
        )
        return PlaceCandidate(
            id: id, source: .appleMaps, placeIdentity: identity,
            name: item.name ?? Text.missingName, address: item.address?.fullAddress,
            category: item.pointOfInterestCategory?.rawValue, coordinate: coordinate
        )
    }
}
