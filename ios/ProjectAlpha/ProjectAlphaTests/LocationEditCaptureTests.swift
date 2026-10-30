//
//  LocationEditCaptureTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/10/26.
//

import Foundation
import MapKit
import SwiftUI
import Testing
@testable import ProjectAlpha

private enum EditCaptureFixture {
    static let name = "Saved museum"
    static let displayName = "Personal museum"
    static let notes = "Committed notes"
    static let editedNotes = "Draft notes"
    static let committedToken = "photos/edit-committed.jpg"
    static let stagedToken = "photos/edit-staged.jpg"
    static let date = Date(timeIntervalSince1970: 100)
    static let image = Data([1, 2, 3])
}

private actor EditCaptureRepository: LocationRepository {
    let original: SavedLocation
    private(set) var updates: [UpdateLocationCommand] = []
    private(set) var creates: [CreateLocationCommand] = []
    private var failure: LocationWriteError?

    init(original: SavedLocation, failure: LocationWriteError? = nil) {
        self.original = original
        self.failure = failure
    }
    func allowSuccess() { failure = nil }
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        LocationLibrarySnapshot(collections: [], locations: [original], libraryRevision: 1)
    }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func location(id: UUID) async throws -> SavedLocation? { id == original.id ? original : nil }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        creates.append(command)
        throw LocationWriteError.storageFailure
    }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageFailure
    }
    func updateLocation(_ command: UpdateLocationCommand) async throws -> LocationCommit {
        updates.append(command)
        if let failure { throw failure }
        let draft = command.draft
        return LocationCommit(location: SavedLocation(id: original.id,
            collectionID: draft.destinationCollectionID, placeIdentity: original.placeIdentity,
            source: original.source, name: original.name, displayName: draft.displayName,
            address: original.address, coordinate: original.coordinate, category: original.category,
            notes: draft.notes, assets: draft.assets, isFavorite: original.isFavorite,
            createdAt: original.createdAt, updatedAt: original.updatedAt,
            revision: original.revision + 1), libraryRevision: 2)
    }
}

private struct EditCaptureCollectionRepository: CollectionRepository {
    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot {
        throw LocationWriteError.storageFailure
    }
    func snapshot() async throws -> CollectionListSnapshot { throw LocationWriteError.storageFailure }
    func collection(id: UUID) async throws -> CollectionSummary? { nil }
    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        throw LocationWriteError.storageFailure
    }
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        throw LocationWriteError.storageFailure
    }
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit {
        throw LocationWriteError.storageFailure
    }
}

private actor EditCaptureMedia: LocationMediaService {
    let staged: LocalAssetReference
    private(set) var discarded: [LocalAssetReference] = []
    private(set) var preparedDraftIDs: [UUID] = []
    private(set) var cancelled: [UUID] = []
    private(set) var finished: [UUID] = []
    init() throws {
        staged = try LocalAssetReference(assetID: UUID(), relativeFileToken: EditCaptureFixture.stagedToken)
    }
    func preparePhoto(data: Data, draftID: UUID) async throws -> LocalAssetReference {
        preparedDraftIDs.append(draftID)
        return staged
    }
    func photoData(for asset: LocalAssetReference, thumbnail: Bool) async throws -> Data { EditCaptureFixture.image }
    func discardPhoto(_ asset: LocalAssetReference, draftID: UUID) async { discarded.append(asset) }
    func cancelDraft(id: UUID) async { cancelled.append(id) }
    func finishDraft(id: UUID) async { finished.append(id) }
}

/// AC-22/23/41/42/45, INV-07/08/09: saved edits retain original media and stable draft identity.
@MainActor
struct LocationEditCaptureTests {
    private func original() throws -> SavedLocation {
        SavedLocation(id: UUID(), collectionID: UUID(), placeIdentity: nil, source: .manualCoordinate,
            name: EditCaptureFixture.name, displayName: EditCaptureFixture.displayName, address: nil,
            coordinate: try Coordinate(latitude: 0, longitude: 0), category: nil,
            notes: EditCaptureFixture.notes, assets: [try LocalAssetReference(assetID: UUID(),
                relativeFileToken: EditCaptureFixture.committedToken)], isFavorite: true,
            createdAt: EditCaptureFixture.date, updatedAt: EditCaptureFixture.date, revision: 7)
    }
    private func model(_ original: SavedLocation, repository: EditCaptureRepository,
                       media: EditCaptureMedia) -> LocationCaptureModel {
        LocationCaptureModel(savedLocation: original, repository: repository,
            collectionRepository: EditCaptureCollectionRepository(), mediaService: media)
    }

