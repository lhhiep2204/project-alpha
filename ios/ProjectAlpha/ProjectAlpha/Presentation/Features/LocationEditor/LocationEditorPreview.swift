//
//  LocationEditorPreview.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation
import UIKit

@MainActor
enum LocationEditorPreview {
    private enum Fixture {
        static let name = "Riverside Garden"
        static let address = "12 Riverside Walk"
        static let photoTokens = ["photos/preview-garden.jpg", "photos/preview-coast.jpg", "photos/preview-evening.jpg"]
        static let localeIdentifier = "en"
    }
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static let candidate = PlaceCandidate(
        id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
        source: .droppedPin, placeIdentity: nil, name: Fixture.name, address: Fixture.address,
        category: nil, coordinate: try! Coordinate(latitude: 10.78, longitude: 106.7)
    )
    static let savedLocation = SavedLocation(
        id: candidate.id, collectionID: Collection.mock.id, placeIdentity: nil,
        source: candidate.source, name: candidate.name, displayName: nil, address: candidate.address,
        coordinate: candidate.coordinate, category: nil, notes: nil, assets: [], isFavorite: true,
        createdAt: date, updatedAt: date, revision: 1
    )
    static func editModel() -> LocationCaptureModel {
        LocationCaptureModel(savedLocation: savedLocation, repository: LocationEditorPreviewRepository(),
                             collectionRepository: PreviewCollectionRepository(), mediaService: photoService(),
                             mediaDraftID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9)))
    }
    static func model(mediaService: (any LocationMediaService)? = nil) -> LocationCaptureModel {
        LocationCaptureModel(candidate: candidate, destinationCollectionID: Collection.mock.id,
                             repository: LocationEditorPreviewRepository(), collectionRepository: PreviewCollectionRepository(),
                             mediaService: mediaService, id: candidate.id, createdAt: date)
    }

    private static let locale = Locale(identifier: Fixture.localeIdentifier)
    static let photoLabel = String(format: LocalizationManager.localizedString(LocationKeys.photoNumber, locale: locale),
                                   locale: locale, Int64(1))
    static let photoAssets: [LocalAssetReference] = Fixture.photoTokens.enumerated().map { index, token in
        try! LocalAssetReference(
            assetID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, UInt8(index + 1))),
            relativeFileToken: token)
    }
    private static let photoData: [Data] = [UIColor.systemGreen, .systemBlue, .systemOrange].map { color in
        UIGraphicsImageRenderer(size: CGSize(width: 480, height: 320)).jpegData(withCompressionQuality: 0.8) { context in
            color.withAlphaComponent(0.35).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 480, height: 320))
            UIColor.systemYellow.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 310, y: 35, width: 65, height: 65))
            color.setFill()
            let hill = UIBezierPath()
            hill.move(to: CGPoint(x: 0, y: 250))
            hill.addQuadCurve(to: CGPoint(x: 480, y: 210), controlPoint: CGPoint(x: 200, y: 40))
            hill.addLine(to: CGPoint(x: 480, y: 320))
            hill.addLine(to: CGPoint(x: 0, y: 320))
            hill.close()
            hill.fill()
        }
    }
    static func photoService() -> any LocationMediaService {
        LocationEditorPreviewMedia(assets: photoAssets, images: photoData)
    }
    static func photoModel() -> LocationCaptureModel { model(mediaService: photoService()) }
    static func addPhotos(to model: LocationCaptureModel) async {
        guard model.assets.isEmpty else { return }
        for data in photoData { await model.importPhoto(data: data) }
    }
}

private actor LocationEditorPreviewMedia: LocationMediaService {
    let assets: [LocalAssetReference]
    let images: [Data]
    private var nextIndex = 0

    init(assets: [LocalAssetReference], images: [Data]) {
        self.assets = assets
        self.images = images
    }
    func preparePhoto(data: Data, draftID: UUID) async throws -> LocalAssetReference {
        guard assets.indices.contains(nextIndex) else { throw LocationMediaError.photoLimit }
        defer { nextIndex += 1 }
        return assets[nextIndex]
    }
    func photoData(for asset: LocalAssetReference, thumbnail: Bool) async throws -> Data {
        guard let index = assets.firstIndex(where: { $0.assetID == asset.assetID }) else { throw LocationMediaError.invalidImage }
        return images[index]
    }
    func discardPhoto(_ asset: LocalAssetReference, draftID: UUID) async {}
    func cancelDraft(id: UUID) async {}
    func finishDraft(id: UUID) async {}
}

private actor LocationEditorPreviewRepository: LocationRepository {
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        await LocationLibrarySnapshot(collections: [CollectionSummary(collection: .mock, locationCount: 1)],
                                      locations: [LocationEditorPreview.savedLocation], libraryRevision: 1)
    }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        let snapshot = try? await locationSnapshot(collectionID: collectionID)
        return AsyncThrowingStream { continuation in
            if let snapshot { continuation.yield(snapshot) }
            continuation.finish()
        }
    }
    func location(id: UUID) async throws -> SavedLocation? { await LocationEditorPreview.savedLocation }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit { throw LocationWriteError.storageUnavailable }
    func updateLocation(_ command: UpdateLocationCommand) async throws -> LocationCommit { throw LocationWriteError.storageUnavailable }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit { throw LocationWriteError.storageUnavailable }
}
