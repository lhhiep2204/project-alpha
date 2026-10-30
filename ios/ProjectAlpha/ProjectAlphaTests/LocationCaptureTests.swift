//
//  LocationCaptureTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import CoreLocation
import Foundation
import MapKit
import SwiftUI
import Testing
@testable import ProjectAlpha

private enum CaptureFixture {
    static let place = "Resolved place"
    static let collectionName = "Capture collection"
    static let enrichedAddress = "123 Museum Road"
    static let customName = "My optional name"
    static let notes = "Keep optional notes on failure"
    static let token = "photos/test.jpg"
    static let date = Date(timeIntervalSince1970: 100)
    static let image = Data([1, 2, 3])
}

private actor CaptureRepository: LocationRepository {
    let started = CollectionObservationGate()
    let release = CollectionObservationGate()
    private let suspended: Bool
    private let commitRevision: Int64
    private var failure: LocationWriteError?
    private(set) var commands: [CreateLocationCommand] = []

    init(suspended: Bool = false, failure: LocationWriteError? = nil, commitRevision: Int64 = 1) {
        self.commitRevision = commitRevision
        self.suspended = suspended
        self.failure = failure
    }
    func allowSuccess() { failure = nil }
    func fail(with error: LocationWriteError) { failure = error }
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        LocationLibrarySnapshot(collections: [], locations: [], libraryRevision: 0)
    }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func location(id: UUID) async throws -> SavedLocation? { nil }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageFailure
    }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        commands.append(command)
        await started.open()
        if suspended { await release.wait() }
        if let failure { throw failure }
        let draft = command.draft
        let place = draft.candidate
        return LocationCommit(location: SavedLocation(id: draft.id, collectionID: draft.destinationCollectionID,
            placeIdentity: place.placeIdentity, source: place.source, name: place.name,
            displayName: draft.displayName, address: place.address, coordinate: place.coordinate,
            category: place.category, notes: draft.notes, assets: draft.assets, isFavorite: false,
            createdAt: draft.createdAt, updatedAt: draft.createdAt, revision: 1), libraryRevision: commitRevision)
    }
}

private actor CaptureMedia: LocationMediaService {
    let started = CollectionObservationGate()
    let release = CollectionObservationGate()
    let asset: LocalAssetReference
    let suspended: Bool
    private(set) var preparedDraftIDs: [UUID] = []
    private(set) var discarded: [LocalAssetReference] = []
    private(set) var cancelled: [UUID] = []
    private(set) var finished: [UUID] = []
    init(suspended: Bool = false) throws {
        self.suspended = suspended
        asset = try LocalAssetReference(assetID: UUID(), relativeFileToken: CaptureFixture.token)
    }
    func preparePhoto(data: Data, draftID: UUID) async throws -> LocalAssetReference {
        preparedDraftIDs.append(draftID)
        await started.open()
        if suspended { await release.wait() }
        return asset
    }
    func photoData(for asset: LocalAssetReference, thumbnail: Bool) async throws -> Data { CaptureFixture.image }
    func discardPhoto(_ asset: LocalAssetReference, draftID: UUID) async { discarded.append(asset) }
    func cancelDraft(id: UUID) async { cancelled.append(id) }
    func finishDraft(id: UUID) async { finished.append(id) }
}

