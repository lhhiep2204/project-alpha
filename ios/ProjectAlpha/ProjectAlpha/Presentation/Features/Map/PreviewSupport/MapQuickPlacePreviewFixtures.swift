//
//  MapQuickPlacePreviewFixtures.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 11/10/26.
//

import Foundation

@MainActor
enum MapQuickPlacePreviewFixtures {
    private static let name = "Apple Park"
    private static let address = "One Apple Park Way, Cupertino"
    private static let candidateID = "18378FB1-22D5-47D8-999B-4AEE3D8012D6"

    static let searchPlace = MapQuickPlace(
        id: .searchCandidate(UUID(uuidString: candidateID)!),
        name: name,
        address: address,
        coordinate: try! Coordinate(latitude: 37.3349, longitude: -122.0090),
        horizontalAccuracyMetres: nil,
        timestamp: nil
    )

    static let currentPlace = MapQuickPlace(
        id: .currentPosition,
        name: nil,
        address: address,
        coordinate: try! Coordinate(latitude: 37.3349, longitude: -122.0090),
        horizontalAccuracyMetres: 12,
        timestamp: Date(timeIntervalSince1970: 1_780_000_000)
    )
}
