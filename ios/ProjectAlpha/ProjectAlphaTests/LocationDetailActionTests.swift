//
//  LocationDetailActionTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 26/10/26.
//

import Foundation
import MapKit
import SwiftUI
import Testing
@testable import ProjectAlpha

private nonisolated enum DetailActionFixture {
    static let name = "Museum & Gallery"
    static let address = "1 Museum Street"
    static let notes = "Private visit notes"
    static let updatedNotes = "Notes changed by another scene"
    static let collectionName = "Places"
    static let date = Date(timeIntervalSince1970: 100)
    static let mutationDate = Date(timeIntervalSince1970: 200)
    static let newline = "\n"
    static let mapsHost = "maps.apple.com"
    static let coordinateParameter = "ll"
    static let coordinateText = "10.75, 106.5"
    static let nameParameter = "q"
    static let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let collectionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    static let otherID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
    static let thirdID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
    static let otherCollectionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5))

    static func saved(id: UUID = DetailActionFixture.id, revision: Int64 = 3, favorite: Bool = false,
                      notes: String? = DetailActionFixture.notes) throws -> SavedLocation {
        SavedLocation(id: id, collectionID: collectionID, placeIdentity: nil, source: .manualCoordinate,
            name: name, displayName: nil, address: address,
            coordinate: try Coordinate(latitude: 10.75, longitude: 106.5), category: nil,
            notes: notes, assets: [], isFavorite: favorite, createdAt: date, updatedAt: date, revision: revision)
    }

    static func snapshot(_ location: SavedLocation?, revision: Int64 = 5) -> LocationLibrarySnapshot {
        let collection = Collection(id: collectionID, name: collectionName, isDefault: true,
            createdAt: date, updatedAt: date, revision: 1)
        return LocationLibrarySnapshot(collections: [CollectionSummary(collection: collection,
            locationCount: location == nil ? 0 : 1)], locations: location.map { [$0] } ?? [], libraryRevision: revision)
    }
}

/// A controlled suspension proves pending-operation behavior without scheduler sleeps.
private actor DetailActionGate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func suspend() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            release = continuation
            entered = true
            entry?.resume()
            entry = nil
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entry = $0 }
    }

    func open() {
        release?.resume()
        release = nil
    }
}

private actor DetailActionRepository: LocationRepository {
    private var current: SavedLocation?
    private var failure: LocationWriteError?
    private let gate: DetailActionGate?
    private(set) var lookups: [UUID] = []
    private(set) var favorites: [SetLocationFavoriteCommand] = []
    private(set) var deletions: [DeleteLocationCommand] = []
    private(set) var otherWrites = 0

    init(current: SavedLocation?, failure: LocationWriteError? = nil, gate: DetailActionGate? = nil) {
        self.current = current
        self.failure = failure
        self.gate = gate
    }

    func allowSuccess() { failure = nil }
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        DetailActionFixture.snapshot(current)
    }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func location(id: UUID) async throws -> SavedLocation? {
        lookups.append(id)
        return current?.id == id ? current : nil
    }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        otherWrites += 1
        throw LocationWriteError.storageFailure
    }
    func updateLocation(_ command: UpdateLocationCommand) async throws -> LocationCommit {
        otherWrites += 1
        throw LocationWriteError.storageFailure
    }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        favorites.append(command)
        await gate?.suspend()
        if let failure { throw failure }
        guard let original = current else { throw LocationWriteError.locationMissing(command.id) }
        let updated = SavedLocation(id: original.id, collectionID: original.collectionID,
            placeIdentity: original.placeIdentity, source: original.source, name: original.name,
            displayName: original.displayName, address: original.address, coordinate: original.coordinate,
            category: original.category, notes: original.notes, assets: original.assets,
            isFavorite: command.isFavorite, createdAt: original.createdAt,
            updatedAt: command.updatedAt, revision: original.revision + 1)
        current = updated
        return LocationCommit(location: updated, libraryRevision: 6)
    }
    func deleteLocation(_ command: DeleteLocationCommand) async throws -> DeleteLocationCommit {
        deletions.append(command)
        await gate?.suspend()
        if let failure { throw failure }
        guard let current else { throw LocationWriteError.locationMissing(command.id) }
        guard current.revision == command.expectedRevision else { throw LocationWriteError.editConflict(latest: current) }
        self.current = nil
        return DeleteLocationCommit(deletedLocationID: command.id, libraryRevision: 6)
    }
}

