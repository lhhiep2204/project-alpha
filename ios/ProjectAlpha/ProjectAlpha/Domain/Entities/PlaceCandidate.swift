//
//  PlaceCandidate.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/9/26.
//

import Foundation

/// The geographic scope known from authoritative place metadata, independent of map camera scale.
nonisolated enum PlaceGeographicKind: Hashable, Sendable {
    case point
    case city
    case region
    case unknown
}

/// A resolved, unsaved place. It deliberately has no collection ownership.
nonisolated struct PlaceCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let source: LocationSource
    let placeIdentity: PlaceIdentity?
    let name: String
    let address: String?
    let category: String?
    let coordinate: Coordinate
    let geographicKind: PlaceGeographicKind

    init(
        id: UUID,
        source: LocationSource,
        placeIdentity: PlaceIdentity?,
        name: String,
        address: String?,
        category: String?,
        coordinate: Coordinate,
        geographicKind: PlaceGeographicKind = .unknown
    ) {
        self.id = id
        self.source = source
        self.placeIdentity = placeIdentity
        self.name = name
        self.address = address
        self.category = category
        self.coordinate = coordinate
        self.geographicKind = geographicKind
    }
}

/// A provider suggestion that must be resolved into a `PlaceCandidate` before it can be saved.
nonisolated struct PlaceSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
}
