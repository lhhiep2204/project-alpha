//
//  ObservationRecoveryTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 26/10/26.
//

import Foundation
import MapKit
import SwiftUI
import Testing
import UIKit
import XCTest
@testable import ProjectAlpha

private enum ObservationRecoveryFixture {
    static let collectionName = "Retained collection"
    static let updatedName = "Updated retained collection"
    static let staleName = "Obsolete collection"
    static let placeName = "Observation test place"
    static let notes = "Keep this draft through observation recovery"
    static let firstSubscription = "Initial editor observation registered"
    static let retrySubscription = "Parent editor retry registered"
    static let date = Date(timeIntervalSince1970: 100)

    static func snapshot(id: UUID, name: String, revision: Int64) -> CollectionListSnapshot {
        CollectionListSnapshot(collections: [CollectionSummary(collection: Collection(
            id: id, name: name, isDefault: false, createdAt: date, updatedAt: date,
            revision: revision), locationCount: 0)], libraryRevision: revision)
    }

    @MainActor
    static func model(collections: any CollectionRepository, id: UUID = UUID()) throws -> LocationCaptureModel {
        LocationCaptureModel(candidate: PlaceCandidate(id: id, source: .manualCoordinate,
            placeIdentity: nil, name: placeName, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 10, longitude: 20)), destinationCollectionID: id,
            repository: ObservationRecoveryLocations(), collectionRepository: collections,
            id: id, createdAt: date)
    }
}

private enum ObservationRecoveryFailure: Error { case observation, unexpectedOperation }

private actor ObservationRecoveryCollections: CollectionRepository {
    private var streams: [AsyncThrowingStream<CollectionListSnapshot, any Error>.Continuation] = []
    private var registrationWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private let onRegistration: (@MainActor @Sendable (Int) -> Void)?

    init(onRegistration: (@MainActor @Sendable (Int) -> Void)? = nil) {
        self.onRegistration = onRegistration
    }

    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        let pair = AsyncThrowingStream<CollectionListSnapshot, any Error>.makeStream()
        streams.append(pair.continuation)
        registrationWaiters.removeValue(forKey: streams.count)?.resume()
        if let onRegistration { await onRegistration(streams.count) }
        return pair.stream
    }

    func waitForRegistration(_ count: Int) async {
        if streams.count >= count { return }
        await withCheckedContinuation { registrationWaiters[count] = $0 }
    }

    func send(_ snapshot: CollectionListSnapshot, session: Int) { streams[session - 1].yield(snapshot) }
    func fail(_ session: Int) { streams[session - 1].finish(throwing: ObservationRecoveryFailure.observation) }
    func finish(_ session: Int) { streams[session - 1].finish() }
    func finishAll() { for stream in streams { stream.finish() } }

    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot {
        throw ObservationRecoveryFailure.unexpectedOperation
    }
    func snapshot() async throws -> CollectionListSnapshot { throw ObservationRecoveryFailure.unexpectedOperation }
    func collection(id: UUID) async throws -> CollectionSummary? { throw ObservationRecoveryFailure.unexpectedOperation }
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        throw ObservationRecoveryFailure.unexpectedOperation
    }
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        throw ObservationRecoveryFailure.unexpectedOperation
    }
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit {
        throw ObservationRecoveryFailure.unexpectedOperation
    }
}

private struct ObservationRecoveryLocations: LocationRepository {
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        throw ObservationRecoveryFailure.unexpectedOperation
    }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func location(id: UUID) async throws -> SavedLocation? { throw ObservationRecoveryFailure.unexpectedOperation }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        throw ObservationRecoveryFailure.unexpectedOperation
    }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw ObservationRecoveryFailure.unexpectedOperation
    }
}

/// D-03/D-20, AC-44/45, INV-09: only the current parent-owned request may change a retained draft.
@MainActor
struct LocationCollectionObservationTests {
    @Test func retryRejectsOldStreamBeforeReplacementStartsAndPreservesDraft() async throws {
        let repository = ObservationRecoveryCollections()
        let model = try ObservationRecoveryFixture.model(collections: repository)
        model.notes = ObservationRecoveryFixture.notes
        let draft = model.draft
        let first = Task { await model.observeCollections() }
        await repository.waitForRegistration(1)
        let oldRequest = model.collectionObservationRequestID
        model.retryCollectionObservation()
        #expect(model.collectionObservationRequestID != oldRequest)
        await repository.send(ObservationRecoveryFixture.snapshot(id: model.id,
            name: ObservationRecoveryFixture.staleName, revision: 1), session: 1)
        await repository.fail(1)
        await first.value
        #expect(model.collections.isEmpty)
        #expect(!model.collectionLoadFailed)
        let replacement = Task { await model.observeCollections() }
        await repository.waitForRegistration(2)
        let current = ObservationRecoveryFixture.snapshot(id: model.id,
            name: ObservationRecoveryFixture.updatedName, revision: 2)
        await repository.send(current, session: 2)
        await repository.finish(2)
        await replacement.value
        #expect(model.collections == current.collections)
        #expect(!model.collectionLoadFailed)
        #expect(model.draft == draft)
        #expect(model.canSave)
    }