    /// INV-07/08, AC-45: existing fields/photos are the clean baseline, not immediately dirty edits.
    @Test func savedEditorStartsCleanAndKeepsOriginalIdentity() throws {
        let saved = try original()
        let capture = model(saved, repository: EditCaptureRepository(original: saved), media: try EditCaptureMedia())
        #expect(capture.isEditingSavedLocation)
        #expect(!capture.isDirty)
        #expect(capture.id == saved.id)
        #expect(capture.createdAt == saved.createdAt)
        #expect(capture.assets == saved.assets)
        #expect(capture.displayName == saved.displayName)
        #expect(capture.notes == saved.notes)
        #expect(capture.candidate.coordinate == saved.coordinate)
        #expect(capture.destinationCollectionID == saved.collectionID)
    }

    /// AC-22/23, INV-07/08: repeat edits keep record identity but never reuse a retired media-staging session.
    @Test func repeatedSavedEditorsUseIndependentMediaDrafts() async throws {
        let saved = try original()
        let repository = EditCaptureRepository(original: saved)
        let media = try EditCaptureMedia()
        let firstSession = UUID()
        let secondSession = UUID()
        let first = LocationCaptureModel(savedLocation: saved, repository: repository,
            collectionRepository: EditCaptureCollectionRepository(), mediaService: media, mediaDraftID: firstSession)
        let second = LocationCaptureModel(savedLocation: saved, repository: repository,
            collectionRepository: EditCaptureCollectionRepository(), mediaService: media, mediaDraftID: secondSession)
        #expect(first.id == saved.id)
        #expect(second.id == saved.id)
        #expect(first.mediaDraftID == firstSession)
        #expect(second.mediaDraftID == secondSession)
        #expect(first.mediaDraftID != second.mediaDraftID)
        await first.importPhoto(data: EditCaptureFixture.image)
        await first.cancel()
        await second.importPhoto(data: EditCaptureFixture.image)
        #expect(await media.preparedDraftIDs == [firstSession, secondSession])
        #expect(await media.cancelled == [firstSession])
        #expect(second.assets.count == saved.assets.count + 1)
        #expect(!second.isCancelled)
    }

    /// AC-22/41, INV-06/08: removing an existing thumbnail edits references without deleting its file.
    @Test func removingCommittedPhotoAndDiscardingRestoresOriginalWithoutMediaDeletion() async throws {
        let saved = try original()
        let media = try EditCaptureMedia()
        let repository = EditCaptureRepository(original: saved)
        let capture = model(saved, repository: repository, media: media)
        await capture.removePhoto(saved.assets[0])
        #expect(capture.assets.isEmpty)
        #expect(capture.isDirty)
        #expect(await media.discarded.isEmpty)
        capture.notes = EditCaptureFixture.editedNotes
        capture.destinationCollectionID = UUID()
        await capture.importPhoto(data: EditCaptureFixture.image)
        let staged = media.staged
        await capture.discardDetails()
        #expect(capture.assets == saved.assets)
        #expect(capture.notes == saved.notes)
        #expect(capture.displayName == saved.displayName)
        #expect(capture.destinationCollectionID == saved.collectionID)
        #expect(!capture.isDirty)
        #expect(capture.id == saved.id)
        #expect(await media.discarded == [staged])
        #expect(await repository.updates.isEmpty)
        #expect(await repository.creates.isEmpty)
    }

