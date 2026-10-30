//
//  ScopedAssetQueryTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 27/10/26.
//

import Foundation
import SwiftData
import Testing
@testable import ProjectAlpha

private enum ScopedAssetFixture {
    static let directoryPrefix = "ProjectAlphaScopedAssetTests-"
    static let databaseName = "library.sqlite"
    static let collectionName = "Scoped assets"
    static let otherCollectionName = "Other assets"
    static let locationName = "Seeded photo location"
    static let photoPrefix = "photos/"
    static let photoSuffix = ".jpg"
    static let contentType = "image/jpeg"
    static let date = Date(timeIntervalSince1970: 100)
    static let future = Date(timeIntervalSince1970: 4_000_000_000)
    static let locationCount = 48
    static let unrelatedAssetCount = 256

    static func token(_ id: UUID) -> String { photoPrefix + id.uuidString + photoSuffix }
    static func prepared(_ id: UUID, token: String? = nil) -> PreparedLocalAsset {
        PreparedLocalAsset(id: id, relativeFileToken: token ?? self.token(id),
            contentType: contentType, pixelWidth: 32, pixelHeight: 16, createdAt: date)
    }
}

/// INV-05/06, AC-21/23/65, D-20: exact projection/validation with unrelated assets.
/// The disk case is supplemental isolated SQLite predicate-translation coverage, not performance evidence.
@MainActor
struct ScopedAssetQueryTests {
    @Test(arguments: [false, true])
    func scopedAssetProjectionPreservesOrderAndQueuedTokenIsolation(onDisk: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            ScopedAssetFixture.directoryPrefix + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container: ModelContainer
        if onDisk {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let schema = Schema(versionedSchema: LibrarySchemaV1.self)
            let configuration = ModelConfiguration(schema: schema,
                url: directory.appendingPathComponent(ScopedAssetFixture.databaseName), cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                           configurations: [configuration])
        } else {
            container = try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
        }
        let firstID = UUID()
        let writer = LibraryStore(container: container)
        _ = try await writer.bootstrap(BootstrapCollectionCommand(id: firstID,
            name: ScopedAssetFixture.collectionName, createdAt: ScopedAssetFixture.date))
        let second = try await writer.create(CreateCollectionCommand(id: UUID(),
            name: ScopedAssetFixture.otherCollectionName, createdAt: ScopedAssetFixture.date))
        let expected = try seed(container: container, firstID: firstID, secondID: second.collection.id)
        let store = LibraryStore(container: container)
        let global = try await store.locationSnapshot(collectionID: nil)
        #expect(global.locations.count == ScopedAssetFixture.locationCount)
        for collectionID in [firstID, second.collection.id] {
            let scoped = try await store.locationSnapshot(collectionID: collectionID)
            #expect(scoped.locations.count == ScopedAssetFixture.locationCount / 2)
            #expect(scoped.locations == global.locations.filter { $0.collectionID == collectionID })
            for location in scoped.locations {
                #expect(location.assets == expected[location.id])
                #expect(try await store.location(id: location.id) == location)
            }
        }
        let referenced = try await store.referencedAssetIDsAndTokens()
        #expect(referenced.count == ScopedAssetFixture.locationCount * 5)
        for reference in expected.values.flatMap({ $0 }) {
            #expect(referenced[reference.assetID] == reference.relativeFileToken)
        }

        let abandoned = ScopedAssetFixture.prepared(UUID())
        try await store.registerAsset(abandoned)
        _ = try await store.discardUnreferencedAsset(id: abandoned.id)
        let valid = ScopedAssetFixture.prepared(UUID())
        try await store.registerAsset(valid)
        let validReference = try LocalAssetReference(assetID: valid.id, relativeFileToken: valid.relativeFileToken)
        let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: ScopedAssetFixture.locationName, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 80, longitude: 0))
        let draft = LocationDraft(id: UUID(), candidate: candidate, destinationCollectionID: firstID,
                                  assets: [validReference], createdAt: ScopedAssetFixture.date)
        let committed = try await store.createLocation(CreateLocationCommand(draft: draft))
        // An unrelated queued token cannot reject valid registration or a commit.
        #expect(committed.location.assets == [validReference])
        // Validation mapped this asset through an ID/token projection on the same writer.
        // Exact re-registration must still resolve all stored metadata without changing references.
        try await store.registerAsset(valid)
        #expect(try await store.location(id: committed.location.id)?.assets == [validReference])
        #expect(try await LibraryStore(container: container).location(id: committed.location.id) == committed.location)
        let beforeRejectedWrites = try await store.locationSnapshot(collectionID: nil)
        do {
            try await store.registerAsset(ScopedAssetFixture.prepared(UUID(), token: abandoned.relativeFileToken))
            Issue.record()
        } catch LibraryStoreError.invalidStoredData { }
        let queuedReference = try LocalAssetReference(assetID: abandoned.id,
                                                      relativeFileToken: abandoned.relativeFileToken)
        let rejectedDraft = LocationDraft(id: UUID(), candidate: candidate,
            destinationCollectionID: second.collection.id, assets: [queuedReference], createdAt: ScopedAssetFixture.date)
        do {
            _ = try await store.createLocation(CreateLocationCommand(draft: rejectedDraft))
            Issue.record()
        } catch LocationWriteError.invalidAssets { }
        let reload = LibraryStore(container: container)
        #expect(try await reload.locationSnapshot(collectionID: nil) == beforeRejectedWrites)
        let pending = try await reload.dueCleanupTasks(at: ScopedAssetFixture.future)
        #expect(pending.count == 1)
        #expect(pending.first?.relativeFileToken == abandoned.relativeFileToken)
        #expect(try await reload.assetToken(id: valid.id) == valid.relativeFileToken)
    }

    /// Seed once so test cost comes from the meaningful query boundary, not hundreds of commits.
    private func seed(container: ModelContainer, firstID: UUID, secondID: UUID) throws -> [UUID: [LocalAssetReference]] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var expected: [UUID: [LocalAssetReference]] = [:]
        for index in 0..<ScopedAssetFixture.locationCount {
            let locationID = UUID()
            var references: [LocalAssetReference] = []
            for _ in 0..<5 {
                let asset = ScopedAssetFixture.prepared(UUID())
                context.insert(row(asset))
                references.insert(try LocalAssetReference(assetID: asset.id,
                    relativeFileToken: asset.relativeFileToken), at: 0)
            }
            expected[locationID] = references
            context.insert(LibrarySchemaV1.LocationLocal(id: locationID,
                collectionID: index.isMultiple(of: 2) ? firstID : secondID,
                provider: nil, primaryPlaceID: nil, alternatePlaceIDs: [], source: LocationSource.manualCoordinate.rawValue,
                name: ScopedAssetFixture.locationName, displayName: nil, address: nil,
                latitude: Double(index), longitude: 0, category: nil, notes: nil,
                orderedAssetIDs: references.map(\.assetID), isFavorite: false,
                createdAt: ScopedAssetFixture.date, updatedAt: ScopedAssetFixture.date, revision: 1))
        }
        for _ in 0..<ScopedAssetFixture.unrelatedAssetCount { context.insert(row(ScopedAssetFixture.prepared(UUID()))) }
        try context.save()
        return expected
    }

    private func row(_ asset: PreparedLocalAsset) -> LibrarySchemaV1.AssetLocal {
        LibrarySchemaV1.AssetLocal(id: asset.id, relativeFileToken: asset.relativeFileToken,
            contentType: asset.contentType, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
            createdAt: asset.createdAt)
    }
}