    @Test func cancelledObservationDoesNotPoisonAReplacementWithSameDraftIdentity() async throws {
        let repository = ObservationRecoveryCollections()
        let id = UUID()
        let old = try ObservationRecoveryFixture.model(collections: repository, id: id)
        let replacement = try ObservationRecoveryFixture.model(collections: repository, id: id)
        #expect(old.mediaDraftID == replacement.mediaDraftID)
        #expect(old.collectionObservationRequestID != replacement.collectionObservationRequestID)
        let first = Task { await old.observeCollections() }
        await repository.waitForRegistration(1)
        first.cancel()
        await first.value
        #expect(!old.collectionLoadFailed)
        let second = Task { await replacement.observeCollections() }
        await repository.waitForRegistration(2)
        let current = ObservationRecoveryFixture.snapshot(id: id,
            name: ObservationRecoveryFixture.collectionName, revision: 2)
        await repository.send(current, session: 2)
        await repository.finish(2)
        await second.value
        #expect(replacement.collections == current.collections)
        #expect(old.collections.isEmpty)
    }
}

/// AC-44/45, D-03 and INV-09: exercise the real editor .task and actual child presentation teardown.
@MainActor
final class LocationCollectionObservationHostingTests: XCTestCase {
    func testPickerRetryRemainsObservedAfterChildDismissal() async throws {
        let initial = expectation(description: ObservationRecoveryFixture.firstSubscription)
        let restarted = expectation(description: ObservationRecoveryFixture.retrySubscription)
        let repository = ObservationRecoveryCollections { count in
            if count == 1 { initial.fulfill() }
            if count == 2 { restarted.fulfill() }
        }
        let model = try ObservationRecoveryFixture.model(collections: repository)
        model.notes = ObservationRecoveryFixture.notes
        let draft = model.draft
        let toast = DSToastManager()
        let host = UIHostingController(rootView: LocationDetailsEditor(model: model, rendersLiveMap: false)
            .environment(toast))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        await fulfillment(of: [initial], timeout: 5)
        await repository.fail(1)
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { model.collectionLoadFailed }
        }, object: nil)], timeout: 5)
        let picker = UIHostingController(rootView: LocationCollectionPicker(model: model).environment(toast))
        host.present(picker, animated: false)
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { picker.viewIfLoaded?.window != nil && !picker.isBeingPresented }
        }, object: nil)], timeout: 5)
        model.retryCollectionObservation()
        await fulfillment(of: [restarted], timeout: 5)
        picker.dismiss(animated: false)
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { host.presentedViewController == nil }
        }, object: nil)], timeout: 5)
        let current = ObservationRecoveryFixture.snapshot(id: model.id,
            name: ObservationRecoveryFixture.updatedName, revision: 2)
        await repository.send(current, session: 2)
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { model.collections == current.collections && !model.collectionLoadFailed }
        }, object: nil)], timeout: 5)
        XCTAssertEqual(model.draft, draft)
        XCTAssertTrue(model.canSave)
        await repository.finishAll()
    }
}

private struct ObservationRecoveryPosition: DeviceLocationService {
    func authorization() async -> LocationAuthorization {
        LocationAuthorization(status: .denied, accuracy: .full, servicesEnabled: true)
    }
    func currentPosition() async throws(LocationServiceError) -> DevicePosition { throw .permissionDenied }
}

