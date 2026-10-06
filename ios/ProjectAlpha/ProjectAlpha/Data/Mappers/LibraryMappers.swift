import Foundation

nonisolated enum LibraryMappingError: Error {
    case invalidLocation
    case missingAsset(UUID)
}

nonisolated enum LibraryMappers {
    static func collection(_ local: LibrarySchemaV1.CollectionLocal) throws -> Collection {
        return Collection(
            id: local.id,
            name: local.name,
            isDefault: local.isDefault,
            createdAt: local.createdAt,
            updatedAt: local.updatedAt,
            revision: local.revision
        )
    }

    static func location(
        _ local: LibrarySchemaV1.LocationLocal,
        assetTokens: [UUID: String]
    ) throws -> SavedLocation {
        let identity: PlaceIdentity?
        if let provider = local.provider, let primaryID = local.primaryPlaceID {
            guard let placeProvider = PlaceProvider(rawValue: provider) else {
                throw LibraryMappingError.invalidLocation
            }
            identity = try PlaceIdentity(
                provider: placeProvider,
                primaryID: primaryID,
                alternateIDs: Set(local.alternatePlaceIDs)
            )
        } else if local.provider == nil && local.primaryPlaceID == nil {
            identity = nil
        } else {
            throw LibraryMappingError.invalidLocation
        }
        guard let source = LocationSource(rawValue: local.source) else {
            throw LibraryMappingError.invalidLocation
        }
        let coordinate = try Coordinate(latitude: local.latitude, longitude: local.longitude)
        let assets = try local.orderedAssetIDs.map { id in
            guard let token = assetTokens[id] else { throw LibraryMappingError.missingAsset(id) }
            return try LocalAssetReference(assetID: id, relativeFileToken: token)
        }
        return SavedLocation(
            id: local.id,
            collectionID: local.collectionID,
            placeIdentity: identity,
            source: source,
            name: local.name,
            displayName: local.displayName,
            address: local.address,
            coordinate: coordinate,
            category: local.category,
            notes: local.notes,
            assets: assets,
            isFavorite: local.isFavorite,
            createdAt: local.createdAt,
            updatedAt: local.updatedAt,
            revision: local.revision
        )
    }
}
