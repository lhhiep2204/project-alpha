//
//  LocationDetailsPresentationTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 25/10/26.
//

import Foundation
import MapKit
import SwiftUI
import Testing
@testable import ProjectAlpha

enum DetailPresentationFixture {
    static let name = "Museum"
    static let originalNotes = "Committed notes"
    static let editedNotes = "Updated notes"
    static let displayName = "Personal museum"
    static let photoToken = "photos/detail-staged.jpg"
    static let image = Data([1, 2, 3])
    static let date = Date(timeIntervalSince1970: 100)

    static func saved(revision: Int64 = 7) throws -> SavedLocation {
        SavedLocation(id: UUID(), collectionID: UUID(), placeIdentity: nil, source: .manualCoordinate,
            name: name, displayName: nil, address: nil, coordinate: try Coordinate(latitude: 10, longitude: 20),
            category: nil, notes: originalNotes, assets: [], isFavorite: false,
            createdAt: date, updatedAt: date, revision: revision)
    }

    static func replacing(_ original: SavedLocation, notes: String, revision: Int64) -> SavedLocation {
        SavedLocation(id: original.id, collectionID: original.collectionID, placeIdentity: original.placeIdentity,
            source: original.source, name: original.name, displayName: original.displayName,
            address: original.address, coordinate: original.coordinate, category: original.category,
            notes: notes, assets: original.assets, isFavorite: original.isFavorite,
            createdAt: original.createdAt, updatedAt: original.updatedAt, revision: revision)
    }
}

actor DetailPresentationRepository: LocationRepository {
    private(set) var creates: [CreateLocationCommand] = []
    private(set) var updates: [UpdateLocationCommand] = []
    private var failure: LocationWriteError?

    init(failure: LocationWriteError? = nil) { self.failure = failure }
    func allowSuccess() { failure = nil }
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        LocationLibrarySnapshot(collections: [], locations: [], libraryRevision: 0)
    }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func location(id: UUID) async throws -> SavedLocation? { nil }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        creates.append(command)
        return try commit(command.draft, revision: 1)
    }
    func updateLocation(_ command: UpdateLocationCommand) async throws -> LocationCommit {
        updates.append(command)
        return try commit(command.draft, revision: command.expectedRevision + 1)
    }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageFailure
    }
    private func commit(_ draft: LocationDraft, revision: Int64) throws -> LocationCommit {
        if let failure { throw failure }
        let candidate = draft.candidate
        return LocationCommit(location: SavedLocation(id: draft.id, collectionID: draft.destinationCollectionID,
            placeIdentity: candidate.placeIdentity, source: candidate.source, name: candidate.name,
            displayName: draft.displayName, address: candidate.address, coordinate: candidate.coordinate,
            category: candidate.category, notes: draft.notes, assets: draft.assets, isFavorite: false,
            createdAt: draft.createdAt, updatedAt: DetailPresentationFixture.date, revision: revision),
            libraryRevision: revision)
    }
}