private actor ObservationRecoveryMapRepository: LocationRepository {
    private var freshSnapshot: LocationLibrarySnapshot?
    private var freshLocation: Result<SavedLocation?, ObservationRecoveryFailure> = .failure(.unexpectedOperation)
    private var pausesNextLocation = false
    private var pendingLocation: CheckedContinuation<SavedLocation?, any Error>?
    private var pausedLocationWaiter: CheckedContinuation<Void, Never>?
    func pauseNextLocationRead() { pausesNextLocation = true }
    func waitForPausedLocation() async {
        if pendingLocation != nil { return }
        await withCheckedContinuation { pausedLocationWaiter = $0 }
    }
    func resumeLocation(missing: Bool) {
        let pending = pendingLocation
        pendingLocation = nil
        if missing { pending?.resume(returning: nil) }
        else { pending?.resume(throwing: ObservationRecoveryFailure.observation) }
    }
    func setFreshLocation(_ value: SavedLocation?) { freshLocation = .success(value) }
    private var commit: LocationCommit?
    private var pausesNextSnapshot = false
    private var pendingSnapshot: CheckedContinuation<LocationLibrarySnapshot, Never>?
    private var pausedSnapshotWaiter: CheckedContinuation<Void, Never>?
    func pauseNextSnapshotRead() { pausesNextSnapshot = true }
    func waitForPausedSnapshot() async {
        if pendingSnapshot != nil { return }
        await withCheckedContinuation { pausedSnapshotWaiter = $0 }
    }
    func resumeSnapshot(_ value: LocationLibrarySnapshot) {
        let pending = pendingSnapshot
        pendingSnapshot = nil
        pending?.resume(returning: value)
    }
    func setFreshSnapshot(_ value: LocationLibrarySnapshot) { freshSnapshot = value }
    func setCommit(_ value: LocationCommit) { commit = value }
    private var streams: [AsyncThrowingStream<LocationLibrarySnapshot, any Error>.Continuation] = []
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        let pair = AsyncThrowingStream<LocationLibrarySnapshot, any Error>.makeStream()
        streams.append(pair.continuation)
        waiters.removeValue(forKey: streams.count)?.resume()
        return pair.stream
    }
    func waitForRegistration(_ count: Int) async {
        if streams.count >= count { return }
        await withCheckedContinuation { waiters[count] = $0 }
    }
    func send(_ snapshot: LocationLibrarySnapshot, session: Int) { streams[session - 1].yield(snapshot) }
    func finish(_ session: Int) { streams[session - 1].finish() }
    func fail(_ session: Int) { streams[session - 1].finish(throwing: ObservationRecoveryFailure.observation) }
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        if pausesNextSnapshot {
            pausesNextSnapshot = false
            return await withCheckedContinuation {
                pendingSnapshot = $0
                pausedSnapshotWaiter?.resume()
                pausedSnapshotWaiter = nil
            }
        }
        if let freshSnapshot { return freshSnapshot }
        throw ObservationRecoveryFailure.observation
    }
    func location(id: UUID) async throws -> SavedLocation? {
        if pausesNextLocation {
            pausesNextLocation = false
            return try await withCheckedThrowingContinuation {
                pendingLocation = $0
                pausedLocationWaiter?.resume()
                pausedLocationWaiter = nil
            }
        }
        return try freshLocation.get()
    }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        if let commit { return commit }
        throw ObservationRecoveryFailure.unexpectedOperation
    }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw ObservationRecoveryFailure.unexpectedOperation
    }
}

enum MapRecoverySelection: CaseIterable, Sendable { case savedPin, search, recenter }

/// AC-31/44/56, INV-09, D-03/20: failed reads recover in the same scene-owned map session.
@MainActor
struct MapObservationRecoveryTests {
    private func saved(id: UUID = UUID(), collectionID: UUID, latitude: Double = 10) throws -> SavedLocation {
        SavedLocation(id: id, collectionID: collectionID, placeIdentity: nil, source: .manualCoordinate,
            name: ObservationRecoveryFixture.placeName, displayName: nil, address: nil,
            coordinate: try Coordinate(latitude: latitude, longitude: 20), category: nil, notes: nil,
            assets: [], isFavorite: false, createdAt: ObservationRecoveryFixture.date,
            updatedAt: ObservationRecoveryFixture.date, revision: 1)
    }
    private func snapshot(collectionID: UUID, locations: [SavedLocation], revision: Int64) -> LocationLibrarySnapshot {
        LocationLibrarySnapshot(collections: ObservationRecoveryFixture.snapshot(id: collectionID,
            name: ObservationRecoveryFixture.collectionName, revision: revision).collections,
            locations: locations, libraryRevision: revision)
    }
    private func model(repository: ObservationRecoveryMapRepository, scope: UUID) -> MapViewModel {
        MapViewModel(deviceLocationService: ObservationRecoveryPosition(), locationRepository: repository,
                     scopeCollectionID: scope)
    }

