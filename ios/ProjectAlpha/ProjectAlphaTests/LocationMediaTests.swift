//
//  LocationMediaTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import ProjectAlpha

private enum MediaFixture {
    static let directoryPrefix = "ProjectAlphaLocationMediaTests-"
    static let defaultName = "My Places"
    static let place = "Museum"
    static let north = "N"
    static let east = "E"
    static let date = Date(timeIntervalSince1970: 100)
    static let future = Date(timeIntervalSince1970: 4_000_000_000)
    static let corruptData = Data([0, 1, 2, 3])
    static let draftsDirectory = "drafts"
    static let journalExtension = "plist"
}
private enum MediaInjectedFailure: Error { case file, database }

/// AC-21–23/41/45, INV-06/08: isolated real files and in-memory metadata, no Photos/live services.
@MainActor
struct LocationMediaTests {
    private func setup() async throws -> (ModelContainer, LibraryStore, UUID, URL) {
        let container = try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
        let store = LibraryStore(container: container)
        let destination = UUID()
        _ = try await store.bootstrap(BootstrapCollectionCommand(id: destination, name: MediaFixture.defaultName,
                                                               createdAt: MediaFixture.date))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(MediaFixture.directoryPrefix + UUID().uuidString, isDirectory: true)
        return (container, store, destination, directory)
    }
    private func image(width: Int = 32, height: Int = 16) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let raster = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        let metadata: [CFString: Any] = [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 10,
            kCGImagePropertyGPSLatitudeRef: MediaFixture.north,
            kCGImagePropertyGPSLongitude: 20,
            kCGImagePropertyGPSLongitudeRef: MediaFixture.east
        ]]
        CGImageDestinationAddImage(destination, raster, metadata as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
    private func command(destination: UUID, draftID: UUID, assets: [LocalAssetReference]) throws -> CreateLocationCommand {
        CreateLocationCommand(draft: LocationDraft(id: draftID,
            candidate: PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
                name: MediaFixture.place, address: nil, category: nil,
                coordinate: try Coordinate(latitude: 0, longitude: 0)),
            destinationCollectionID: destination, assets: assets, createdAt: MediaFixture.date))
    }

    /// AC-22/23/45, INV-06/07/08: after creation and an edit finish, another edit can import/cancel safely.
    @Test func repeatedSavedEditsImportAfterRetiredCreateAndPreserveCommittedPhotosOnCancel() async throws {
        let (container, store, destination, directory) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LocalLocationMediaService(store: store, baseDirectory: directory)
        let recordID = UUID()
        let input = try image()
        let originalAsset = try await service.preparePhoto(data: input, draftID: recordID)
        let created = try await store.createLocation(command(destination: destination,
            draftID: recordID, assets: [originalAsset]))
        await service.finishDraft(id: recordID)
        let repository = SwiftDataLocationRepository(store: store)
        let collections = SwiftDataCollectionRepository(store: store)
        let editSessionID = UUID()
        let editing = LocationCaptureModel(savedLocation: created.location, repository: repository,
            collectionRepository: collections, mediaService: service, mediaDraftID: editSessionID)
        await editing.importPhoto(data: input)
        #expect(!editing.photoImportFailed)
        #expect(editing.assets.count == 2)
        #expect(editing.id == recordID)
        #expect(editing.mediaDraftID == editSessionID)
        let newAsset = try #require(editing.assets.last)
        #expect(newAsset != originalAsset)
        await editing.save()
        let updated = try #require(editing.commit?.location)
        #expect(updated.id == recordID)
        #expect(updated.assets == [originalAsset, newAsset])
        let originalBytes = try await service.photoData(for: originalAsset, thumbnail: false)
        let editedBytes = try await service.photoData(for: newAsset, thumbnail: false)
        let nextSessionID = UUID()
        let nextEdit = LocationCaptureModel(savedLocation: updated, repository: repository,
            collectionRepository: collections, mediaService: service, mediaDraftID: nextSessionID)
        await nextEdit.importPhoto(data: input)
        #expect(!nextEdit.photoImportFailed)
        #expect(nextEdit.assets.count == 3)
        #expect(nextEdit.mediaDraftID != editing.mediaDraftID)
        let abandoned = try #require(nextEdit.assets.last)
        #expect(!updated.assets.contains(abandoned))
        await nextEdit.cancel()
        #expect(try await LibraryStore(container: container).location(id: recordID) == updated)
        #expect(try await service.photoData(for: originalAsset, thumbnail: false) == originalBytes)
        #expect(try await service.photoData(for: newAsset, thumbnail: false) == editedBytes)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(abandoned.relativeFileToken).path))
        #expect(try await store.referencedAssetIDsAndTokens().count == 2)
    }

    /// AC-21/45: one corrupt import does not remove a previous valid draft photo.
    @Test func corruptImportPreservesEarlierPhotoAndCancelRemovesOnlyDraftFiles() async throws {
        let (_, store, _, directory) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LocalLocationMediaService(store: store, baseDirectory: directory)
        let draftID = UUID()
        let asset = try await service.preparePhoto(data: image(), draftID: draftID)
        let original = try await service.photoData(for: asset, thumbnail: false)
        do { _ = try await service.preparePhoto(data: MediaFixture.corruptData, draftID: draftID); Issue.record() }
        catch LocationMediaError.invalidImage { }
        #expect(try await service.photoData(for: asset, thumbnail: false) == original)
        await service.cancelDraft(id: draftID)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.relativeFileToken).path))
    }

    /// AC-41: sixth photo is rejected before staging; large input becomes a bounded valid JPEG.
    @Test func photoLimitAndDownsamplingBoundStoredAssets() async throws {
        let (_, store, _, directory) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LocalLocationMediaService(store: store, baseDirectory: directory)
        let draftID = UUID()
        let input = try image(width: 2_200, height: 1_100)
        let inputSource = try #require(CGImageSourceCreateWithData(input as CFData, nil))
        let inputProperties = try #require(CGImageSourceCopyPropertiesAtIndex(inputSource, 0, nil) as? [CFString: Any])
        #expect(inputProperties[kCGImagePropertyGPSDictionary] != nil)
        let asset = try await service.preparePhoto(data: input, draftID: draftID)
        let bytes = try await service.photoData(for: asset, thumbnail: false)
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1_600)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 800)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let small = try image()
        for _ in 1..<5 { _ = try await service.preparePhoto(data: small, draftID: draftID) }
        do { _ = try await service.preparePhoto(data: small, draftID: draftID); Issue.record() }
        catch LocationMediaError.photoLimit { }
        #expect(try await service.photoData(for: asset, thumbnail: true).isEmpty == false)
        await service.cancelDraft(id: draftID)
    }

    /// AC-22/INV-06: a failed database commit keeps prepared bytes retryable; cancel/maintenance protect committed refs.
    @Test func databaseFailureRetryAndCancellationProtectCommittedPhoto() async throws {
        let (container, store, destination, directory) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LocalLocationMediaService(store: store, baseDirectory: directory)
        let draftID = UUID()
        let asset = try await service.preparePhoto(data: image(), draftID: draftID)
        let create = try command(destination: destination, draftID: draftID, assets: [asset])
        let failing = LibraryStore(container: container, beforeSave: { throw MediaInjectedFailure.database })
        do { _ = try await failing.createLocation(create); Issue.record() }
        catch MediaInjectedFailure.database { }
        #expect(try await failing.location(id: draftID) == nil)
        #expect(try await service.photoData(for: asset, thumbnail: false).isEmpty == false)
        let committed = try await store.createLocation(create)
        await service.cancelDraft(id: draftID)
        await service.finishDraft(id: draftID)
        var config = LocalMediaConfiguration()
        config.orphanGracePeriod = 0
        let maintenance = LocalLocationMediaService(store: store, baseDirectory: directory, configuration: config,
                                                    currentDate: { MediaFixture.future })
        try await maintenance.startMaintenance()
        #expect(try await maintenance.photoData(for: asset, thumbnail: false).isEmpty == false)
        #expect(try await LibraryStore(container: container).location(id: draftID)?.assets == committed.location.assets)
    }

    /// AC-23/INV-08: cleanup failure remains recoverable; active uncommitted media survives reconciliation.
    @Test func failedCancellationCleanupRetriesAndActiveDraftSurvivesMaintenance() async throws {
        let (_, store, _, directory) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        var config = LocalMediaConfiguration()
        config.orphanGracePeriod = 0
        let failing = LocalLocationMediaService(store: store, baseDirectory: directory, configuration: config,
            currentDate: { MediaFixture.date }, beforeFileOperation: { operation in
                if case .removeFile = operation { throw MediaInjectedFailure.file }
            })
        let draftID = UUID()
        let asset = try await failing.preparePhoto(data: image(), draftID: draftID)
        await failing.cancelDraft(id: draftID)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.relativeFileToken).path))
        let maintenance = LocalLocationMediaService(store: store, baseDirectory: directory, configuration: config,
                                                    currentDate: { MediaFixture.future })
        let activeID = UUID()
        let active = try await maintenance.preparePhoto(data: image(), draftID: activeID)
        try await maintenance.startMaintenance()
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.relativeFileToken).path))
        #expect(try await maintenance.photoData(for: active, thumbnail: false).isEmpty == false)
        await maintenance.cancelDraft(id: activeID)
    }

    /// AC-22/45: file-finalization failure does not commit a location and leaves later import usable.
    @Test func photoWriteFailureDoesNotPreventFreshServiceRetry() async throws {
        let (_, store, _, directory) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failing = LocalLocationMediaService(store: store, baseDirectory: directory,
            beforeFileOperation: { operation in if case .writePhoto = operation { throw MediaInjectedFailure.file } })
        let draftID = UUID()
        do { _ = try await failing.preparePhoto(data: image(), draftID: draftID); Issue.record() }
        catch LocationMediaError.storageFailure { }
        #expect(try await store.locationSnapshot(collectionID: nil).locations.isEmpty)
        let retry = LocalLocationMediaService(store: store, baseDirectory: directory)
        let recovered = try await retry.preparePhoto(data: image(), draftID: draftID)
        #expect(try await retry.photoData(for: recovered, thumbnail: false).isEmpty == false)
        await retry.cancelDraft(id: draftID)
    }
    /// AC-23, INV-06/08: a persistent failed journal/file cannot starve independent cleanup.
    @Test func persistentBadPhotoStillAllowsHealthyCleanupAndProtectsCommittedMedia() async throws {
        let (container, store, destination, directory) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preparer = LocalLocationMediaService(store: store, baseDirectory: directory)
        let input = try image()
        let abandoned = try await preparer.preparePhoto(data: input, draftID: UUID())
        let badURL = directory.appendingPathComponent(abandoned.relativeFileToken)
        let badJournal = directory.appendingPathComponent(MediaFixture.draftsDirectory)
            .appendingPathComponent(abandoned.assetID.uuidString).appendingPathExtension(MediaFixture.journalExtension)
        let keeperID = UUID()
        let keeper = try await preparer.preparePhoto(data: input, draftID: keeperID)
        let committed = try await store.createLocation(command(destination: destination,
            draftID: keeperID, assets: [keeper]))
        await preparer.finishDraft(id: keeperID)
        let committedBytes = try await preparer.photoData(for: keeper, thumbnail: false)
        var config = LocalMediaConfiguration()
        config.orphanGracePeriod = 0
        let maintenance = LocalLocationMediaService(store: store, baseDirectory: directory,
            configuration: config, currentDate: { MediaFixture.future }, beforeFileOperation: { operation in
                if case .removeFile(let url) = operation, url == badURL { throw MediaInjectedFailure.file }
            })
        for _ in 0..<2 {
            let healthyID = UUID()
            let healthy = try await preparer.preparePhoto(data: input, draftID: healthyID)
            _ = try await store.discardUnreferencedAsset(id: healthy.assetID)
            // A restart does not know the preparer's active drafts. Its journal is recoverable work.
            do { try await maintenance.startMaintenance(); Issue.record() }
            catch MediaInjectedFailure.file { }
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(healthy.relativeFileToken).path))
            #expect(FileManager.default.fileExists(atPath: badURL.path))
            #expect(FileManager.default.fileExists(atPath: badJournal.path))
            #expect(try await maintenance.photoData(for: keeper, thumbnail: false) == committedBytes)
            #expect(try await LibraryStore(container: container).location(id: keeperID) == committed.location)
            let pending = try await store.dueCleanupTasks(at: MediaFixture.future.addingTimeInterval(86_400))
            #expect(pending.count == 1)
            #expect(pending.first?.relativeFileToken == abandoned.relativeFileToken)
            #expect((pending.first?.attemptCount ?? 0) > 0)
        }
    }

    /// AC-23, INV-08/D-03: cancellation stops maintenance without recording a failed deletion.
    @Test func cancellationPropagatesAndReleasesMaintenanceGuardWithoutRetryPenalty() async throws {
        let (_, store, _, directory) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preparer = LocalLocationMediaService(store: store, baseDirectory: directory)
        let asset = try await preparer.preparePhoto(data: image(), draftID: UUID())
        _ = try await store.discardUnreferencedAsset(id: asset.assetID)
        var config = LocalMediaConfiguration()
        config.orphanGracePeriod = 0
        let cancelled = LocalLocationMediaService(store: store, baseDirectory: directory,
            configuration: config, currentDate: { MediaFixture.future }, beforeFileOperation: { operation in
                if case .removeFile = operation { throw CancellationError() }
            })
        // The second call must enter maintenance again; a stuck in-progress guard would return success.
        for _ in 0..<2 {
            do { try await cancelled.startMaintenance(); Issue.record() }
            catch is CancellationError { }
            let pending = try await store.dueCleanupTasks(at: MediaFixture.future)
            #expect(pending.count == 1)
            #expect(pending.first?.attemptCount == 0)
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.relativeFileToken).path))
        }
        let recovery = LocalLocationMediaService(store: store, baseDirectory: directory,
            configuration: config, currentDate: { MediaFixture.future })
        try await recovery.startMaintenance()
        #expect(try await store.dueCleanupTasks(at: MediaFixture.future).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.relativeFileToken).path))
    }
}
