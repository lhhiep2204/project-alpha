//
//  MapSearchPreviewFixtures.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 9/10/26.
//

import Foundation

@MainActor
enum MapSearchPreviewFixtures {
    private static let title = "Apple Park"
    private static let address = "One Apple Park Way, Cupertino"
    private static let suggestionID = "preview.applePark"
    private static let candidateID = "18378FB1-22D5-47D8-999B-4AEE3D8012D6"

    static let suggestion = PlaceSuggestion(id: suggestionID, title: title, subtitle: address)
    static let candidate = PlaceCandidate(
        id: UUID(uuidString: candidateID)!,
        source: .appleMaps,
        placeIdentity: nil,
        name: title,
        address: address,
        category: nil,
        coordinate: try! Coordinate(latitude: 37.3349, longitude: -122.0090)
    )
}