    @Test func failedStreamRetryPreservesSelectionCameraAndScope() async throws {
        let repository = ObservationRecoveryMapRepository()
        let scope = UUID()
        let record = try saved(collectionID: scope)
        let model = model(repository: repository, scope: scope)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, locations: [record], revision: 1))
        model.selectSavedLocation(record.id)
        let camera = try #require(model.cameraPosition.region)
        let pins = model.annotationGroups
        let first = Task { await model.observeSavedLocations() }
        await repository.waitForRegistration(1)
        await repository.fail(1)
        await first.value
        #expect(model.libraryLoadFailed)
        let oldRequest = model.libraryObservationRequestID
        model.retryLibraryLoading()
        #expect(model.libraryObservationRequestID != oldRequest)
        let retry = Task { await model.observeSavedLocations() }
        await repository.waitForRegistration(2)
        await repository.send(snapshot(collectionID: scope, locations: [record], revision: 2), session: 2)
        await repository.finish(2)
        await retry.value
        #expect(!model.libraryLoadFailed)
        #expect(model.scopeCollectionID == scope)
        #expect(model.selectedSavedLocation == record)
        #expect(model.annotationGroups == pins)
        #expect(model.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == camera.center.longitude)
        #expect(model.cameraPosition.region?.span.latitudeDelta == camera.span.latitudeDelta)
        #expect(model.cameraPosition.region?.span.longitudeDelta == camera.span.longitudeDelta)
    }

    @Test func obsoleteStreamCannotPublishAfterRetryRequest() async throws {
        let repository = ObservationRecoveryMapRepository()
        let scope = UUID()
        let record = try saved(collectionID: scope)
        let model = model(repository: repository, scope: scope)
        let first = Task { await model.observeSavedLocations() }
        await repository.waitForRegistration(1)
        model.retryLibraryLoading()
        await repository.send(snapshot(collectionID: scope, locations: [record], revision: 99), session: 1)
        await repository.fail(1)
        await first.value
        #expect(model.savedLocations.isEmpty)
        #expect(!model.libraryLoadFailed)
        let retry = Task { await model.observeSavedLocations() }
        await repository.waitForRegistration(2)
        await repository.send(snapshot(collectionID: scope, locations: [record], revision: 2), session: 2)
        await repository.finish(2)
        await retry.value
        #expect(model.savedLocations == [record])
        #expect(model.libraryRevision == 2)
    }

    @Test func newerRetryRejectsOldFreshReadBeforeStructuredTaskCancellation() async throws {
        let repository = ObservationRecoveryMapRepository()
        let scope = UUID()
        let existing = try saved(collectionID: scope)
        let target = try saved(collectionID: scope, latitude: 30)
        let model = model(repository: repository, scope: scope)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, locations: [existing], revision: 1))
        model.selectSavedLocation(existing.id)
        await model.resolveSavedLocationRequest(id: target.id)
        #expect(model.libraryLoadFailed)
        let event = model.unavailableSavedLocationEvent
        await repository.pauseNextSnapshotRead()
        model.retryLibraryLoading()
        let obsolete = Task { await model.observeSavedLocations() }
        await repository.waitForPausedSnapshot()
        model.retryLibraryLoading()
        await repository.resumeSnapshot(snapshot(collectionID: scope, locations: [existing], revision: 99))
        await obsolete.value
        #expect(model.libraryRevision == 1)
        #expect(model.selectedSavedLocation == existing)
        #expect(model.unavailableSavedLocationEvent == event)
        #expect(model.libraryLoadFailed)
        await repository.setFreshSnapshot(snapshot(collectionID: scope, locations: [existing, target], revision: 2))
        let retry = Task { await model.observeSavedLocations() }
        await repository.waitForRegistration(1)
        await repository.finish(1)
        await retry.value
        #expect(model.selectedSavedLocation == target)
        #expect(model.libraryRevision == 2)
        #expect(!model.libraryLoadFailed)
    }

    @Test(arguments: [false, true])
    func failedExplicitTargetRecoversOrReportsMissingOnFreshObservation(missing: Bool) async throws {
        let repository = ObservationRecoveryMapRepository()
        let scope = UUID()
        let existing = try saved(collectionID: scope)
        let target = try saved(collectionID: scope, latitude: 30)
        let model = model(repository: repository, scope: scope)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, locations: [existing], revision: 1))
        model.selectSavedLocation(existing.id)
        let event = model.unavailableSavedLocationEvent
        let buffered = Task { await model.observeSavedLocations() }
        await repository.waitForRegistration(1)
        await model.resolveSavedLocationRequest(id: target.id)
        #expect(model.libraryLoadFailed)
        #expect(model.selectedSavedLocation == existing)
        // A buffered projection cannot settle an explicit request whose fresh read failed.
        await repository.send(snapshot(collectionID: scope, locations: [existing], revision: 1), session: 1)
        await repository.finish(1)
        await buffered.value
        #expect(model.libraryLoadFailed)
        #expect(model.unavailableSavedLocationEvent == event)
        await repository.setFreshSnapshot(snapshot(collectionID: scope,
            locations: missing ? [existing] : [existing, target], revision: 2))
        model.retryLibraryLoading()
        let retry = Task { await model.observeSavedLocations() }
        await repository.waitForRegistration(2)
        await repository.send(snapshot(collectionID: scope,
            locations: missing ? [existing] : [existing, target], revision: 2), session: 2)
        await repository.finish(2)
        await retry.value
        #expect(!model.libraryLoadFailed)
        #expect(model.selectedSavedLocation == (missing ? existing : target))
        #expect(model.unavailableSavedLocationEvent == event + (missing ? 1 : 0))
    }

    @Test(arguments: MapRecoverySelection.allCases)
    func newerUserSelectionSupersedesFailedExplicitTarget(selection: MapRecoverySelection) async throws {
        let repository = ObservationRecoveryMapRepository()
        let scope = UUID()
        let existing = try saved(collectionID: scope)
        let target = try saved(collectionID: scope, latitude: 30)
        let model = model(repository: repository, scope: scope)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, locations: [existing], revision: 1))
        model.selectSavedLocation(existing.id)
        await model.resolveSavedLocationRequest(id: target.id)
        #expect(model.libraryLoadFailed)
        let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: ObservationRecoveryFixture.placeName, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 40, longitude: 50))
        switch selection {
        case .savedPin: model.selectSavedLocation(existing.id)
        case .search: model.selectSearchCandidate(candidate)
        case .recenter:
            _ = await model.activate()
            model.requestRecenter()
            #expect(model.hasPendingRecenterRequest)
        }
        let chosen = model.visiblePlace
        let focus = model.locationFocus
        let event = model.unavailableSavedLocationEvent
        model.retryLibraryLoading()
        let retry = Task { await model.observeSavedLocations() }
        await repository.waitForRegistration(1)
        await repository.send(snapshot(collectionID: scope, locations: [existing, target], revision: 2), session: 1)
        await repository.finish(1)
        await retry.value
        #expect(!model.libraryLoadFailed)
        #expect(model.selectedSavedLocation?.id != target.id)
        #expect(model.visiblePlace == chosen)
        #expect(model.locationFocus == focus)
        #expect(model.unavailableSavedLocationEvent == event)
        model.deactivate()
    }


    /// AC-44/47, INV-09: receipt errors remain relevant only while that receipt is retained.
    @Test func replacingFailedOutOfScopeReceiptHidesItsStaleError() async throws {
        let repository = ObservationRecoveryMapRepository()
        let scope = UUID()
        let other = UUID()
        let existing = try saved(collectionID: scope)
        let model = MapViewModel(deviceLocationService: ObservationRecoveryPosition(),
            locationRepository: repository, collectionRepository: ObservationRecoveryCollections(),
            scopeCollectionID: scope)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, locations: [existing], revision: 1))
        let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: ObservationRecoveryFixture.placeName, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 40, longitude: 50))
        model.selectSearchCandidate(candidate)
        model.prepareCapture(fallbackName: ObservationRecoveryFixture.placeName)
        let capture = try #require(model.capture)
        capture.destinationCollectionID = other
        let receipt = try saved(id: capture.id, collectionID: other, latitude: 40)
        await repository.setCommit(LocationCommit(location: receipt, libraryRevision: 2))
        await capture.save()
        #expect(capture.commit?.location == receipt)
        model.acceptCaptureCommit(capture)
        await model.refreshCommittedReceipt(expectedLibraryRevision: 2)
        #expect(model.libraryLoadFailed)
        model.selectSavedLocation(existing.id)
        #expect(model.libraryLoadFailed)
        #expect(model.retainedReceiptID == receipt.id)
        model.selectSearchCandidate(candidate)
        #expect(model.retainedReceiptID == nil)
        #expect(!model.libraryLoadFailed)
    }

    /// AC-44/47, INV-09, D-03: retry invalidates receipt reads before task cancellation arrives.
    @Test(arguments: [false, true])
    func newerRetryRejectsObsoleteReceiptReadWithoutTaskCancellation(missing: Bool) async throws {
        let repository = ObservationRecoveryMapRepository()
        let scope = UUID()
        let other = UUID()
        let model = MapViewModel(deviceLocationService: ObservationRecoveryPosition(),
            locationRepository: repository, collectionRepository: ObservationRecoveryCollections(),
            scopeCollectionID: scope)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, locations: [], revision: 1))
        let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: ObservationRecoveryFixture.placeName, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 40, longitude: 50))
        model.selectSearchCandidate(candidate)
        model.prepareCapture(fallbackName: ObservationRecoveryFixture.placeName)
        let capture = try #require(model.capture)
        capture.destinationCollectionID = other
        let receipt = try saved(id: capture.id, collectionID: other, latitude: 40)
        await repository.setCommit(LocationCommit(location: receipt, libraryRevision: 2))
        await capture.save()
        #expect(capture.commit?.location == receipt)
        model.acceptCaptureCommit(capture)
        model.showDetails()
        let detail = try #require(model.selectedDetail)
        let event = model.unavailableSavedLocationEvent
        let failure = model.libraryLoadFailed
        let camera = model.cameraPosition.region
        await repository.pauseNextLocationRead()
        let obsolete = Task { await model.refreshCommittedReceipt(expectedLibraryRevision: 2) }
        await repository.waitForPausedLocation()
        model.retryLibraryLoading()
        await repository.resumeLocation(missing: missing)
        await obsolete.value
        #expect(model.retainedReceiptID == receipt.id)
        #expect(model.selectedDetail == detail)
        #expect(model.unavailableSavedLocationEvent == event)
        #expect(model.libraryLoadFailed == failure)
        #expect(model.cameraPosition.region?.center.latitude == camera?.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == camera?.center.longitude)
        await repository.setFreshLocation(nil)
        await model.refreshCommittedReceipt(expectedLibraryRevision: 2)
        #expect(model.retainedReceiptID == nil)
        #expect(model.selectedDetail == nil)
        #expect(model.unavailableSavedLocationEvent == event + 1)
        #expect(!model.libraryLoadFailed)
    }

    /// AC-31/56/65: overlapping independent records keep their exact owning-collection metadata.
    @Test func annotationProjectionKeepsMetadataAcrossCollectionReordering() throws {
        let scope = UUID()
        let otherID = UUID()
        let first = try saved(collectionID: scope)
        let second = try saved(collectionID: otherID)
        let firstSummary = CollectionSummary(collection: Collection(id: scope,
            name: ObservationRecoveryFixture.collectionName, isDefault: true,
            createdAt: ObservationRecoveryFixture.date, updatedAt: ObservationRecoveryFixture.date, revision: 1),
            locationCount: 8)
        let otherSummary = CollectionSummary(collection: Collection(id: otherID,
            name: ObservationRecoveryFixture.updatedName, isDefault: false,
            createdAt: ObservationRecoveryFixture.date, updatedAt: ObservationRecoveryFixture.date, revision: 1),
            locationCount: 13)
        let model = MapViewModel(deviceLocationService: ObservationRecoveryPosition())
        model.applyLibrarySnapshot(LocationLibrarySnapshot(collections: [otherSummary, firstSummary],
            locations: [first, second], libraryRevision: 1))
        let records = Dictionary(uniqueKeysWithValues: model.annotationGroups.flatMap(\.records).map { ($0.id, $0) })
        #expect(model.annotationGroups.count == 1)
        #expect(records[first.id] == MapSavedPinRecord(id: first.id, title: first.name,
            collectionName: firstSummary.collection.name, createdAt: first.createdAt,
            collectionIsDefault: true, collectionLocationCount: 8))
        #expect(records[second.id] == MapSavedPinRecord(id: second.id, title: second.name,
            collectionName: otherSummary.collection.name, createdAt: second.createdAt,
            collectionIsDefault: false, collectionLocationCount: 13))
        let groups = model.annotationGroups
        model.applyLibrarySnapshot(LocationLibrarySnapshot(collections: [firstSummary, otherSummary],
            locations: [second, first], libraryRevision: 2))
        #expect(model.annotationGroups == groups)
    }
}
