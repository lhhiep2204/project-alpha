//
//  LibrarySchemaV1.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 25/9/26.
//

import Foundation
import SwiftData

enum LibrarySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [CollectionLocal.self, LocationLocal.self, AssetLocal.self, LibraryMetadataLocal.self, MediaCleanupLocal.self]
    }

    @Model
    final class CollectionLocal {
        @Attribute(.unique) var id: UUID
        var name: String
        var isDefault: Bool
        var createdAt: Date
        var updatedAt: Date
        var revision: Int64

        init(id: UUID, name: String, isDefault: Bool, createdAt: Date, updatedAt: Date, revision: Int64) {
            self.id = id
            self.name = name
            self.isDefault = isDefault
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.revision = revision
        }
    }

    @Model
    final class LocationLocal {
        @Attribute(.unique) var id: UUID
        var collectionID: UUID
        var provider: String?
        var primaryPlaceID: String?
        var alternatePlaceIDs: [String]
        var source: String
        var name: String
        var displayName: String?
        var address: String?
        var latitude: Double
        var longitude: Double
        var category: String?
        var notes: String?
        var orderedAssetIDs: [UUID]
        var isFavorite: Bool
        var createdAt: Date
        var updatedAt: Date
        var revision: Int64

        init(id: UUID, collectionID: UUID, provider: String?, primaryPlaceID: String?, alternatePlaceIDs: [String], source: String, name: String, displayName: String?, address: String?, latitude: Double, longitude: Double, category: String?, notes: String?, orderedAssetIDs: [UUID], isFavorite: Bool, createdAt: Date, updatedAt: Date, revision: Int64) {
            self.id = id
            self.collectionID = collectionID
            self.provider = provider
            self.primaryPlaceID = primaryPlaceID
            self.alternatePlaceIDs = alternatePlaceIDs
            self.source = source
            self.name = name
            self.displayName = displayName
            self.address = address
            self.latitude = latitude
            self.longitude = longitude
            self.category = category
            self.notes = notes
            self.orderedAssetIDs = orderedAssetIDs
            self.isFavorite = isFavorite
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.revision = revision
        }
    }

    @Model
    final class AssetLocal {
        @Attribute(.unique) var id: UUID
        var relativeFileToken: String
        var contentType: String
        var pixelWidth: Int
        var pixelHeight: Int
        var createdAt: Date

        init(id: UUID, relativeFileToken: String, contentType: String, pixelWidth: Int, pixelHeight: Int, createdAt: Date) {
            self.id = id
            self.relativeFileToken = relativeFileToken
            self.contentType = contentType
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.createdAt = createdAt
        }
    }

    @Model
    final class LibraryMetadataLocal {
        @Attribute(.unique) var key: String
        var revision: Int64

        init(key: String, revision: Int64) {
            self.key = key
            self.revision = revision
        }
    }

    @Model
    final class MediaCleanupLocal {
        @Attribute(.unique) var id: UUID
        var relativeFileToken: String
        var attemptCount: Int
        var nextAttemptAt: Date
        var enqueuedAt: Date

        init(id: UUID, relativeFileToken: String, attemptCount: Int, nextAttemptAt: Date, enqueuedAt: Date) {
            self.id = id
            self.relativeFileToken = relativeFileToken
            self.attemptCount = attemptCount
            self.nextAttemptAt = nextAttemptAt
            self.enqueuedAt = enqueuedAt
        }
    }
}

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum LibraryStoreConfiguration {
    nonisolated static func makeContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [configuration])
    }
}
