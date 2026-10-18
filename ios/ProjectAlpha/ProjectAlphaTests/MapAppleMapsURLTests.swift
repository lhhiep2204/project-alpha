//
//  MapAppleMapsURLTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 14/10/26.
//

import Foundation
import Testing
@testable import ProjectAlpha

/// AC-24: both map surfaces must hand off the selected provider place, not a new coordinate-only pin.
@MainActor
struct MapAppleMapsURLTests {
    @Test func selectedCandidateRetainsIdentityThroughCardAndDetailHandoff() throws {
        let identity = try PlaceIdentity(primaryID: Fixture.placeID, alternateIDs: [Fixture.alias])
        let candidate = PlaceCandidate(
            id: UUID(), source: .appleMaps, placeIdentity: identity,
            name: Fixture.name, address: Fixture.address, category: nil,
            coordinate: try Coordinate(latitude: 21.028511, longitude: 105.804817)
        )
        let model = MapViewModel(deviceLocationService: UnusedLocationService())
        model.selectSearchCandidate(candidate)
        let card = try #require(model.visiblePlace)
        model.showDetails()
        let detail = try #require(model.selectedDetail)

        #expect(card.placeIdentity == identity)
        #expect(detail.placeIdentity == identity)
        let cardURL = try makeURL(card)
        let detailURL = try makeURL(detail)
        #expect(cardURL == detailURL)
        let components = try #require(URLComponents(url: detailURL, resolvingAgainstBaseURL: false))
        #expect(components.scheme == Fixture.scheme)
        #expect(components.host == Fixture.host)
        #expect(components.path == Fixture.path)
        #expect(value(.placeID, in: components) == Fixture.placeID)
        #expect(value(.coordinate, in: components) == Fixture.coordinate)
        #expect(value(.name, in: components) == Fixture.name)
        #expect(value(.address, in: components) == Fixture.address)
    }

    @Test func namesAddressesAndOpaqueIdentifiersCannotInjectQueryParameters() throws {
        let place = try makePlace(identity: PlaceIdentity(primaryID: Fixture.opaqueID))
        let url = try makeURL(place)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.count == 4)
        #expect(components.fragment == nil)
        #expect(value(.placeID, in: components) == Fixture.opaqueID)
        #expect(value(.address, in: components) == Fixture.address)
        #expect(value(.name, in: components) == Fixture.name)
        #expect(url.absoluteString.contains(Fixture.encodedPlus))
    }

    @Test func coordinateOnlyPositionKeepsExactFixWithoutInventingAPlaceID() throws {
        let place = MapQuickPlace(
            id: .currentPosition, name: nil, address: nil,
            coordinate: try Coordinate(latitude: -33.856784, longitude: 151.215297),
            horizontalAccuracyMetres: 10, timestamp: Date(timeIntervalSinceReferenceDate: 100)
        )
        let components = try #require(URLComponents(url: makeURL(place), resolvingAgainstBaseURL: false))
        #expect(value(.placeID, in: components) == nil)
        #expect(value(.address, in: components) == nil)
        #expect(value(.coordinate, in: components) == Fixture.southernCoordinate)
        #expect(value(.name, in: components) == Fixture.fallbackName)
    }

    @Test(arguments: [nil, Fixture.emptyAddress, Fixture.address])
    func candidateWithoutIdentityKeepsCoordinateAndAvailableAddress(address: String?) throws {
        let place = try makePlace(address: address)
        let components = try #require(URLComponents(url: makeURL(place), resolvingAgainstBaseURL: false))
        #expect(value(.placeID, in: components) == nil)
        #expect(value(.coordinate, in: components) == Fixture.coordinate)
        #expect(value(.name, in: components) == Fixture.name)
        #expect(value(.address, in: components) == (address?.isEmpty == false ? address : nil))
    }

    private func makePlace(address: String? = Fixture.address, identity: PlaceIdentity? = nil) throws -> MapQuickPlace {
        MapQuickPlace(
            id: .searchCandidate(UUID()), name: Fixture.name, address: address,
            coordinate: try Coordinate(latitude: 21.028511, longitude: 105.804817),
            horizontalAccuracyMetres: nil, timestamp: nil, placeIdentity: identity
        )
    }

    private func makeURL(_ place: MapQuickPlace) throws -> URL {
        try #require(MapAppleMapsURL.make(for: place, fallbackName: Fixture.fallbackName))
    }

    private func value(_ parameter: Parameter, in components: URLComponents) -> String? {
        components.queryItems?.first { $0.name == parameter.rawValue }?.value
    }

    private enum Parameter: String {
        case placeID = "place-id"
        case coordinate
        case name
        case address
    }

    private enum Fixture {
        static let placeID = "IF149E70A3B3C4CB2"
        static let alias = "known-alternate-place-id"
        static let opaqueID = "Opaque+ID&place-id=other#part%20"
        static let name = "Cà phê A & B + 50% #1 / 東京"
        static let address = "1 Đường số 2? &name=other + Quận 1"
        static let emptyAddress = ""
        static let fallbackName = "Vị trí của tôi"
        static let coordinate = "21.028511,105.804817"
        static let southernCoordinate = "-33.856784,151.215297"
        static let scheme = "https"
        static let host = "maps.apple.com"
        static let path = "/place"
        static let encodedPlus = "%2B"
    }
}

private nonisolated struct UnusedLocationService: DeviceLocationService {
    func authorization() async -> LocationAuthorization {
        Issue.record()
        return LocationAuthorization(status: .denied, accuracy: .full, servicesEnabled: true)
    }

    func currentPosition() async throws(LocationServiceError) -> DevicePosition {
        Issue.record()
        throw .permissionDenied
    }
}
