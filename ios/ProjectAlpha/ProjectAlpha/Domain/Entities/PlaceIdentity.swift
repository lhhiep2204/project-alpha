//
//  PlaceIdentity.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/9/26.
//

import Foundation

nonisolated enum PlaceProvider: String, Hashable, Sendable {
    case appleMaps
}

/// Opaque provider IDs for a resolved place. IDs are never lowercased or parsed.
nonisolated struct PlaceIdentity: Hashable, Sendable {
    let provider: PlaceProvider
    let primaryID: String
    let alternateIDs: Set<String>

    init(provider: PlaceProvider = .appleMaps, primaryID: String, alternateIDs: Set<String> = []) throws {
        guard !primaryID.isEmpty, alternateIDs.allSatisfy({ !$0.isEmpty }) else {
            throw DomainValidationError.invalidPlaceIdentity
        }

        self.provider = provider
        self.primaryID = primaryID
        self.alternateIDs = alternateIDs.subtracting([primaryID])
    }

    var allIDs: Set<String> {
        alternateIDs.union([primaryID])
    }
}
