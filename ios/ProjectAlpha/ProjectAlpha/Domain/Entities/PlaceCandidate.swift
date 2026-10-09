//
//  PlaceCandidate.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/9/26.
//

import Foundation

/// A resolved, unsaved place. It deliberately has no collection ownership.
nonisolated struct PlaceCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let source: LocationSource
    let placeIdentity: PlaceIdentity?
    let name: String
    let address: String?
    let category: String?
    let coordinate: Coordinate
}

/// A provider suggestion that must be resolved into a `PlaceCandidate` before it can be saved.
nonisolated struct PlaceSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
}