/// AC-44–48/INV-08: one draft owns optional details, destination, photos and retry state.
@MainActor
struct LocationCaptureTests {
    private func model(repository: CaptureRepository, media: CaptureMedia? = nil) throws -> LocationCaptureModel {
        let candidate = PlaceCandidate(id: UUID(), source: .currentPosition, placeIdentity: nil,
            name: CaptureFixture.place, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 10, longitude: 20))
        return LocationCaptureModel(candidate: candidate, destinationCollectionID: UUID(), repository: repository,
            collectionRepository: UnavailableCollectionRepository(), mediaService: media, createdAt: CaptureFixture.date)
    }

    /// AC-44/47: pending and completed Save delivery cannot issue another create or replace the frozen coordinate.
    @Test func pendingDoubleSaveAndCommittedSaveDeliverExactlyOnce() async throws {
        let repository = CaptureRepository(suspended: true)
        let capture = try model(repository: repository)
        let original = capture.draft
        let saving = Task { await capture.save() }
        await repository.started.wait()
        #expect(capture.isSaving)
        await capture.save()
        capture.destinationCollectionID = UUID()
        capture.notes = CaptureFixture.notes
        await repository.release.open()
        await saving.value
        #expect(capture.commit?.location.id == original.id)
        #expect(capture.commit?.location.coordinate == original.candidate.coordinate)
        #expect(capture.commit?.location.collectionID == original.destinationCollectionID)
        #expect(capture.draft == original)
        await capture.save()
        #expect(await repository.commands.count == 1)
    }

    /// AC-45/47, INV-05/08: failed storage retains every field and staged photo for the same retry UUID.
    @Test func failedSaveRetainsDetailsDestinationPhotoAndIdentity() async throws {
        let repository = CaptureRepository(failure: .storageFailure)
        let media = try CaptureMedia()
        let capture = try model(repository: repository, media: media)
        capture.destinationCollectionID = UUID()
        capture.displayName = CaptureFixture.customName
        capture.notes = CaptureFixture.notes
        await capture.importPhoto(data: CaptureFixture.image)
        let original = capture.draft
        await capture.save()
        #expect(capture.saveError == .storageFailure)
        #expect(capture.commit == nil)
        #expect(capture.draft == original)
        #expect(await media.finished.isEmpty)
        await repository.allowSuccess()
        await capture.save()
        #expect(capture.commit?.location.id == original.id)
        #expect(capture.commit?.location.assets == original.assets)
        #expect(await repository.commands.map(\.draft) == [original, original])
        #expect(await media.finished == [original.id])
    }

    /// AC-45/INV-08: cancelling Add Details removes optional media without retiring quick capture.
    @Test func discardOptionalDetailsKeepsCandidateAndStableDraftSaveable() async throws {
        let repository = CaptureRepository()
        let media = try CaptureMedia()
        let capture = try model(repository: repository, media: media)
        let original = capture.draft
        capture.displayName = CaptureFixture.customName
        capture.notes = CaptureFixture.notes
        capture.destinationCollectionID = UUID()
        await capture.importPhoto(data: CaptureFixture.image)
        #expect(capture.isDirty)
        let importedAssets = capture.assets
        #expect(importedAssets.count == 1)
        await capture.discardDetails()
        #expect(capture.id == original.id)
        #expect(capture.candidate == original.candidate)
        #expect(capture.destinationCollectionID == original.destinationCollectionID)
        #expect(!capture.isDirty)
        #expect(capture.assets.isEmpty)
        #expect(await media.discarded == importedAssets)
        await capture.save()
        #expect(capture.commit?.location.id == original.id)
    }

    /// INV-08: cancellation while an import is suspended discards the late result and prevents a late save.
    @Test func cancelledDraftCannotAcquireLatePhotoOrCommit() async throws {
        let repository = CaptureRepository()
        let media = try CaptureMedia(suspended: true)
        let capture = try model(repository: repository, media: media)
        let importing = Task { await capture.importPhoto(data: CaptureFixture.image) }
        await media.started.wait()
        await capture.cancel()
        await media.release.open()
        await importing.value
        await capture.save()
        #expect(capture.assets.isEmpty)
        #expect(await repository.commands.isEmpty)
        #expect(await media.discarded == [media.asset])
        #expect(await media.cancelled == [capture.id])
    }

    /// AC-45/58, INV-09: closing a nested picker cannot release the clean parent editor's capture ownership.
    @Test func nestedEditorOwnersRetainCaptureUntilEveryOwnerCloses() throws {
        let capture = try model(repository: CaptureRepository())
        let parent = UUID()
        let child = UUID()
        capture.beginEditing(ownerID: parent)
        capture.beginEditing(ownerID: child)
        #expect(capture.isEditing)
        #expect(!capture.isDirty)
        capture.endEditing(ownerID: child)
        #expect(capture.isEditing)
        capture.endEditing(ownerID: child)
        #expect(capture.isEditing)
        capture.endEditing(ownerID: parent)
        #expect(!capture.isEditing)
    }

    /// AC-45/INV-08: a picker load owned by discarded details cannot start a late media import.
    @Test func discardedPickerSelectionCannotImportAndCannotFinishNewerSelection() async throws {
        let repository = CaptureRepository()
        let media = try CaptureMedia()
        let capture = try model(repository: repository, media: media)
        let stale = try #require(capture.beginPhotoSelection())
        #expect(capture.isDirty)
        await capture.discardDetails()
        #expect(!capture.acceptsPhotoSelection(generation: stale))
        let current = try #require(capture.beginPhotoSelection())
        capture.finishPhotoSelection(generation: stale)
        #expect(capture.isLoadingPhotoSelection)
        await capture.importPhoto(data: CaptureFixture.image, selectionGeneration: stale)
        #expect(await media.preparedDraftIDs.isEmpty)
        #expect(capture.assets.isEmpty)
        #expect(capture.acceptsPhotoSelection(generation: current))
        await capture.importPhoto(data: CaptureFixture.image, selectionGeneration: current)
        capture.finishPhotoSelection(generation: current)
        #expect(!capture.isLoadingPhotoSelection)
        #expect(capture.assets.count == 1)
        #expect(await media.preparedDraftIDs == [capture.id])
    }

    /// AC-45/47: Save waits for transferable loading before media staging has begun.
    @Test func saveDuringPickerLoadingCannotCommitIncompletePhotos() async throws {
        let repository = CaptureRepository()
        let media = try CaptureMedia()
        let capture = try model(repository: repository, media: media)
        let generation = try #require(capture.beginPhotoSelection())
        await capture.save()
        #expect(await repository.commands.isEmpty)
        #expect(capture.commit == nil)
        #expect(capture.isLoadingPhotoSelection)
        await capture.importPhoto(data: CaptureFixture.image, selectionGeneration: generation)
        await capture.save()
        #expect(await repository.commands.isEmpty)
        capture.finishPhotoSelection(generation: generation)
        await capture.save()
        #expect(capture.commit?.location.assets.count == 1)
        #expect(await repository.commands.count == 1)
    }

    private func mapSnapshot(destination: UUID, other: UUID, revision: Int64 = 1,
                             locations: [SavedLocation] = []) -> LocationLibrarySnapshot {
        LocationLibrarySnapshot(collections: [destination, other].map { id in
            CollectionSummary(collection: Collection(id: id, name: CaptureFixture.collectionName,
                isDefault: id == destination, createdAt: CaptureFixture.date,
                updatedAt: CaptureFixture.date, revision: 1),
                locationCount: locations.filter { $0.collectionID == id }.count)
        }, locations: locations, libraryRevision: revision)
    }

    /// J-04/AC-45/INV-08: a newer one-shot fix cannot replace the frozen current-position draft or its optional edits.
    @Test(arguments: [false, true])
    func currentPositionRefreshPreservesFrozenCaptureCoordinateAndDraft(cleanEditor: Bool) async throws {
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        let original = try DevicePosition(coordinate: Coordinate(latitude: 10, longitude: 20),
            timestamp: CaptureFixture.date, horizontalAccuracyMetres: 5,
            authorization: MapPresentationLocationService.allowed)
        positions.immediateResult = .success(original)
        let repository = CaptureRepository()
        let map = MapViewModel(deviceLocationService: positions, positionClock: { CaptureFixture.date },
            locationRepository: repository, collectionRepository: UnavailableCollectionRepository())
        let destination = UUID()
        map.applyLibrarySnapshot(mapSnapshot(destination: destination, other: UUID()))
        #expect(await map.activate() == nil)
        positions.immediateResult = nil
        let refreshing = Task { await map.recenter() }
        await positions.waitForPositionRequest(2)
        map.prepareCapture(fallbackName: CaptureFixture.place)
        let capture = try #require(map.capture)
        if cleanEditor { capture.beginEditing() }
        else { capture.notes = CaptureFixture.notes }
        let frozen = capture.draft
        let newer = try DevicePosition(coordinate: Coordinate(latitude: 11, longitude: 21),
            timestamp: CaptureFixture.date, horizontalAccuracyMetres: 4,
            authorization: MapPresentationLocationService.allowed)
        positions.complete(2, with: .success(newer))
        #expect(await refreshing.value == nil)
        #expect(map.currentPosition == newer)
        // Mirror MapView's visiblePlace observation after the retained refresh completes.
        map.prepareCapture(fallbackName: CaptureFixture.place)
        #expect(map.capture === capture)
        #expect(map.capture?.draft == frozen)
        if cleanEditor { capture.endEditing() }
        await capture.save()
        #expect(capture.commit?.location.coordinate == original.coordinate)
        #expect(capture.commit?.location.notes == frozen.notes)
        map.deactivate()
    }

    /// AC-20/21/44: a pristine current-position capture includes newly resolved address metadata when saved.
    @Test func pristineCurrentPositionCaptureIncludesDelayedAddressEnrichment() async throws {
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        let position = try DevicePosition(coordinate: Coordinate(latitude: 10, longitude: 20),
            timestamp: CaptureFixture.date, horizontalAccuracyMetres: 5,
            authorization: MapPresentationLocationService.allowed)
        positions.immediateResult = .success(position)
        let geocoder = CaptureAddressGeocoder()
        let repository = CaptureRepository()
        let map = MapViewModel(deviceLocationService: positions, reverseGeocodingService: geocoder,
            locationRepository: repository, collectionRepository: UnavailableCollectionRepository())
        map.applyLibrarySnapshot(mapSnapshot(destination: UUID(), other: UUID()))
        #expect(await map.activate() == nil)
        await geocoder.waitUntilRequested()
        map.prepareCapture(fallbackName: CaptureFixture.place)
        #expect(map.capture?.candidate.address == nil)
        #expect(map.capture?.isDirty == false)
        await geocoder.resolve(address: CaptureFixture.enrichedAddress)
        await map.awaitPendingAddressEnrichment()
        #expect(map.currentAddress == CaptureFixture.enrichedAddress)
        // Mirror the visible-place change and synchronous preparation at Save.
        map.prepareCapture(fallbackName: CaptureFixture.place)
        let capture = try #require(map.capture)
        await capture.save()
        #expect(capture.commit?.location.coordinate == position.coordinate)
        #expect(capture.commit?.location.address == CaptureFixture.enrichedAddress)
        #expect(capture.commit?.location.placeIdentity == nil)
        map.deactivate()
    }

    /// AC-46/47: an out-of-scope receipt retains its committed coordinate and the calling collection scope.
    @Test(arguments: [false, true])
    func outOfScopeSaveReceiptKeepsFrozenSelectionAndScope(newerObservation: Bool) async throws {
        let repository = CaptureRepository()
        let scope = UUID()
        let other = UUID()
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: UnavailableCollectionRepository(),
            scopeCollectionID: scope)
        map.applyLibrarySnapshot(mapSnapshot(destination: scope, other: other))
        let place = try model(repository: repository).candidate
        map.selectSearchCandidate(place)
        map.prepareCapture(fallbackName: CaptureFixture.place)
        let capture = try #require(map.capture)
        capture.destinationCollectionID = other
        let camera = map.cameraPosition
        await capture.save()
        if newerObservation {
            map.applyLibrarySnapshot(mapSnapshot(destination: scope, other: other, revision: 3))
        }
        map.acceptCaptureCommit(capture)
        let committed = try #require(capture.commit)
        #expect(map.scopeCollectionID == scope)
        #expect(map.capture === capture)
        #expect(map.visiblePlace?.id == .savedLocation(committed.location.id))
        #expect(map.visiblePlace?.coordinate == committed.location.coordinate)
        #expect(map.selectedSavedLocation == nil)
        #expect(map.savedLocations.isEmpty)
        #expect(map.collectionCardPlaces.map(\.id) == [.savedLocation(committed.location.id)])
        #expect(map.selectedPageIndex == 0)
        map.selectCollectionCard(.savedLocation(committed.location.id))
        map.showDetails()
        #expect(map.capture === capture)
        #expect(map.selectedDetail?.id == .savedLocation(committed.location.id))
        #expect(map.cameraPosition.region?.center.latitude == camera.region?.center.latitude)
        #expect(map.cameraPosition.region?.center.longitude == camera.region?.center.longitude)
        map.applyLibrarySnapshot(mapSnapshot(destination: scope, other: other, revision: 2,
                                             locations: [committed.location]))
        #expect(map.savedLocations.isEmpty)
        #expect(map.visiblePlace?.coordinate == place.coordinate)
        let saved = committed.location
        let scoped = SavedLocation(id: UUID(), collectionID: scope, placeIdentity: nil, source: saved.source,
            name: saved.name, displayName: nil, address: nil, coordinate: saved.coordinate,
            category: nil, notes: nil, assets: [], isFavorite: false,
            createdAt: saved.createdAt, updatedAt: saved.updatedAt, revision: 1)
        map.applyLibrarySnapshot(mapSnapshot(destination: scope, other: other, revision: 3, locations: [scoped]))
        map.selectCollectionCard(.savedLocation(scoped.id))
        #expect(map.selectedSavedLocation?.id == scoped.id)
        #expect(map.collectionCardPlaces.map(\.id) == [.savedLocation(saved.id), .savedLocation(scoped.id)])
        map.selectCollectionCard(.savedLocation(saved.id))
        map.prepareCapture(fallbackName: CaptureFixture.place)
        #expect(map.displayedSavedLocation == saved)
        #expect(map.visiblePlace?.id == .savedLocation(saved.id))
        #expect(map.selectedSavedLocation == nil)
        #expect(map.capture == nil)
    }

    /// AC-46/47: deletion removes the receipt without reviving its unsaved candidate or changing a saved selection.
    @Test(arguments: [false, true], [false, true])
    func deletedOutOfScopeReceiptCannotReviveCandidate(savedCardSelected: Bool, newerPOIPending: Bool) async throws {
        let repository = CaptureRepository()
        let scope = UUID()
        let other = UUID()
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: UnavailableCollectionRepository(),
            scopeCollectionID: scope)
        map.applyLibrarySnapshot(mapSnapshot(destination: scope, other: other))
        map.selectSearchCandidate(try model(repository: repository).candidate)
        map.prepareCapture(fallbackName: CaptureFixture.place)
        let capture = try #require(map.capture)
        capture.destinationCollectionID = other
        await capture.save()
        map.acceptCaptureCommit(capture)
        let saved = try #require(capture.commit?.location)
        let scoped = SavedLocation(id: UUID(), collectionID: scope, placeIdentity: nil, source: saved.source,
            name: saved.name, displayName: nil, address: nil, coordinate: saved.coordinate,
            category: nil, notes: nil, assets: [], isFavorite: false,
            createdAt: saved.createdAt, updatedAt: saved.updatedAt, revision: 1)
        map.applyLibrarySnapshot(mapSnapshot(destination: scope, other: other, revision: 2, locations: [scoped]))
        if savedCardSelected { map.selectCollectionCard(.savedLocation(scoped.id)) }
        let release = CollectionObservationGate()
        let newer = try model(repository: repository).candidate
        var resolution: Task<Void, Never>?
        if newerPOIPending {
            #expect(await map.activate() == nil)
            resolution = map.beginMapFeatureSelection {
                await release.wait()
                return newer
            }
        }
        await map.refreshCommittedReceipt(expectedLibraryRevision: 2)
        map.prepareCapture(fallbackName: CaptureFixture.place)
        #expect(map.collectionTemporaryPlace == nil)
        #expect(map.collectionCardPlaces.map(\.id) == [.savedLocation(scoped.id)])
        #expect(map.selectedCandidate == nil)
        #expect(map.capture == nil)
        #expect(map.visiblePlace?.id == (savedCardSelected ? .savedLocation(scoped.id) : nil))
        if newerPOIPending {
            await release.open()
            await resolution?.value
            #expect(map.selectedCandidate == newer)
            #expect(map.collectionTemporaryPlace?.id == .searchCandidate(newer.id))
        }
        map.deactivate()
    }

    /// AC-24/56: opening Details on an already selected transient card preserves its camera and draft.
    @Test func selectedCollectionCardDetailsPreservesPannedCameraAndCapture() throws {
        let scope = UUID()
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: CaptureRepository(), collectionRepository: UnavailableCollectionRepository(),
            scopeCollectionID: scope)
        map.applyLibrarySnapshot(mapSnapshot(destination: scope, other: UUID()))
        map.selectSearchCandidate(try model(repository: CaptureRepository()).candidate)
        map.prepareCapture(fallbackName: CaptureFixture.place)
        let capture = try #require(map.capture)
        capture.notes = CaptureFixture.notes
        let place = try #require(map.visiblePlace)
        map.cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50, longitude: 60),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)))
        map.userDidChangeCamera()
        map.selectCollectionCard(place.id)
        map.showDetails()
        #expect(map.cameraPosition.region?.center.latitude == 50)
        #expect(map.cameraPosition.region?.center.longitude == 60)
        #expect(map.capture === capture)
        #expect(map.capture?.notes == CaptureFixture.notes)
        #expect(map.selectedDetail?.id == place.id)
    }

    /// AC-47/INV-09: a settled save from an abandoned selection cannot replace a newer candidate or its draft.
    @Test func staleSaveCompletionCannotReplaceNewerMapSelection() async throws {
        let repository = CaptureRepository(suspended: true)
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: UnavailableCollectionRepository())
        map.applyLibrarySnapshot(mapSnapshot(destination: UUID(), other: UUID()))
        let first = try model(repository: repository).candidate
        map.selectSearchCandidate(first)
        map.prepareCapture(fallbackName: CaptureFixture.place)
        let abandoned = try #require(map.capture)
        let saving = Task { await abandoned.save() }
        await repository.started.wait()
        let second = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: CaptureFixture.place, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 12, longitude: 22))
        map.selectSearchCandidate(second)
        map.prepareCapture(fallbackName: CaptureFixture.place)
        let current = try #require(map.capture)
        current.notes = CaptureFixture.notes
        let camera = map.cameraPosition
        await repository.release.open()
        await saving.value
        #expect(abandoned.commit != nil)
        map.acceptCaptureCommit(abandoned)
        #expect(map.capture === current)
        #expect(map.selectedCandidate == second)
        #expect(map.visiblePlace?.coordinate == second.coordinate)
        #expect(map.selectedSavedLocation == nil)
        #expect(current.notes == CaptureFixture.notes)
        #expect(map.cameraPosition.region?.center.latitude == camera.region?.center.latitude)
        #expect(map.cameraPosition.region?.center.longitude == camera.region?.center.longitude)
    }

    /// AC-31/47, INV-07: a precommit observation delivered after the receipt cannot remove its committed pin.
    @Test func delayedPrecommitSnapshotCannotEraseAcceptedSaveReceipt() async throws {
        let repository = CaptureRepository(commitRevision: 2)
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: UnavailableCollectionRepository())
        let destination = UUID()
        let other = UUID()
        let before = mapSnapshot(destination: destination, other: other, revision: 1)
        map.applyLibrarySnapshot(before)
        map.selectSearchCandidate(try model(repository: repository).candidate)
        map.prepareCapture(fallbackName: CaptureFixture.place)
        let capture = try #require(map.capture)
        await capture.save()
        let commit = try #require(capture.commit)
        map.acceptCaptureCommit(capture)
        #expect(map.selectedSavedLocation == commit.location)
        map.applyLibrarySnapshot(before)
        #expect(map.libraryRevision == commit.libraryRevision)
        #expect(map.savedLocations == [commit.location])
        #expect(map.selectedSavedLocation == commit.location)
        #expect(map.visiblePlace?.id == .savedLocation(commit.location.id))
    }

    /// AC-31/47, INV-05/07: a callback from R+1 cannot resurrect a record deleted at R+2 or overwrite its newer value.
    @Test(arguments: [false, true], [false, true])
    func delayedSaveCallbackUsesLatestObservationInsteadOfResurrectingOldData(deleted: Bool, scoped: Bool) async throws {
        let repository = CaptureRepository(commitRevision: 2)
        let destination = UUID()
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: UnavailableCollectionRepository(),
            scopeCollectionID: scoped ? destination : nil)
        let other = UUID()
        map.applyLibrarySnapshot(mapSnapshot(destination: destination, other: other, revision: 1))
        map.selectSearchCandidate(try model(repository: repository).candidate)
        map.prepareCapture(fallbackName: CaptureFixture.place)
        let capture = try #require(map.capture)
        await capture.save()
        let committed = try #require(capture.commit?.location)
        let latest = SavedLocation(id: committed.id, collectionID: committed.collectionID,
            placeIdentity: committed.placeIdentity, source: committed.source, name: committed.name,
            displayName: committed.displayName, address: committed.address, coordinate: committed.coordinate,
            category: committed.category, notes: CaptureFixture.notes, assets: committed.assets, isFavorite: true,
            createdAt: committed.createdAt, updatedAt: committed.updatedAt.addingTimeInterval(1), revision: 2)
        map.applyLibrarySnapshot(mapSnapshot(destination: destination, other: other, revision: 3,
                                             locations: deleted ? [] : [latest]))
        map.acceptCaptureCommit(capture)
        #expect(map.libraryRevision == 3)
        if scoped {
            #expect(map.collectionTemporaryPlace == nil)
            #expect(map.collectionCardPlaces.map(\.id) == (deleted ? [] : [.savedLocation(committed.id)]))
        }
        if deleted {
            #expect(map.savedLocations.isEmpty)
            #expect(map.selectedSavedLocation == nil)
            #expect(map.visiblePlace?.id != .savedLocation(committed.id))
        } else {
            #expect(map.savedLocations == [latest])
            #expect(map.selectedSavedLocation == latest)
            #expect(map.selectedSavedLocation?.isFavorite == true)
            #expect(map.selectedSavedLocation?.notes == CaptureFixture.notes)
        }
    }

    /// AC-15/45: warning acknowledgement follows the current visible destination; switching it clears stale warning.
    @Test func destinationChangeClearsWarningWithoutDiscardingOptionalDetails() async throws {
        let repository = CaptureRepository()
        let capture = try model(repository: repository)
        capture.notes = CaptureFixture.notes
        let originalID = capture.id
        let warning = DuplicateWarningToken(draftID: originalID,
            destinationCollectionID: capture.destinationCollectionID,
            matches: [DuplicateMatchRevision(locationID: UUID(), revision: 1)])
        await repository.fail(with: .possibleDuplicates(candidateIDs: warning.matches.map(\.locationID),
                                                        evaluationToken: warning))
        await capture.save()
        #expect(capture.saveError != nil)
        let changedDestination = UUID()
        capture.destinationCollectionID = changedDestination
        await capture.acknowledgeWarningAndSave()
        #expect(capture.saveError == nil)
        #expect(await repository.commands.count == 1)
        await repository.allowSuccess()
        await capture.save()
        #expect(capture.commit?.location.collectionID == changedDestination)
        #expect(capture.commit?.location.id == originalID)
        #expect(capture.commit?.location.notes == CaptureFixture.notes)
    }
}

private struct UnavailableCollectionRepository: CollectionRepository {
    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot {
        throw LocationWriteError.storageFailure
    }
    func snapshot() async throws -> CollectionListSnapshot { throw LocationWriteError.storageFailure }
    func collection(id: UUID) async throws -> CollectionSummary? { nil }
    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit { throw LocationWriteError.storageFailure }
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit { throw LocationWriteError.storageFailure }
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit { throw LocationWriteError.storageFailure }
}

private actor CaptureAddressGeocoder: ReverseGeocodingService {
    private var request: ReverseGeocodeRequest?
    private var pending: CheckedContinuation<ReverseGeocodedAddress, Never>?
    private var requested: CheckedContinuation<Void, Never>?
    func reverseGeocode(_ request: ReverseGeocodeRequest) async throws(PlaceServiceError) -> ReverseGeocodedAddress {
        self.request = request
        return await withCheckedContinuation { continuation in
            pending = continuation
            requested?.resume()
            requested = nil
        }
    }
    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func resolve(address: String) {
        guard let request, let pending else { return }
        self.pending = nil
        pending.resume(returning: ReverseGeocodedAddress(request: request, address: address))
    }
}
