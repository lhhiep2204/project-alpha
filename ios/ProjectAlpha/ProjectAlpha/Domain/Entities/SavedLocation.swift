//
//  SavedLocation.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/9/26.
//

import Foundation

nonisolated enum LocationSource: String, Hashable, Sendable {
    case appleMaps
    case currentPosition
    case droppedPin
    case manualCoordinate

    var isManual: Bool {
        switch self {
        case .droppedPin, .manualCoordinate: true
        case .appleMaps, .currentPosition: false
        }
    }
}

/// Immutable committed location value. Editing occurs through a future draft/command boundary.
nonisolated struct SavedLocation: Identifiable, Hashable, Sendable {
    let id: UUID
    let collectionID: UUID
    let placeIdentity: PlaceIdentity?
    let source: LocationSource
    let name: String
    let displayName: String?
    let address: String?
    let coordinate: Coordinate
    let category: String?
    let notes: String?
    let assets: [LocalAssetReference]
    let isFavorite: Bool
    let createdAt: Date
    let updatedAt: Date
    let revision: Int64
}