    /// AC-23, INV-08: cancellation retires staging without sending committed files for removal or writing data.
    @Test func cancellingSavedEditOnlyCancelsDraftStaging() async throws {
        let saved = try original()
        let media = try EditCaptureMedia()
        let repository = EditCaptureRepository(original: saved)
        let capture = model(saved, repository: repository, media: media)
        await capture.importPhoto(data: EditCaptureFixture.image)
        await capture.cancel()
        await capture.save()
        #expect(capture.isCancelled)
        #expect(await media.cancelled == [capture.mediaDraftID])
        #expect(await media.discarded.allSatisfy { !saved.assets.contains($0) })
        #expect(await media.finished.isEmpty)
        #expect(await repository.updates.isEmpty)
        #expect(await repository.creates.isEmpty)
    }

    /// AC-22/42/45, INV-07/08: retry submits the same edited draft and original revision through update only.
    @Test func failedEditPreservesDraftAndRetryUsesRevisionCheckedUpdate() async throws {
        let saved = try original()
        let media = try EditCaptureMedia()
        let repository = EditCaptureRepository(original: saved, failure: .storageFailure)
        let capture = model(saved, repository: repository, media: media)
        capture.notes = EditCaptureFixture.editedNotes
        await capture.importPhoto(data: EditCaptureFixture.image)
        let edited = capture.draft
        await capture.save()
        #expect(capture.commit == nil)
        #expect(capture.saveError == .storageFailure)
        #expect(capture.draft == edited)
        #expect(await media.finished.isEmpty)
        await repository.allowSuccess()
        await capture.save()
        let updates = await repository.updates
        #expect(updates.map(\.draft) == [edited, edited])
        #expect(updates.map(\.expectedRevision) == [saved.revision, saved.revision])
        #expect(await repository.creates.isEmpty)
        #expect(capture.commit?.location.id == saved.id)
        #expect(capture.commit?.location.assets == edited.assets)
        #expect(capture.commit?.location.isFavorite == true)
        #expect(await media.finished == [capture.mediaDraftID])
        #expect(await media.preparedDraftIDs == [capture.mediaDraftID])
    }

    /// AC-42/55, INV-07/08: conflict retains user work; Reload drops only staged media and Reapply rechecks revision.
    @Test(arguments: [false, true])
    func conflictRetainsDraftUntilExplicitReloadOrReapply(reapply: Bool) async throws {
        let saved = try original()
        let latest = SavedLocation(id: saved.id, collectionID: UUID(), placeIdentity: saved.placeIdentity,
            source: saved.source, name: saved.name, displayName: saved.displayName, address: saved.address,
            coordinate: saved.coordinate, category: saved.category, notes: EditCaptureFixture.name,
            assets: saved.assets, isFavorite: false, createdAt: saved.createdAt,
            updatedAt: saved.updatedAt, revision: saved.revision + 1)
        let repository = EditCaptureRepository(original: saved, failure: .editConflict(latest: latest))
        let media = try EditCaptureMedia()
        let capture = model(saved, repository: repository, media: media)
        capture.notes = EditCaptureFixture.editedNotes
        await capture.importPhoto(data: EditCaptureFixture.image)
        let draft = capture.draft
        await capture.save()
        #expect(capture.saveError == .editConflict(latest: latest))
        #expect(capture.draft == draft)
        #expect(await media.discarded.isEmpty)
        if reapply {
            await repository.allowSuccess()
            await capture.reapplyConflict()
            let commands = await repository.updates
            #expect(commands.count == 2)
            #expect(commands.last?.expectedRevision == latest.revision)
            #expect(commands.last?.draft.notes == draft.notes)
            #expect(commands.last?.draft.assets == draft.assets)
            #expect(commands.last?.draft.destinationCollectionID == draft.destinationCollectionID)
            #expect(capture.commit != nil)
            #expect(await media.discarded.isEmpty)
        } else {
            await capture.reloadConflict()
            #expect(capture.notes == latest.notes)
            #expect(capture.destinationCollectionID == latest.collectionID)
            #expect(capture.assets == latest.assets)
            #expect(capture.expectedRevision == latest.revision)
            #expect(!capture.isDirty)
            #expect(await media.discarded == [media.staged])
            #expect(await repository.updates.count == 1)
        }
        #expect(capture.id == saved.id)
    }

