//
//  MapAppleMapsURL.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 14/10/26.
//

import Foundation

/// Opens the provider's place card, retaining the exact coordinate for places without an identity.
enum MapAppleMapsURL {
    static func make(for place: MapQuickPlace, fallbackName: String) -> URL? {
        var components = URLComponents()
        components.scheme = Constants.scheme
        components.host = Constants.host
        components.path = Constants.placePath

        var queryItems: [URLQueryItem] = []
        if let identity = place.placeIdentity {
            queryItems.append(URLQueryItem(name: Parameter.placeID.rawValue, value: identity.primaryID))
        }
        if let address = place.address, !address.isEmpty {
            queryItems.append(URLQueryItem(name: Parameter.address.rawValue, value: address))
        }
        let coordinate = String(place.coordinate.latitude) + Constants.coordinateSeparator
            + String(place.coordinate.longitude)
        queryItems.append(URLQueryItem(name: Parameter.coordinate.rawValue, value: coordinate))
        queryItems.append(URLQueryItem(name: Parameter.name.rawValue, value: place.name ?? fallbackName))
        components.queryItems = queryItems
        // Preserve literal plus signs even when the recipient applies form-style query decoding.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(
            of: Constants.plus, with: Constants.encodedPlus
        )
        return components.url
    }

    private enum Parameter: String {
        case placeID = "place-id"
        case address
        case coordinate
        case name
    }

    private enum Constants {
        static let scheme = "https"
        static let host = "maps.apple.com"
        static let placePath = "/place"
        static let coordinateSeparator = ","
        static let plus = "+"
        static let encodedPlus = "%2B"
    }
}