struct DetailPresentationCollections: CollectionRepository {
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

private actor DetailPresentationMedia: LocationMediaService {
    let asset: LocalAssetReference
    private let holdsDiscard: Bool
    private var discardEntered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var discardRelease: CheckedContinuation<Void, Never>?
    private(set) var discarded: [LocalAssetReference] = []
    private(set) var finished: [UUID] = []
    init(holdsDiscard: Bool = false) throws {
        self.holdsDiscard = holdsDiscard
        asset = try LocalAssetReference(assetID: UUID(), relativeFileToken: DetailPresentationFixture.photoToken)
    }
    func preparePhoto(data: Data, draftID: UUID) async throws -> LocalAssetReference { asset }
    func photoData(for asset: LocalAssetReference, thumbnail: Bool) async throws -> Data {
        DetailPresentationFixture.image
    }
    func discardPhoto(_ asset: LocalAssetReference, draftID: UUID) async {
        discarded.append(asset)
        if holdsDiscard {
            await withCheckedContinuation { continuation in
                discardRelease = continuation
                discardEntered = true
                entryWaiter?.resume()
                entryWaiter = nil
            }
        }
    }
    func waitForDiscard() async {
        if discardEntered { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func releaseDiscard() {
        discardRelease?.resume()
        discardRelease = nil
    }
    func cancelDraft(id: UUID) async {}
    func finishDraft(id: UUID) async { finished.append(id) }
}

/// AC-24/44/45/47/55, D-03/D-13, INV-07/08/09: one read-origin owner changes mode without dismissal.
/// Return values are dismissal requests; actual native-sheet continuity remains a UI evidence gate.
@MainActor
struct LocationDetailsPresentationTests {
    private func capture(saved: SavedLocation?, repository: DetailPresentationRepository,
                         media: DetailPresentationMedia? = nil) throws -> LocationCaptureModel {
        if let saved {
            return LocationCaptureModel(savedLocation: saved, repository: repository,
                collectionRepository: DetailPresentationCollections(), mediaService: media)
        }
        let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: DetailPresentationFixture.name, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 10, longitude: 20))
        return LocationCaptureModel(candidate: candidate, destinationCollectionID: UUID(),
            repository: repository, collectionRepository: DetailPresentationCollections(), mediaService: media,
            createdAt: DetailPresentationFixture.date)
    }

    /// AC-44/45: even clean Add/Edit Cancel confirms; Keep Editing retains the exact draft and owner.
    @Test(arguments: [false, true], [false, true])
    func readOriginCancelAlwaysConfirmsAndKeepEditingRetainsDraft(saved: Bool, dirty: Bool) async throws {
        let repository = DetailPresentationRepository()
        let original = saved ? try DetailPresentationFixture.saved() : nil
        let model = try capture(saved: original, repository: repository)
        let presentation = LocationDetailsPresentation(mode: .read, returnsToRead: true)
        presentation.beginUpdate(model)
        if dirty { model.notes = DetailPresentationFixture.editedNotes }
        let draft = model.draft
        #expect(!presentation.requestClose())
        #expect(presentation.showDiscard)
        #expect(presentation.mode == .update)
        presentation.showDiscard = false
        #expect(presentation.model === model)
        #expect(model.draft == draft)
        #expect(model.isEditing)
        #expect(await repository.creates.isEmpty)
        #expect(await repository.updates.isEmpty)
    }

    /// AC-24/44/45, INV-08: Discard returns read without writes, restores original facts and cleans staged photos.
    @Test(arguments: [false, true], [false, true])
    func readOriginDiscardRestoresReadWithoutDismissal(saved: Bool, dirty: Bool) async throws {
        let repository = DetailPresentationRepository()
        let media = try DetailPresentationMedia()
        let original = saved ? try DetailPresentationFixture.saved() : nil
        let model = try capture(saved: original, repository: repository, media: media)
        let candidate = model.candidate
        let presentation = LocationDetailsPresentation(mode: .read, returnsToRead: true)
        presentation.beginUpdate(model)
        if dirty {
            model.notes = DetailPresentationFixture.editedNotes
            model.displayName = DetailPresentationFixture.displayName
            await model.importPhoto(data: DetailPresentationFixture.image)
        }
        #expect(!presentation.requestClose())
        #expect(await presentation.discardUpdate() == false)
        #expect(presentation.mode == .read)
        #expect(!presentation.showDiscard)
        #expect(presentation.model === model)
        #expect(model.candidate == candidate)
        #expect(!model.isDirty)
        #expect(!model.isEditing)
        #expect(!model.isCancelled)
        #expect(model.notes == (original?.notes ?? String()))
        #expect(model.assets == (original?.assets ?? []))
        #expect(presentation.savedLocation(fallback: original) == original)
        #expect(await media.discarded.count == (dirty ? 1 : 0))
        #expect(await repository.creates.isEmpty)
        #expect(await repository.updates.isEmpty)
        #expect(presentation.requestClose())
    }

    /// AC-44/47, INV-05/07: only explicit Save writes, then read immediately exposes committed facts and UUID.
    @Test(arguments: [false, true])
    func successfulSaveReturnsReadAndCommittedFactsBeforeObservation(saved: Bool) async throws {
        let repository = DetailPresentationRepository()
        let original = saved ? try DetailPresentationFixture.saved() : nil
        let model = try capture(saved: original, repository: repository)
        let presentation = LocationDetailsPresentation(mode: .read, returnsToRead: true)
        presentation.beginUpdate(model)
        model.notes = DetailPresentationFixture.editedNotes
        #expect(!presentation.completeSave())
        #expect(presentation.mode == .update)
        #expect(await repository.creates.isEmpty)
        #expect(await repository.updates.isEmpty)
        await model.save()
        let committed = try #require(model.commit?.location)
        #expect(!presentation.completeSave())
        #expect(presentation.mode == .read)
        #expect(!model.isEditing)
        #expect(presentation.savedLocation(fallback: original) == committed)
        #expect(presentation.savedLocation(fallback: nil)?.id == model.id)
        #expect(committed.notes == DetailPresentationFixture.editedNotes)
        #expect(committed.revision == (original?.revision ?? 0) + 1)
        await model.save()
        #expect(await repository.creates.count == (saved ? 0 : 1))
        #expect(await repository.updates.count == (saved ? 1 : 0))
    }

    /// AC-47/55, INV-07: a newer observed record supersedes the local receipt and reopens at its current revision.
    @Test func freshEditUsesNewerObservedRevisionAndIndependentMediaDraft() async throws {
        let repository = DetailPresentationRepository()
        let original = try DetailPresentationFixture.saved()
        let first = try capture(saved: original, repository: repository)
        let presentation = LocationDetailsPresentation(mode: .read, returnsToRead: true)
        presentation.beginUpdate(first)
        first.notes = DetailPresentationFixture.editedNotes
        await first.save()
        #expect(!presentation.completeSave())
        let committed = try #require(first.commit?.location)
        let latest = DetailPresentationFixture.replacing(committed,
            notes: DetailPresentationFixture.originalNotes, revision: committed.revision + 1)
        #expect(presentation.savedLocation(fallback: latest) == latest)
        let second = try capture(saved: latest, repository: repository)
        presentation.beginUpdate(second)
        #expect(presentation.model === second)
        #expect(second !== first)
        #expect(second.id == original.id)
        #expect(second.expectedRevision == latest.revision)
        #expect(second.notes == latest.notes)
        #expect(second.mediaDraftID != first.mediaDraftID)
        #expect(!second.isDirty)
    }

    /// AC-45/55, INV-08: failure retains update, fields, photo order and stable draft through retry.
    @Test(arguments: [false, true])
    func failedSaveStaysUpdateAndRetriesSameDraft(saved: Bool) async throws {
        let repository = DetailPresentationRepository(failure: .storageFailure)
        let media = try DetailPresentationMedia()
        let original = saved ? try DetailPresentationFixture.saved() : nil
        let model = try capture(saved: original, repository: repository, media: media)
        let presentation = LocationDetailsPresentation(mode: .read, returnsToRead: true)
        presentation.beginUpdate(model)
        model.notes = DetailPresentationFixture.editedNotes
        await model.importPhoto(data: DetailPresentationFixture.image)
        let draft = model.draft
        let mediaDraftID = model.mediaDraftID
        await model.save()
        #expect(model.saveError == .storageFailure)
        #expect(!presentation.completeSave())
        #expect(presentation.mode == .update)
        #expect(presentation.model === model)
        #expect(model.draft == draft)
        #expect(model.mediaDraftID == mediaDraftID)
        #expect(model.isEditing)
        #expect(await media.discarded.isEmpty)
        #expect(await media.finished.isEmpty)
        await repository.allowSuccess()
        await model.save()
        #expect(!presentation.completeSave())
        #expect(presentation.mode == .read)
        #expect(model.commit?.location.assets == draft.assets)
        #expect(await media.finished == [mediaDraftID])
    }

    /// AC-44/45: a second Add after Discard uses a clean draft retaining the original unsaved selection.
    @Test func repeatedAddAfterDiscardAcceptsFreshCleanModel() async throws {
        let repository = DetailPresentationRepository()
        let first = try capture(saved: nil, repository: repository)
        let presentation = LocationDetailsPresentation(mode: .read, returnsToRead: true)
        presentation.beginUpdate(first)
        first.notes = DetailPresentationFixture.editedNotes
        #expect(await presentation.discardUpdate() == false)
        let second = LocationCaptureModel(candidate: first.candidate,
            destinationCollectionID: first.destinationCollectionID, repository: repository,
            collectionRepository: DetailPresentationCollections(), id: first.id, createdAt: first.createdAt)
        presentation.beginUpdate(second)
        #expect(presentation.model === second)
        #expect(second.candidate == first.candidate)
        #expect(second.id == first.id)
        #expect(!second.isDirty)
        #expect(second.commit == nil)
        #expect(await repository.creates.isEmpty)
    }

    /// AC-44/45: direct card Add/Edit keeps standalone clean dismissal and dirty confirmation behavior.
    @Test(arguments: [false, true])
    func standaloneCancellationKeepsExistingDismissalPolicy(dirty: Bool) async throws {
        let repository = DetailPresentationRepository()
        let model = try capture(saved: nil, repository: repository)
        let presentation = LocationDetailsPresentation(model: model, mode: .update, returnsToRead: false)
        presentation.beginEditing()
        if dirty { model.notes = DetailPresentationFixture.editedNotes }
        #expect(presentation.requestClose() == !dirty)
        #expect(presentation.showDiscard == dirty)
        if dirty { #expect(await presentation.discardUpdate()) }
        #expect(!model.isEditing)
        #expect(await repository.creates.isEmpty)
    }

    /// AC-24/44/47, D-03/D-13, INV-09: accepting a create must retain detail before returning to read.
    /// Covers Global Map, in-scope Collection Map, out-of-scope receipt and newer observed revisions.
    @Test(arguments: [(scoped: false, moveOut: false), (scoped: false, moveOut: true),
                      (scoped: true, moveOut: false), (scoped: true, moveOut: true)], [false, true])
    func mapAcceptsCreateWithoutClosingDetailOrRefocusing(configuration: (scoped: Bool, moveOut: Bool),
                                                        newerObservation: Bool) async throws {
        let scoped = configuration.scoped
        let moveOut = configuration.moveOut
        let repository = DetailPresentationRepository()
        let scopeID = UUID()
        let collection = Collection(id: scopeID, name: DetailPresentationFixture.name, isDefault: true,
            createdAt: DetailPresentationFixture.date, updatedAt: DetailPresentationFixture.date, revision: 1)
        let summaries = [CollectionSummary(collection: collection, locationCount: 0)]
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            locationRepository: repository, collectionRepository: DetailPresentationCollections(),
            scopeCollectionID: scoped ? scopeID : nil)
        map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: summaries, locations: [], libraryRevision: 0))
        let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: DetailPresentationFixture.name, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 10, longitude: 20))
        map.selectSearchCandidate(candidate)
        map.showDetails()
        #expect(map.selectedDetail != nil)
        map.prepareCapture(fallbackName: DetailPresentationFixture.name)
        let model = try #require(map.capture)
        let presentation = LocationDetailsPresentation(mode: .read, returnsToRead: true)
        presentation.beginUpdate(model)
        model.notes = DetailPresentationFixture.editedNotes
        if moveOut { model.destinationCollectionID = UUID() }
        let camera = try #require(map.cameraPosition.region)
        let focus = map.locationFocus
        await model.save()
        let committed = try #require(model.commit)
        let latest = DetailPresentationFixture.replacing(committed.location,
            notes: DetailPresentationFixture.originalNotes, revision: committed.location.revision + 1)
        if newerObservation {
            map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: summaries,
                locations: scoped && moveOut ? [] : [latest], libraryRevision: committed.libraryRevision + 1))
        }
        map.acceptCaptureCommit(model)
        #expect(!presentation.completeSave())
        #expect(presentation.mode == .read)
        #expect(map.selectedDetail?.id == .savedLocation(committed.location.id))
        #expect(map.presentedDetail?.id == .savedLocation(committed.location.id))
        #expect(map.displayedSavedLocation?.id == committed.location.id)
        #expect(map.locationFocus == focus)
        #expect(map.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(map.cameraPosition.region?.center.longitude == camera.center.longitude)
        #expect(map.cameraPosition.region?.span.latitudeDelta == camera.span.latitudeDelta)
        #expect(map.cameraPosition.region?.span.longitudeDelta == camera.span.longitudeDelta)
        if scoped && moveOut {
            #expect(map.selectedSavedLocation == nil)
            #expect(map.committedReceipt?.id == committed.location.id)
            #expect(map.savedLocations.isEmpty)
        } else {
            #expect(map.selectedSavedLocation == (newerObservation ? latest : committed.location))
        }
        #expect(await repository.creates.count == 1)
    }

    /// AC-45, INV-08/09: awaiting staged-media cleanup cannot close or replace the owned update.
    @Test func heldMediaDiscardRejectsReentrantPresentationActions() async throws {
        let repository = DetailPresentationRepository()
        let media = try DetailPresentationMedia(holdsDiscard: true)
        let model = try capture(saved: nil, repository: repository, media: media)
        let replacement = try capture(saved: nil, repository: repository)
        let presentation = LocationDetailsPresentation(mode: .read, returnsToRead: true)
        presentation.beginUpdate(model)
        await model.importPhoto(data: DetailPresentationFixture.image)
        #expect(!presentation.requestClose())
        let discard = Task { await presentation.discardUpdate() }
        await media.waitForDiscard()
        #expect(presentation.isDiscarding)
        #expect(presentation.mode == .update)
        #expect(!presentation.requestClose())
        #expect(await presentation.discardUpdate() == false)
        #expect(!presentation.completeSave())
        presentation.beginUpdate(replacement)
        #expect(presentation.model === model)
        #expect(await repository.creates.isEmpty)
        #expect(await repository.updates.isEmpty)
        await media.releaseDiscard()
        #expect(await discard.value == false)
        #expect(!presentation.isDiscarding)
        #expect(presentation.mode == .read)
        #expect(presentation.model === model)
        #expect(model.assets.isEmpty)
        #expect(await media.discarded.count == 1)
    }

    /// AC-69: only a committed save emits success, in the sheet that remains visible.
    @Test(arguments: [false, true], [false, true])
    func successToastUsesVisibleOwnerAfterCommit(saved: Bool, returnsToRead: Bool) async throws {
        let repository = DetailPresentationRepository(failure: .storageFailure)
        let original = saved ? try DetailPresentationFixture.saved() : nil
        let model = try capture(saved: original, repository: repository)
        let presentation = LocationDetailsPresentation(model: model, mode: .update, returnsToRead: returnsToRead)
        let sheetToast = DSToastManager()
        let parentToast = DSToastManager()
        presentation.beginEditing()
        #expect(!presentation.completeSave(toastManager: sheetToast, dismissedToastManager: parentToast))
        #expect(sheetToast.currentPresentation == nil)
        #expect(parentToast.currentPresentation == nil)
        await model.save()
        #expect(!presentation.completeSave(toastManager: sheetToast, dismissedToastManager: parentToast))
        #expect(sheetToast.currentPresentation == nil)
        #expect(parentToast.currentPresentation == nil)
        await repository.allowSuccess()
        await model.save()
        #expect(model.commit != nil)
        #expect(presentation.completeSave(toastManager: sheetToast, dismissedToastManager: parentToast) == !returnsToRead)
        let visibleToast = returnsToRead ? sheetToast : parentToast
        let hiddenToast = returnsToRead ? parentToast : sheetToast
        #expect(visibleToast.currentPresentation?.localizationKey == LocationKeys.saveSucceeded.rawValue)
        #expect(visibleToast.currentPresentation?.duration == .seconds(3))
        #expect(hiddenToast.currentPresentation == nil)
        if returnsToRead {
            let toastID = visibleToast.currentPresentation?.id
            #expect(!presentation.completeSave(toastManager: sheetToast, dismissedToastManager: parentToast))
            #expect(visibleToast.currentPresentation?.id == toastID)
        }
    }

    /// AC-47: standalone successful Save still requests dismissal.
    @Test func standaloneSaveRequestsDismissal() async throws {
        let repository = DetailPresentationRepository()
        let model = try capture(saved: nil, repository: repository)
        let presentation = LocationDetailsPresentation(model: model, mode: .update, returnsToRead: false)
        presentation.beginEditing()
        await model.save()
        #expect(presentation.completeSave())
        #expect(!model.isEditing)
        #expect(await repository.creates.count == 1)
    }
}