/// P-06, AC-24/44/55/69, D-03/D-13/D-17, INV-05/07/09.
/// Native menus, pasteboard interaction and system sharing require separate UI evidence.
@MainActor
struct LocationDetailActionTests {
    /// AC-24/J-07: informational payloads preserve facts without mutation or private notes by default.
    @Test(arguments: [false, true])
    func copyAndSharePayloadContainOnlyAvailablePublicFacts(hasAddress: Bool) throws {
        let saved = try DetailActionFixture.saved()
        let payload = LocationDetailPayload(name: saved.name,
            address: hasAddress ? saved.address : nil, coordinate: saved.coordinate, notes: saved.notes)
        #expect(payload.coordinateText == DetailActionFixture.coordinateText)
        #expect(payload.locationInfo.contains(DetailActionFixture.name))
        #expect(payload.locationInfo.contains(payload.coordinateText))
        #expect(payload.locationInfo.contains(DetailActionFixture.address) == hasAddress)
        #expect(!payload.locationInfo.contains(DetailActionFixture.notes))
        let publicShare = payload.shareText(includeNotes: false)
        #expect(publicShare.contains(DetailActionFixture.name))
        #expect(publicShare.contains(payload.coordinateText))
        #expect(publicShare.contains(DetailActionFixture.address) == hasAddress)
        #expect(publicShare.contains(payload.mapsURL.absoluteString))
        #expect(!publicShare.contains(DetailActionFixture.notes))
        #expect(!publicShare.contains(saved.id.uuidString))
        let privateShare = payload.shareText(includeNotes: true)
        #expect(privateShare.contains(DetailActionFixture.notes))
        #expect(privateShare.contains(publicShare))
        let components = try #require(URLComponents(url: payload.mapsURL, resolvingAgainstBaseURL: false))
        #expect(components.host == DetailActionFixture.mapsHost)
        #expect(components.queryItems?.first { $0.name == DetailActionFixture.coordinateParameter }?.value
            == DetailActionFixture.coordinateText)
        #expect(components.queryItems?.first { $0.name == DetailActionFixture.nameParameter }?.value == DetailActionFixture.name)
    }

    /// AC-24/J-07: unavailable address/notes produce no synthetic private content or empty payload sections.
    @Test func absentNotesCannotChangeSharedPayload() throws {
        let saved = try DetailActionFixture.saved(notes: nil)
        let payload = LocationDetailPayload(name: DetailActionFixture.name, address: nil,
            coordinate: saved.coordinate, notes: nil)
        #expect(payload.shareText(includeNotes: true) == payload.shareText(includeNotes: false))
        #expect(!payload.locationInfo.components(separatedBy: DetailActionFixture.newline).contains(String()))
    }

    /// INV-05/07: favorite reads the current UUID and patches only the latest favorite flag.
    @Test func favoriteUsesLatestRecordInsteadOfStaleDisplayedFlag() async throws {
        let original = try DetailActionFixture.saved()
        let latest = try DetailActionFixture.saved(revision: 9, favorite: true,
            notes: DetailActionFixture.updatedNotes)
        let repository = DetailActionRepository(current: latest)
        let actions = LocationDetailActionModel(repository: repository, clock: { DetailActionFixture.mutationDate })
        let commit = try #require(await actions.toggleFavorite(original))
        #expect(await repository.lookups == [original.id])
        #expect(await repository.favorites == [SetLocationFavoriteCommand(id: original.id,
            isFavorite: false, updatedAt: DetailActionFixture.mutationDate)])
        #expect(commit.location.id == original.id)
        #expect(commit.location.revision == latest.revision + 1)
        #expect(commit.location.notes == latest.notes)
        #expect(!commit.location.isFavorite)
        #expect(actions.actionError == nil)
        #expect(!actions.isPerformingAction)
        #expect(await repository.otherWrites == 0)
        #expect(await repository.deletions.isEmpty)
    }

    /// INV-05: failed favorite cannot return a commit or optimistic success; explicit retry remains possible.
    @Test func failedFavoriteReturnsNoCommitAndAllowsRetry() async throws {
        let original = try DetailActionFixture.saved()
        let repository = DetailActionRepository(current: original, failure: .storageFailure)
        let actions = LocationDetailActionModel(repository: repository, clock: { DetailActionFixture.mutationDate })
        #expect(await actions.toggleFavorite(original) == nil)
        #expect(actions.actionError == .storageFailure)
        #expect(actions.failedAction == .favorite)
        #expect(!actions.isPerformingAction)
        await repository.allowSuccess()
        #expect(await actions.toggleFavorite(original)?.location.isFavorite == true)
        #expect(actions.actionError == nil)
        #expect(await repository.favorites.count == 2)
    }

    /// AC-55, INV-07: a removed saved UUID cannot accidentally toggle another record.
    @Test func favoriteOfMissingRecordHasNoWrite() async throws {
        let original = try DetailActionFixture.saved()
        let repository = DetailActionRepository(current: nil)
        let actions = LocationDetailActionModel(repository: repository)
        #expect(await actions.toggleFavorite(original) == nil)
        #expect(actions.actionError == .locationMissing(original.id))
        #expect(await repository.favorites.isEmpty)
        #expect(await repository.deletions.isEmpty)
    }

    /// D-09, INV-05: showing and cancelling Delete confirmation performs no storage operation.
    @Test func cancelDeleteClearsDestructiveTargetWithoutWriting() async throws {
        let original = try DetailActionFixture.saved()
        let repository = DetailActionRepository(current: original)
        let actions = LocationDetailActionModel(repository: repository)
        actions.requestDelete(original)
        #expect(actions.deleteTarget == original)
        #expect(actions.deleteNeedsConfirmation)
        actions.cancelDelete()
        #expect(actions.deleteTarget == nil)
        #expect(!actions.deleteNeedsConfirmation)
        #expect(await actions.deleteLocation() == nil)
        #expect(await repository.lookups.isEmpty)
        #expect(await repository.deletions.isEmpty)
        #expect(await repository.favorites.isEmpty)
        #expect(await repository.otherWrites == 0)
    }

    /// AC-55, INV-05/07: a conflict keeps the latest target for explicit reconfirmation, never automatic deletion.
    @Test func staleDeleteRequiresExplicitConfirmationOfLatestRevision() async throws {
        let original = try DetailActionFixture.saved()
        let latest = try DetailActionFixture.saved(revision: 8, notes: DetailActionFixture.updatedNotes)
        let repository = DetailActionRepository(current: latest)
        let actions = LocationDetailActionModel(repository: repository)
        actions.requestDelete(original)
        actions.deleteNeedsConfirmation = false
        #expect(await actions.deleteLocation() == nil)
        #expect(actions.actionError == .editConflict(latest: latest))
        #expect(actions.deleteTarget == latest)
        #expect(!actions.deleteNeedsConfirmation)
        #expect(await repository.deletions == [DeleteLocationCommand(id: original.id,
            expectedRevision: original.revision)])
        actions.requestDelete(latest)
        #expect(actions.deleteNeedsConfirmation)
        #expect(actions.actionError == nil)
        actions.deleteNeedsConfirmation = false
        #expect(await actions.deleteLocation()?.deletedLocationID == original.id)
        #expect(actions.deleteTarget == nil)
        #expect(await repository.deletions.map(\.expectedRevision) == [original.revision, latest.revision])
    }

    /// AC-69, INV-05: only a successful persistence result is eligible for Delete success/dismiss feedback.
    @Test func failedDeleteKeepsTargetAndReturnsNoSuccessUntilRetryCommits() async throws {
        let original = try DetailActionFixture.saved()
        let repository = DetailActionRepository(current: original, failure: .storageFailure)
        let actions = LocationDetailActionModel(repository: repository)
        actions.requestDelete(original)
        actions.deleteNeedsConfirmation = false
        #expect(await actions.deleteLocation() == nil)
        #expect(actions.actionError == .storageFailure)
        #expect(actions.deleteTarget == original)
        #expect(actions.failedAction == .delete)
        #expect(!actions.isPerformingAction)
        await repository.allowSuccess()
        let result = try #require(await actions.deleteLocation())
        #expect(result.deletedLocationID == original.id)
        #expect(actions.actionError == nil)
        #expect(actions.deleteTarget == nil)
        #expect(!actions.isPerformingAction)
        #expect(await repository.deletions.count == 2)
    }

    /// INV-05/07: pending favorite blocks every repeated mutation and destructive re-targeting.
    @Test func pendingFavoriteRejectsRepeatedFavoriteAndDelete() async throws {
        let original = try DetailActionFixture.saved()
        let gate = DetailActionGate()
        let repository = DetailActionRepository(current: original, gate: gate)
        let actions = LocationDetailActionModel(repository: repository)
        let pending = Task { await actions.toggleFavorite(original) }
        await gate.waitUntilEntered()
        #expect(actions.isPerformingAction)
        #expect(await actions.toggleFavorite(original) == nil)
        actions.requestDelete(original)
        #expect(actions.deleteTarget == nil)
        #expect(await actions.deleteLocation() == nil)
        #expect(await repository.favorites.count == 1)
        #expect(await repository.deletions.isEmpty)
        await gate.open()
        #expect(await pending.value?.location.isFavorite == true)
        #expect(!actions.isPerformingAction)
    }

    /// INV-05/07: pending Delete returns no success until commit and coalesces repeated taps.
    @Test func pendingDeleteRejectsRepeatedMutationsUntilCommit() async throws {
        let original = try DetailActionFixture.saved()
        let gate = DetailActionGate()
        let repository = DetailActionRepository(current: original, gate: gate)
        let actions = LocationDetailActionModel(repository: repository)
        actions.requestDelete(original)
        actions.deleteNeedsConfirmation = false
        let pending = Task { await actions.deleteLocation() }
        await gate.waitUntilEntered()
        #expect(actions.isPerformingAction)
        #expect(actions.deleteTarget == original)
        #expect(await actions.deleteLocation() == nil)
        #expect(await actions.toggleFavorite(original) == nil)
        #expect(await repository.deletions.count == 1)
        #expect(await repository.favorites.isEmpty)
        await gate.open()
        #expect(await pending.value?.deletedLocationID == original.id)
        #expect(actions.deleteTarget == nil)
        #expect(!actions.isPerformingAction)
    }

    /// AC-24/55: a preview/unsupported repository cannot advertise mutations or fabricate commits.
    @Test func unavailableRepositoryNeverCommits() async throws {
        let original = try DetailActionFixture.saved()
        let actions = LocationDetailActionModel(repository: nil)
        #expect(!actions.canMutate)
        #expect(await actions.toggleFavorite(original) == nil)
        actions.requestDelete(original)
        #expect(await actions.deleteLocation() == nil)
        #expect(!actions.isPerformingAction)
    }

    /// AC-24/55, INV-07/09: a committed Favorite updates detail immediately without recentering either map.
    @Test(arguments: [false, true])
    func mapFavoriteKeepsDetailSelectionAndCamera(scoped: Bool) async throws {
        let original = try DetailActionFixture.saved()
        let latest = try DetailActionFixture.saved(revision: 8, notes: DetailActionFixture.updatedNotes)
        let repository = DetailActionRepository(current: latest)
        let map = makeMap(original, repository: repository, scoped: scoped)
        let camera = try #require(map.cameraPosition.region)
        let focus = map.locationFocus
        let detailID = map.selectedDetail?.id
        await map.toggleDetailFavorite(original)
        #expect(map.selectedDetail?.id == detailID)
        #expect(map.displayedSavedLocation?.id == original.id)
        #expect(map.displayedSavedLocation?.revision == latest.revision + 1)
        #expect(map.displayedSavedLocation?.notes == latest.notes)
        #expect(map.displayedSavedLocation?.isFavorite == true)
        #expect(map.savedLocations.first?.isFavorite == true)
        #expect(map.scopeCollectionID == (scoped ? original.collectionID : nil))
        #expect(map.locationFocus == focus)
        expectCamera(map, equals: camera)
    }

    /// AC-55/69, INV-05/09: Delete failure leaves detail visible; success clears only committed selection.
    @Test(arguments: [false, true])
    func mapDeleteRetainsDetailOnFailureAndDismissesOnlyAfterCommit(scoped: Bool) async throws {
        let original = try DetailActionFixture.saved()
        let repository = DetailActionRepository(current: original, failure: .storageFailure)
        let map = makeMap(original, repository: repository, scoped: scoped)
        let camera = try #require(map.cameraPosition.region)
        let focus = map.locationFocus
        map.detailActions.requestDelete(original)
        map.detailActions.deleteNeedsConfirmation = false
        #expect(await map.deleteDetailLocation() == false)
        #expect(map.displayedSavedLocation == original)
        #expect(map.selectedDetail?.id == .savedLocation(original.id))
        #expect(map.savedLocations == [original])
        #expect(map.detailActions.actionError == .storageFailure)
        await repository.allowSuccess()
        #expect(await map.deleteDetailLocation())
        #expect(map.displayedSavedLocation == nil)
        #expect(map.selectedDetail == nil)
        #expect(map.savedLocations.isEmpty)
        #expect(map.scopeCollectionID == (scoped ? original.collectionID : nil))
        #expect(map.locationFocus == focus)
        expectCamera(map, equals: camera)
    }

    /// INV-07/09: a late Favorite receipt cannot overwrite a newer library observation.
    @Test func newerObservedRevisionWinsOverSuspendedFavoriteCommit() async throws {
        let original = try DetailActionFixture.saved()
        let latest = try DetailActionFixture.saved(revision: 11, notes: DetailActionFixture.updatedNotes)
        let gate = DetailActionGate()
        let repository = DetailActionRepository(current: original, gate: gate)
        let map = makeMap(original, repository: repository)
        let camera = try #require(map.cameraPosition.region)
        let pending = Task { await map.toggleDetailFavorite(original) }
        await gate.waitUntilEntered()
        map.applyLibrarySnapshot(DetailActionFixture.snapshot(latest, revision: 7))
        await gate.open()
        await pending.value
        #expect(map.displayedSavedLocation == latest)
        #expect(map.savedLocations == [latest])
        #expect(map.libraryRevision == 7)
        #expect(map.selectedDetail?.id == .savedLocation(original.id))
        expectCamera(map, equals: camera)
    }

    /// INV-09: a committed deletion cannot dismiss a newer user-selected candidate detail.
    @Test func pendingDeletePreservesNewCandidateSelectionAndCamera() async throws {
        let original = try DetailActionFixture.saved()
        let gate = DetailActionGate()
        let repository = DetailActionRepository(current: original, gate: gate)
        let map = makeMap(original, repository: repository)
        map.detailActions.requestDelete(original)
        map.detailActions.deleteNeedsConfirmation = false
        let pending = Task { await map.deleteDetailLocation() }
        await gate.waitUntilEntered()
        let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: DetailActionFixture.name, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 20, longitude: 30))
        map.selectSearchCandidate(candidate)
        map.showDetails()
        let camera = try #require(map.cameraPosition.region)
        let focus = map.locationFocus
        await gate.open()
        #expect(await pending.value)
        #expect(map.selectedCandidate == candidate)
        #expect(map.selectedDetail?.id == .searchCandidate(candidate.id))
        #expect(map.visiblePlace?.coordinate == candidate.coordinate)
        #expect(map.savedLocations.isEmpty)
        #expect(map.locationFocus == focus)
        expectCamera(map, equals: camera)
    }

    /// AC-24/55, INV-05/09: observation cannot reveal fallback before the command returns success.
    @Test(arguments: [Int64(6), Int64(7)], [false, true])
    func observedDeletionRevealsRetainedCurrentPositionOnlyAfterCommit(observedRevision: Int64, scoped: Bool) async throws {
        let original = try DetailActionFixture.saved()
        let gate = DetailActionGate()
        let repository = DetailActionRepository(current: original, gate: gate)
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        let origin = try DevicePosition(coordinate: Coordinate(latitude: 10, longitude: 106),
            timestamp: DetailActionFixture.date, horizontalAccuracyMetres: 10,
            authorization: MapPresentationLocationService.allowed)
        positions.immediateResult = .success(origin)
        let map = MapViewModel(deviceLocationService: positions,
            positionClock: { DetailActionFixture.mutationDate }, locationRepository: repository,
            scopeCollectionID: scoped ? original.collectionID : nil, initialLocationID: original.id)
        #expect(await map.activate() == nil)
        #expect(map.currentPosition == origin)
        map.applyLibrarySnapshot(DetailActionFixture.snapshot(original))
        map.showDetails()
        #expect(map.visiblePlace?.id == .savedLocation(original.id))
        let camera = try #require(map.cameraPosition.region)
        let focus = map.locationFocus
        map.detailActions.requestDelete(original)
        map.detailActions.deleteNeedsConfirmation = false
        let pending = Task { await map.deleteDetailLocation() }
        await gate.waitUntilEntered()
        map.applyLibrarySnapshot(DetailActionFixture.snapshot(nil, revision: observedRevision))
        #expect(map.selectedSavedLocation == nil)
        #expect(map.selectedDetail == nil)
        #expect(map.visiblePlace == nil)
        #expect(map.currentPosition == origin)
        expectCamera(map, equals: camera)
        await gate.open()
        #expect(await pending.value)
        #expect(map.visiblePlace?.id == .currentPosition)
        #expect(positions.positionCalls == 1)
        #expect(map.displayedSavedLocation == nil)
        #expect(map.selectedDetail == nil)
        #expect(map.selectedCandidate == nil)
        #expect(map.committedReceipt == nil)
        #expect(map.capture == nil)
        #expect(map.existingSavedLocationID == nil)
        #expect(map.libraryRevision == observedRevision)
        #expect(map.locationFocus == focus)
        #expect(map.currentPosition == origin)
        expectCamera(map, equals: camera)
        map.deactivate()
    }

    /// U-12/AC-24: next in collection order, or preceding at the end, with no camera change.
    @Test(arguments: [false, true], [0, 1, 2])
    func deleteSelectsNextRemainingLocationInSameCollection(scoped: Bool, deletedIndex: Int) async throws {
        let records = try [DetailActionFixture.id, DetailActionFixture.otherID, DetailActionFixture.thirdID]
            .map { try DetailActionFixture.saved(id: $0) }
        let target = records[deletedIndex]
        let repository = DetailActionRepository(current: target)
        let map = makeMap(target, repository: repository, scoped: scoped)
        let initial = DetailActionFixture.snapshot(target)
        map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: initial.collections,
            locations: records, libraryRevision: initial.libraryRevision))
        let camera = try #require(map.cameraPosition.region)
        map.detailActions.requestDelete(target)
        #expect(await map.deleteDetailLocation())
        let expected = records[deletedIndex == 2 ? 1 : deletedIndex + 1]
        #expect(map.selectedSavedLocation?.id == expected.id)
        #expect(map.visiblePlace?.id == .savedLocation(expected.id))
        #expect(map.selectedDetail == nil)
        #expect(map.mapSelection?.value == expected.id)
        #expect(!map.savedLocations.contains { $0.id == target.id })
        expectCamera(map, equals: camera)
    }

    /// A newer stream can remove the next neighbor before the command resumes.
    @Test(arguments: [false, true])
    func deleteChoosesCurrentNeighborAfterNewerObservation(insertsNeighbor: Bool) async throws {
        let first = try DetailActionFixture.saved()
        let second = try DetailActionFixture.saved(id: DetailActionFixture.otherID)
        let third = try DetailActionFixture.saved(id: DetailActionFixture.thirdID)
        let gate = DetailActionGate()
        let repository = DetailActionRepository(current: first, gate: gate)
        let map = makeMap(first, repository: repository, scoped: true)
        let initial = DetailActionFixture.snapshot(first)
        map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: initial.collections,
            locations: insertsNeighbor ? [first, third] : [first, second, third], libraryRevision: 5))
        map.detailActions.requestDelete(first)
        let pending = Task { await map.deleteDetailLocation() }
        await gate.waitUntilEntered()
        let remaining = insertsNeighbor ? [second, third] : [third]
        map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: initial.collections,
            locations: remaining, libraryRevision: 7))
        #expect(map.visiblePlace == nil)
        await gate.open()
        #expect(await pending.value)
        #expect(map.visiblePlace?.id == .savedLocation(try #require(remaining.first).id))
        #expect(map.savedLocations == remaining)
        #expect(map.libraryRevision == 7)
    }

    /// Empty collection restores Search ahead of retained GPS, including on Global Map.
    @Test(arguments: [false, true])
    func deleteLastRestoresPreviousSearchWithoutRequestingPosition(scoped: Bool) async throws {
        let original = try DetailActionFixture.saved()
        let repository = DetailActionRepository(current: original)
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        let origin = try DevicePosition(coordinate: Coordinate(latitude: 10, longitude: 106),
            timestamp: DetailActionFixture.date, horizontalAccuracyMetres: 10,
            authorization: MapPresentationLocationService.allowed)
        positions.immediateResult = .success(origin)
        let map = MapViewModel(deviceLocationService: positions,
            positionClock: { DetailActionFixture.mutationDate }, locationRepository: repository,
            scopeCollectionID: scoped ? original.collectionID : nil, initialLocationID: original.id)
        #expect(await map.activate() == nil)
        map.applyLibrarySnapshot(DetailActionFixture.snapshot(original))
        let candidate = PlaceCandidate(id: DetailActionFixture.thirdID, source: .manualCoordinate,
            placeIdentity: nil, name: DetailActionFixture.name, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 20, longitude: 30))
        map.selectSearchCandidate(candidate)
        map.selectSavedLocation(original.id)
        let camera = try #require(map.cameraPosition.region)
        let calls = positions.positionCalls
        map.detailActions.requestDelete(original)
        #expect(await map.deleteDetailLocation())
        #expect(map.selectedCandidate == candidate)
        #expect(map.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(positions.positionCalls == calls)
        #expect(map.currentPosition == origin)
        if scoped { #expect(map.collectionTemporaryPlace?.id == .searchCandidate(candidate.id)) }
        expectCamera(map, equals: camera)
        map.deactivate()
    }

    /// A remaining Global Map record from another collection is not an eligible successor.
    @Test func deleteDoesNotSelectAnUnrelatedCollection() async throws {
        let original = try DetailActionFixture.saved()
        let other = SavedLocation(id: DetailActionFixture.otherID,
            collectionID: DetailActionFixture.otherCollectionID, placeIdentity: nil, source: original.source,
            name: original.name, displayName: nil, address: nil, coordinate: original.coordinate,
            category: nil, notes: nil, assets: [], isFavorite: false,
            createdAt: original.createdAt, updatedAt: original.updatedAt, revision: 1)
        let repository = DetailActionRepository(current: original)
        let map = makeMap(original, repository: repository)
        let initial = DetailActionFixture.snapshot(original)
        map.applyLibrarySnapshot(LocationLibrarySnapshot(collections: initial.collections,
            locations: [original, other], libraryRevision: 5))
        map.detailActions.requestDelete(original)
        #expect(await map.deleteDetailLocation())
        #expect(map.savedLocations == [other])
        #expect(map.visiblePlace == nil)
        #expect(map.selectedSavedLocation == nil)
    }

    /// AC-55, INV-07/09: an old detail's late error cannot expose Retry for a new saved UUID.
    @Test func failedFavoriteFeedbackStaysWithOriginalDetailAfterSelectingAnotherSavedLocation() async throws {
        let first = try DetailActionFixture.saved()
        let second = try DetailActionFixture.saved(id: DetailActionFixture.otherID)
        let gate = DetailActionGate()
        let repository = DetailActionRepository(current: first, failure: .storageFailure, gate: gate)
        let map = makeMap(first, repository: repository)
        let pending = Task { await map.toggleDetailFavorite(first) }
        await gate.waitUntilEntered()
        map.selectedDetail = nil
        map.applyLibrarySnapshot(DetailActionFixture.snapshot(second, revision: 6))
        map.selectSavedLocation(second.id)
        map.showDetails()
        let camera = try #require(map.cameraPosition.region)
        await gate.open()
        await pending.value
        #expect(map.detailActions.actionError == .storageFailure)
        #expect(map.detailActions.failedAction == .favorite)
        #expect(map.detailActions.hasFeedback(for: first.id))
        #expect(!map.detailActions.hasFeedback(for: map.displayedSavedLocation?.id))
        #expect(!map.detailActions.hasFeedback(for: nil))
        #expect(map.displayedSavedLocation == second)
        #expect(map.selectedDetail?.id == .savedLocation(second.id))
        #expect(await repository.favorites.map(\.id) == [first.id])
        #expect(await repository.deletions.isEmpty)
        #expect(await repository.otherWrites == 0)
        expectCamera(map, equals: camera)
    }

    private func makeMap(_ location: SavedLocation, repository: DetailActionRepository,
                         scoped: Bool = false) -> MapViewModel {
        let map = MapViewModel(deviceLocationService: MapPresentationLocationService(),
            positionClock: { DetailActionFixture.mutationDate }, locationRepository: repository,
            scopeCollectionID: scoped ? location.collectionID : nil, initialLocationID: location.id)
        map.applyLibrarySnapshot(DetailActionFixture.snapshot(location))
        map.showDetails()
        return map
    }

    private func expectCamera(_ map: MapViewModel, equals region: MKCoordinateRegion) {
        #expect(map.cameraPosition.region?.center.latitude == region.center.latitude)
        #expect(map.cameraPosition.region?.center.longitude == region.center.longitude)
        #expect(map.cameraPosition.region?.span.latitudeDelta == region.span.latitudeDelta)
        #expect(map.cameraPosition.region?.span.longitudeDelta == region.span.longitudeDelta)
    }
}