    /// AC-31/45/58, INV-09: edit reuses one capture; applying personal edits never refocuses the map.
    @Test(arguments: [false, true], [false, true])
    func mapSavedEditRetainsCameraAndAppliesScopedMove(scoped: Bool, move: Bool) async throws {
        let saved = try original()
        let other = UUID()
        let repository = EditCaptureRepository(original: saved)
        let media = try EditCaptureMedia()
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: EditCaptureCollectionRepository(),
            scopeCollectionID: scoped ? saved.collectionID : nil, mediaService: media)
        let summaries = [saved.collectionID, other].map { id in
            CollectionSummary(collection: Collection(id: id, name: EditCaptureFixture.name,
                isDefault: id == saved.collectionID, createdAt: EditCaptureFixture.date,
                updatedAt: EditCaptureFixture.date, revision: 1), locationCount: id == saved.collectionID ? 1 : 0)
        }
        map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: summaries, locations: [saved], libraryRevision: 1))
        map.selectSavedLocation(saved.id)
        map.showDetails()
        let camera = try #require(map.cameraPosition.region)
        let focus = map.locationFocus
        #expect(map.prepareSavedLocationEdit())
        let capture = try #require(map.capture)
        capture.beginEditing()
        capture.notes = EditCaptureFixture.editedNotes
        if move { capture.destinationCollectionID = other }
        #expect(map.prepareSavedLocationEdit())
        #expect(map.capture === capture)
        #expect(capture.id == saved.id)
        #expect(capture.notes == EditCaptureFixture.editedNotes)
        #expect(map.isUpdatingDetail)
        await capture.save()
        #expect(capture.commit != nil)
        #expect(!map.isUpdatingDetail)
        map.acceptCaptureCommit(capture)
        #expect(map.capture == nil)
        #expect(map.locationFocus == focus)
        #expect(map.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(map.cameraPosition.region?.center.longitude == camera.center.longitude)
        #expect(map.cameraPosition.region?.span.latitudeDelta == camera.span.latitudeDelta)
        #expect(map.cameraPosition.region?.span.longitudeDelta == camera.span.longitudeDelta)
        if scoped && move {
            #expect(map.savedLocations.isEmpty)
            #expect(map.selectedSavedLocation == nil)
            #expect(map.selectedDetail == nil)
        } else {
            #expect(map.savedLocations.count == 1)
            #expect(map.selectedSavedLocation?.id == saved.id)
            #expect(map.selectedSavedLocation?.notes == EditCaptureFixture.editedNotes)
            #expect(map.selectedSavedLocation?.collectionID == (move ? other : saved.collectionID))
            #expect(map.selectedDetail?.id == .savedLocation(saved.id))
        }
    }

    private func mapSnapshot(_ saved: SavedLocation, revision: Int64) -> LocationLibrarySnapshot {
        let collection = Collection(id: saved.collectionID, name: EditCaptureFixture.name, isDefault: true,
            createdAt: EditCaptureFixture.date, updatedAt: EditCaptureFixture.date, revision: 1)
        return LocationLibrarySnapshot(collections: [CollectionSummary(collection: collection, locationCount: 1)],
            locations: [saved], libraryRevision: revision)
    }

    /// AC-42/45/55, INV-07/08: a closed clean editor reopens from the current projection with fresh media staging.
    @Test func reopeningClosedEditorUsesLatestSnapshotAndNewMediaSession() throws {
        let saved = try original()
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: EditCaptureRepository(original: saved),
            collectionRepository: EditCaptureCollectionRepository(), mediaService: try EditCaptureMedia())
        map.applyLibrarySnapshot(mapSnapshot(saved, revision: 1))
        map.selectSavedLocation(saved.id)
        #expect(map.prepareSavedLocationEdit())
        let closed = try #require(map.capture)
        closed.beginEditing()
        #expect(!closed.isDirty)
        closed.endAllEditing()
        #expect(!closed.isEditing)
        let latest = SavedLocation(id: saved.id, collectionID: saved.collectionID,
            placeIdentity: saved.placeIdentity, source: saved.source, name: saved.name,
            displayName: EditCaptureFixture.editedNotes, address: saved.address, coordinate: saved.coordinate,
            category: saved.category, notes: EditCaptureFixture.editedNotes, assets: saved.assets,
            isFavorite: false, createdAt: saved.createdAt, updatedAt: saved.updatedAt,
            revision: saved.revision + 1)
        map.applyLibrarySnapshot(mapSnapshot(latest, revision: 2))
        #expect(map.prepareSavedLocationEdit())
        let reopened = try #require(map.capture)
        #expect(reopened !== closed)
        #expect(reopened.id == saved.id)
        #expect(reopened.notes == latest.notes)
        #expect(reopened.displayName == latest.displayName)
        #expect(reopened.expectedRevision == latest.revision)
        #expect(reopened.mediaDraftID != closed.mediaDraftID)
        #expect(!reopened.isDirty)
    }

    /// AC-24/45/55, D-03/17: read-only detail follows the current record and closes when it leaves scope.
    @Test(arguments: [false, true])
    func readOnlyDetailDisappearsWhenSavedRecordLeavesScope(movedOut: Bool) async throws {
        let saved = try original()
        let repository = EditCaptureRepository(original: saved)
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: EditCaptureCollectionRepository(),
            scopeCollectionID: saved.collectionID)
        map.applyLibrarySnapshot(mapSnapshot(saved, revision: 1))
        map.selectSavedLocation(saved.id)
        map.showDetails()
        #expect(map.presentedDetail?.id == .savedLocation(saved.id))
        #expect(map.capture == nil)

        let moved = SavedLocation(id: saved.id, collectionID: UUID(), placeIdentity: saved.placeIdentity,
            source: saved.source, name: saved.name, displayName: saved.displayName, address: saved.address,
            coordinate: saved.coordinate, category: saved.category, notes: saved.notes, assets: saved.assets,
            isFavorite: saved.isFavorite, createdAt: saved.createdAt, updatedAt: saved.updatedAt,
            revision: saved.revision + 1)
        map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: mapSnapshot(saved, revision: 2).collections,
            locations: movedOut ? [moved] : [], libraryRevision: 2))

        #expect(map.selectedSavedLocation == nil)
        #expect(map.selectedDetail == nil)
        #expect(map.presentedDetail == nil)
        #expect(map.capture == nil)
        #expect(await repository.creates.isEmpty)
        #expect(await repository.updates.isEmpty)
    }

    /// AC-24/44/45/47/55, D-03/13/17, INV-08/09: snapshot removal must not dismiss in-place edits or lose media.
    /// Sheet identity/animation and adaptive presentation still require device/UI evidence.
    @Test(arguments: [false, true])
    func activeDetailEditSurvivesRecordLeavingScopeUntilExplicitDiscard(movedOut: Bool) async throws {
        let saved = try original()
        let moved = SavedLocation(id: saved.id, collectionID: UUID(), placeIdentity: saved.placeIdentity,
            source: saved.source, name: saved.name, displayName: saved.displayName, address: saved.address,
            coordinate: saved.coordinate, category: saved.category, notes: saved.notes, assets: saved.assets,
            isFavorite: saved.isFavorite, createdAt: saved.createdAt, updatedAt: saved.updatedAt,
            revision: saved.revision + 1)
        let failure: LocationWriteError = movedOut ? .editConflict(latest: moved) : .locationMissing(saved.id)
        let repository = EditCaptureRepository(original: saved, failure: failure)
        let media = try EditCaptureMedia()
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: EditCaptureCollectionRepository(),
            scopeCollectionID: saved.collectionID, mediaService: media)
        map.applyLibrarySnapshot(mapSnapshot(saved, revision: 1))
        map.selectSavedLocation(saved.id)
        map.showDetails()
        let detail = try #require(map.presentedDetail)
        #expect(map.prepareSavedLocationEdit())
        let capture = try #require(map.capture)
        capture.beginEditing()
        capture.notes = EditCaptureFixture.editedNotes
        await capture.importPhoto(data: EditCaptureFixture.image)
        let draft = capture.draft
        let mediaID = capture.mediaDraftID
        let camera = try #require(map.cameraPosition.region)

        map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: mapSnapshot(saved, revision: 2).collections,
            locations: movedOut ? [moved] : [], libraryRevision: 2))

        #expect(map.selectedSavedLocation == nil)
        #expect(map.selectedDetail == nil)
        #expect(map.presentedDetail?.id == detail.id)
        #expect(map.presentedDetail?.coordinate == saved.coordinate)
        #expect(map.capture === capture)
        #expect(capture.id == saved.id)
        #expect(capture.expectedRevision == saved.revision)
        #expect(capture.draft == draft)
        #expect(capture.mediaDraftID == mediaID)
        #expect(capture.isEditing && capture.isDirty && !capture.isCancelled)
        #expect(map.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(map.cameraPosition.region?.center.longitude == camera.center.longitude)
        #expect(map.cameraPosition.region?.span.latitudeDelta == camera.span.latitudeDelta)
        #expect(map.cameraPosition.region?.span.longitudeDelta == camera.span.longitudeDelta)
        #expect(await media.preparedDraftIDs == [mediaID])
        #expect(await media.cancelled.isEmpty)
        #expect(await media.discarded.isEmpty)
        #expect(await repository.creates.isEmpty)
        #expect(await repository.updates.isEmpty)

        await capture.save()
        #expect(capture.saveError == failure)
        #expect(capture.commit == nil)
        #expect(capture.draft == draft)
        #expect(capture.mediaDraftID == mediaID)
        #expect(map.presentedDetail?.id == detail.id)
        #expect(await repository.updates.map(\.expectedRevision) == [saved.revision])
        #expect(await repository.updates.map(\.draft) == [draft])
        #expect(await media.finished.isEmpty)
        #expect(await media.cancelled.isEmpty)

        await capture.cancel()
        capture.endAllEditing()
        #expect(map.presentedDetail == nil)
        #expect(capture.isCancelled)
        #expect(await media.cancelled == [mediaID])
        #expect(await media.discarded.allSatisfy { !saved.assets.contains($0) })
        #expect(await repository.creates.isEmpty)
        #expect(await repository.updates.count == 1)
    }

    /// AC-24/44/45/47, D-03/17, INV-08/09: clean Add/Edit mode survives scene suspension with one draft owner.
    /// Re-presented SwiftUI mode and actual tab/sheet transitions require UI evidence.
    @Test(arguments: [false, true], [false, true])
    func detailUpdateModeSurvivesDeactivationUntilDiscardOrCancel(savedEdit: Bool, cancel: Bool) async throws {
        let saved = try original()
        let repository = EditCaptureRepository(original: saved)
        let media = try EditCaptureMedia()
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: EditCaptureCollectionRepository(), mediaService: media)
        map.applyLibrarySnapshot(mapSnapshot(saved, revision: 1))
        if savedEdit {
            map.selectSavedLocation(saved.id)
        } else {
            let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
                name: EditCaptureFixture.name, address: nil, category: nil,
                coordinate: try Coordinate(latitude: 10, longitude: 20))
            map.selectSearchCandidate(candidate)
        }
        map.showDetails()
        #expect(!map.isUpdatingDetail)
        if savedEdit { #expect(map.prepareSavedLocationEdit()) }
        else { map.prepareCapture(fallbackName: EditCaptureFixture.name) }
        let capture = try #require(map.capture)
        #expect(!capture.isDirty)
        #expect(!map.isUpdatingDetail)
        capture.beginEditing()
        #expect(map.isUpdatingDetail)
        let cleanDraft = capture.draft
        let mediaID = capture.mediaDraftID
        let detailID = try #require(map.presentedDetail).id

        map.deactivate()
        #expect(map.isUpdatingDetail)
        #expect(map.capture === capture)
        #expect(capture.draft == cleanDraft)
        #expect(capture.mediaDraftID == mediaID)
        #expect(map.presentedDetail?.id == detailID)

        await capture.importPhoto(data: EditCaptureFixture.image)
        let editedDraft = capture.draft
        map.deactivate()
        #expect(map.isUpdatingDetail)
        #expect(map.capture === capture)
        #expect(capture.draft == editedDraft)
        #expect(capture.mediaDraftID == mediaID)
        #expect(await media.preparedDraftIDs == [mediaID])
        #expect(await media.cancelled.isEmpty)
        if cancel { await capture.cancel() }
        else { await capture.discardDetails() }
        #expect(!map.isUpdatingDetail)
        #expect(await repository.creates.isEmpty)
        #expect(await repository.updates.isEmpty)
    }

    /// AC-24/45/55, D-03/13: in-place Edit resolves current saved revision without a create or update.
    @Test func readOnlyDetailPreparesCurrentSavedRevisionWithoutWriting() async throws {
        let saved = try original()
        let repository = EditCaptureRepository(original: saved)
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: EditCaptureCollectionRepository(),
            mediaService: try EditCaptureMedia())
        map.applyLibrarySnapshot(mapSnapshot(saved, revision: 1))
        map.selectSavedLocation(saved.id)
        map.showDetails()
        let detailID = try #require(map.presentedDetail).id
        let latest = SavedLocation(id: saved.id, collectionID: saved.collectionID,
            placeIdentity: saved.placeIdentity, source: saved.source, name: saved.name,
            displayName: saved.displayName, address: saved.address, coordinate: saved.coordinate,
            category: saved.category, notes: EditCaptureFixture.editedNotes, assets: saved.assets,
            isFavorite: saved.isFavorite, createdAt: saved.createdAt, updatedAt: saved.updatedAt,
            revision: saved.revision + 1)
        map.applyLibrarySnapshot(mapSnapshot(latest, revision: 2))

        #expect(map.prepareSavedLocationEdit())
        let capture = try #require(map.capture)
        capture.beginEditing()
        #expect(map.presentedDetail?.id == detailID)
        #expect(capture.id == latest.id)
        #expect(capture.expectedRevision == latest.revision)
        #expect(capture.notes == latest.notes)
        #expect(capture.assets == latest.assets)
        #expect(capture.candidate.coordinate == latest.coordinate)
        #expect(capture.destinationCollectionID == latest.collectionID)
        #expect(!capture.isDirty)
        #expect(await repository.creates.isEmpty)
        #expect(await repository.updates.isEmpty)
    }

    /// AC-30/45/58, INV-07/09: a closed edit cannot capture a removed/moved-out record on a later Add.
    @Test(arguments: [false, true])
    func closedSavedEditorDoesNotBlockCurrentPositionCaptureAfterRecordLeavesScope(movedOut: Bool) async throws {
        let saved = try original()
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        let position = try DevicePosition(coordinate: Coordinate(latitude: 10, longitude: 20),
            timestamp: EditCaptureFixture.date, horizontalAccuracyMetres: 5,
            authorization: MapPresentationLocationService.allowed)
        positions.immediateResult = .success(position)
        let map = MapViewModel(deviceLocationService: positions, positionClock: { EditCaptureFixture.date },
            locationRepository: EditCaptureRepository(original: saved),
            collectionRepository: EditCaptureCollectionRepository(), scopeCollectionID: saved.collectionID)
        map.applyLibrarySnapshot(mapSnapshot(saved, revision: 1))
        #expect(await map.activate() == nil)
        #expect(await map.recenter() == nil)
        map.selectSavedLocation(saved.id)
        #expect(map.prepareSavedLocationEdit())
        let closed = try #require(map.capture)
        closed.beginEditing()
        closed.endAllEditing()
        #expect(!closed.isEditing && !closed.isDirty)
        let originalSnapshot = mapSnapshot(saved, revision: 2)
        let moved = SavedLocation(id: saved.id, collectionID: UUID(), placeIdentity: saved.placeIdentity,
            source: saved.source, name: saved.name, displayName: saved.displayName, address: saved.address,
            coordinate: saved.coordinate, category: saved.category, notes: saved.notes, assets: saved.assets,
            isFavorite: saved.isFavorite, createdAt: saved.createdAt, updatedAt: saved.updatedAt,
            revision: saved.revision + 1)
        map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: originalSnapshot.collections,
            locations: movedOut ? [moved] : [], libraryRevision: 2))
        #expect(map.selectedSavedLocation == nil)
        #expect(map.visiblePlace?.id == .currentPosition)
        map.prepareCapture(fallbackName: EditCaptureFixture.name)
        let current = try #require(map.capture)
        #expect(current !== closed)
        #expect(!current.isEditingSavedLocation)
        #expect(current.id != saved.id)
        #expect(current.expectedRevision == nil)
        #expect(current.candidate.coordinate == position.coordinate)
        #expect(current.destinationCollectionID == saved.collectionID)
        map.deactivate()
    }

    /// AC-12/41/45, INV-03/07: an already-saved candidate edits that saved UUID instead of starting another create.
    @Test(arguments: [false, true], [false, true])
    func matchingCandidateOpensSavedRecordForEdit(scoped: Bool, moveOut: Bool) async throws {
        let saved = try original()
        let repository = EditCaptureRepository(original: saved)
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: EditCaptureCollectionRepository(),
            scopeCollectionID: scoped ? saved.collectionID : nil)
        map.applyLibrarySnapshot(mapSnapshot(saved, revision: 1))
        let candidate = PlaceCandidate(id: UUID(), source: saved.source, placeIdentity: saved.placeIdentity,
            name: saved.name, address: saved.address, category: saved.category, coordinate: saved.coordinate)
        map.selectSearchCandidate(candidate)
        map.prepareCapture(fallbackName: EditCaptureFixture.name)
        #expect(map.selectedSavedLocation == nil)
        #expect(map.existingSavedLocationID == saved.id)
        #expect(map.displayedSavedLocation == saved)
        #expect(map.prepareSavedLocationEdit())
        let editing = try #require(map.capture)
        #expect(editing.isEditingSavedLocation)
        #expect(editing.id == saved.id)
        #expect(editing.expectedRevision == saved.revision)
        editing.notes = EditCaptureFixture.editedNotes
        let destination = UUID()
        if moveOut { editing.destinationCollectionID = destination }
        let camera = try #require(map.cameraPosition.region)
        let focus = map.locationFocus
        await editing.save()
        #expect(await repository.updates.first?.draft.id == saved.id)
        #expect(await repository.creates.isEmpty)
        map.acceptCaptureCommit(editing)
        #expect(map.selectedCandidate == nil)
        #expect(map.selectedCandidateSource == nil)
        #expect(map.existingSavedLocationID == nil)
        #expect(map.collectionTemporaryPlace == nil)
        #expect(map.locationFocus == focus)
        #expect(map.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(map.cameraPosition.region?.center.longitude == camera.center.longitude)
        #expect(map.cameraPosition.region?.span.latitudeDelta == camera.span.latitudeDelta)
        #expect(map.cameraPosition.region?.span.longitudeDelta == camera.span.longitudeDelta)
        if scoped && moveOut {
            #expect(map.savedLocations.isEmpty)
            #expect(map.selectedSavedLocation == nil)
            #expect(map.visiblePlace == nil)
            #expect(map.mapSelection == nil)
            #expect(map.collectionCardPlaces.isEmpty)
        } else {
            #expect(map.displayedSavedLocation?.id == saved.id)
            #expect(map.visiblePlace?.id == .savedLocation(saved.id))
            #expect(map.selectedSavedLocation?.notes == EditCaptureFixture.editedNotes)
            #expect(map.selectedSavedLocation?.collectionID == (moveOut ? destination : saved.collectionID))
        }
    }

    /// AC-41/45/58, INV-09: releasing a child presentation owner keeps parent ownership and ordered assets.
    /// Actual viewer-sheet dismissal and confirmation-alert behavior require UI evidence.
    @Test func childPresentationReleaseRetainsDirtyEditorAndPhotoOrder() async throws {
        let saved = try original()
        let media = try EditCaptureMedia()
        let capture = model(saved, repository: EditCaptureRepository(original: saved), media: media)
        let parent = UUID()
        let child = UUID()
        capture.beginEditing(ownerID: parent)
        await capture.importPhoto(data: EditCaptureFixture.image)
        let draft = capture.draft
        for _ in 0..<3 {
            capture.beginEditing(ownerID: child)
            capture.endEditing(ownerID: child)
            #expect(capture.isEditing)
            #expect(capture.draft == draft)
            #expect(capture.assets.first == saved.assets.first)
        }
        #expect(await media.discarded.isEmpty)
        #expect(await media.cancelled.isEmpty)
    }
}
