//
//  CollectionMapTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import CoreLocation
import Foundation
import MapKit
import QuartzCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import ProjectAlpha

private enum CollectionMapFixture {
    static let collectionName = "Collection A"
    static let otherName = "Collection B"
    static let visibleName = "Visible museum"
    static let hiddenName = "Hidden cafe"
    static let customName = "My custom museum name"
    static let date = Date(timeIntervalSince1970: 100)
    static let firstID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let secondID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    static let thirdID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
    static let portraitSize = CGSize(width: 390, height: 844)
    static let landscapeSize = CGSize(width: 844, height: 390)
    static let frameTolerance: CGFloat = 1
    static let resizeDiagnostic = "pass=%ld size=%@ selected=%@ offset=%@ contentSize=%@ insets=%@ viewport=%@ card=%@"
}

enum CollectionMapBookkeeping: CaseIterable, Sendable {
    case optionalNil
    case emptyFeature
    case inactive
    case sameSelection
}

enum CollectionCarouselOutcome: CaseIterable, Sendable {
    case settleOnSecond
    case cancelAtFirst
    case newerPinSelection
    case targetDeleted
}

enum CollectionTemporarySource: CaseIterable, Sendable {
    case currentPosition, search, nativePOI
}

private struct NoCollectionMapPosition: DeviceLocationService {
    func authorization() async -> LocationAuthorization {
        LocationAuthorization(status: .denied, accuracy: .full, servicesEnabled: true)
    }
    func currentPosition() async throws(LocationServiceError) -> DevicePosition { throw .permissionDenied }
}

/// AC-31/56/58, D-03/08 and INV-09: complete collection scope and independently retained map sessions.
@MainActor
struct CollectionMapTests {
    /// AC-24/56/58, D-03/D-17, INV-09: resizing the actual carousel must keep
    /// the whole selected card inside its viewport, including middle/end items.
    /// This hosted geometry regression does not establish device rotation,
    /// RTL, legal-attribution clearance or first-frame animation acceptance.
    @Test(.serialized, arguments: [CollectionMapFixture.firstID, CollectionMapFixture.secondID, CollectionMapFixture.thirdID])
    func selectedCardRemainsFullyInsideHostedViewportAfterRepeatedResizes(selectedID: UUID) async throws {
        let scope = UUID()
        let records = try [CollectionMapFixture.firstID, CollectionMapFixture.secondID, CollectionMapFixture.thirdID]
            .map { try saved(id: $0, collectionID: scope) }
        let model = MapViewModel(deviceLocationService: NoCollectionMapPosition(),
                                 scopeCollectionID: scope, initialLocationID: selectedID)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: UUID(), locations: records))
        let selectedIndex = try #require(model.savedLocations.firstIndex { $0.id == selectedID })
        let camera = try #require(model.cameraPosition.region)
        let initialFocus = model.locationFocus
        let root = MapView(viewModel: model, rendersLiveMap: false)
            .environment(AppPreferences(store: CarouselResizePreferences()))
            .environment(SceneCoordinator())
            .environment(DSToastManager())
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.dynamicTypeSize, .large)
            .ignoresSafeArea()
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        let host = UIHostingController(rootView: root)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for (pass, size) in [CollectionMapFixture.portraitSize, CollectionMapFixture.landscapeSize,
                     CollectionMapFixture.portraitSize, CollectionMapFixture.landscapeSize,
                     CollectionMapFixture.portraitSize].enumerated() {
            window.frame = CGRect(origin: .zero, size: size)
            host.view.frame = window.bounds
            // Await the render transaction's completion rather than assuming a
            // fixed number of layout passes settles geometry and scroll state.
            await withCheckedContinuation { continuation in
                CATransaction.begin()
                CATransaction.setCompletionBlock { continuation.resume() }
                window.setNeedsLayout()
                window.layoutIfNeeded()
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                _ = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                CATransaction.commit()
            }
            let scrollViews = carouselScrollViews(in: host.view)
            #expect(scrollViews.count == 1)
            let scroll = try #require(scrollViews.first)
            let layout = MapCardLayout(size: size, regularWidth: false, leadingIsPhysicalLeft: true)
            let itemWidth = layout.carouselCardWidth(itemCount: records.count)
            let contentWidth = CGFloat(records.count) * itemWidth
                + CGFloat(records.count - 1) * MapCarouselMetrics.spacing
            // SwiftUI may express symmetric resting margins as either content
            // insets or content size. The actual content extent handles both.
            let contentMargin = max(0, (scroll.contentSize.width - contentWidth) / 2)
            let card = CGRect(x: contentMargin + CGFloat(selectedIndex) * (itemWidth + MapCarouselMetrics.spacing),
                              y: 0, width: itemWidth, height: scroll.bounds.height)
            let visibleCard = scroll.convert(card, to: host.view)
            let viewport = scroll.convert(scroll.bounds, to: host.view)
            let diagnostic = Comment(rawValue: String(format: CollectionMapFixture.resizeDiagnostic,
                pass, String(describing: size), selectedID.uuidString,
                String(describing: scroll.contentOffset), String(describing: scroll.contentSize),
                String(describing: scroll.adjustedContentInset), String(describing: viewport),
                String(describing: visibleCard)))
            #expect(abs(viewport.width - layout.carouselViewportWidth) <= CollectionMapFixture.frameTolerance, diagnostic)
            #expect(visibleCard.minX >= viewport.minX - CollectionMapFixture.frameTolerance, diagnostic)
            #expect(visibleCard.maxX <= viewport.maxX + CollectionMapFixture.frameTolerance, diagnostic)
            #expect(host.view.bounds.insetBy(dx: -CollectionMapFixture.frameTolerance,
                                           dy: -CollectionMapFixture.frameTolerance).contains(viewport))
            #expect(model.selectedSavedLocation?.id == selectedID)
            #expect(model.scopeCollectionID == scope)
            #expect(model.locationFocus == initialFocus)
            let resizedCamera = try #require(model.cameraPosition.region)
            #expect(resizedCamera.center.latitude == camera.center.latitude)
            #expect(resizedCamera.center.longitude == camera.center.longitude)
            #expect(resizedCamera.span.latitudeDelta == camera.span.latitudeDelta)
            #expect(resizedCamera.span.longitudeDelta == camera.span.longitudeDelta)
        }
    }

    private func carouselScrollViews(in view: UIView) -> [UIScrollView] {
        let current = (view as? UIScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap { carouselScrollViews(in: $0) }
    }

    /// AC-37/56: authorized collection entry enriches distance without replacing the saved selection/camera.
    @Test(arguments: [LocationAuthorizationStatus.authorizedWhenInUse, .authorizedAlways])
    func authorizedEntryAcquiresOriginWithoutRecentering(status: LocationAuthorizationStatus) async throws {
        let scope = UUID()
        let record = try saved(collectionID: scope)
        let positions = MapPresentationLocationService(status: status)
        let position = try DevicePosition(coordinate: Coordinate(latitude: 30, longitude: 40),
            timestamp: CollectionMapFixture.date, horizontalAccuracyMetres: 5,
            authorization: MapPresentationLocationService.allowed)
        positions.immediateResult = .success(position)
        let routes = CollectionPagingRoutes()
        let model = MapViewModel(deviceLocationService: positions, routeEstimationService: routes,
                                 scopeCollectionID: scope, initialLocationID: record.id)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: UUID(), locations: [record]))
        let camera = try #require(model.cameraPosition.region)
        model.showDetails()
        #expect(await model.activate() == nil)
        await model.route.awaitPendingEstimate()
        #expect(positions.positionCalls == 1)
        #expect(model.currentPosition == position)
        #expect(model.selectedSavedLocation?.id == record.id)
        #expect(model.selectedDetail?.id == .savedLocation(record.id))
        #expect(model.collectionTemporaryPlace == nil)
        #expect(model.locationFocus == nil)
        #expect(model.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == camera.center.longitude)
        #expect(model.cameraPosition.region?.span.latitudeDelta == camera.span.latitudeDelta)
        #expect(await routes.requests.map(\.destination.savedLocationID) == [record.id])
        guard case .unavailable(let distance, _) = model.route.state else { Issue.record(); return }
        #expect(distance > 0)
        model.deactivate()
        #expect(await model.activate() == nil)
        #expect(positions.positionCalls == 1)
        model.deactivate()
    }

    @Test func passiveOriginBeforeLibraryNeverCreatesCurrentPositionCard() async throws {
        let scope = UUID()
        let record = try saved(collectionID: scope)
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        positions.immediateResult = .success(try DevicePosition(
            coordinate: Coordinate(latitude: 30, longitude: 40), timestamp: CollectionMapFixture.date,
            horizontalAccuracyMetres: 5, authorization: MapPresentationLocationService.allowed))
        let model = MapViewModel(deviceLocationService: positions, scopeCollectionID: scope,
                                 initialLocationID: record.id)
        #expect(await model.activate() == nil)
        #expect(model.currentPosition != nil)
        #expect(model.visiblePlace == nil)
        #expect(model.collectionTemporaryPlace == nil)
        #expect(model.collectionCardPlaces.isEmpty)
        #expect(model.locationFocus == nil)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: UUID(), locations: [record]))
        #expect(model.visiblePlace?.id == .savedLocation(record.id))
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: UUID(), locations: [], revision: 2))
        #expect(model.currentPosition != nil)
        #expect(model.visiblePlace == nil)
        #expect(model.collectionTemporaryPlace == nil)
        model.deactivate()
    }

    /// Library observation and origin acquisition are separate lifecycle tasks in MapView.
    @Test(arguments: [false, true])
    func passiveOriginSurvivesLateLibraryAndSavedSelection(showAll: Bool) async throws {
        let scope = UUID()
        let first = try saved(id: CollectionMapFixture.firstID, collectionID: scope)
        let second = try saved(id: CollectionMapFixture.secondID, collectionID: scope, latitude: 11)
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        let routes = CollectionPagingRoutes()
        let model = MapViewModel(deviceLocationService: positions, routeEstimationService: routes,
            scopeCollectionID: scope, initialLocationID: showAll ? nil : first.id)
        let acquisition = Task { await model.activate() }
        await positions.waitForPositionRequest(1)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: UUID(), locations: [first, second]))
        model.selectSavedLocation(second.id)
        let camera = try #require(model.cameraPosition.region)
        #expect(model.isAcquiringLocation)
        let position = try DevicePosition(coordinate: Coordinate(latitude: 30, longitude: 40),
            timestamp: CollectionMapFixture.date, horizontalAccuracyMetres: 5,
            authorization: MapPresentationLocationService.allowed)
        positions.complete(1, with: .success(position))
        #expect(await acquisition.value == nil)
        await model.route.awaitPendingEstimate()
        #expect(model.currentPosition == position)
        #expect(model.selectedSavedLocation?.id == second.id)
        #expect(model.locationFocus == nil)
        #expect(model.cameraPosition.region?.center.latitude == camera.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == camera.center.longitude)
        #expect(await routes.requests.map(\.destination.savedLocationID) == [second.id])
        #expect(!model.isAcquiringLocation)
        model.deactivate()
    }

    @Test func passiveOriginRejectsCompletionAfterDeactivation() async throws {
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        let model = MapViewModel(deviceLocationService: positions, scopeCollectionID: UUID())
        let acquisition = Task { await model.activate() }
        await positions.waitForPositionRequest(1)
        model.deactivate()
        let position = try DevicePosition(coordinate: Coordinate(latitude: 30, longitude: 40),
            timestamp: CollectionMapFixture.date, horizontalAccuracyMetres: 5,
            authorization: MapPresentationLocationService.allowed)
        positions.complete(1, with: .success(position))
        #expect(await acquisition.value == nil)
        #expect(model.currentPosition == nil)
        #expect(!model.isAcquiringLocation)
        #expect(!model.showsUserLocation)
    }

    @Test(arguments: [LocationAuthorizationStatus.denied, .restricted, .notDetermined])
    func passiveEntryWithoutPermissionIsSilentAndNeverRequestsPosition(status: LocationAuthorizationStatus) async {
        let positions = MapPresentationLocationService(status: status)
        let model = MapViewModel(deviceLocationService: positions, scopeCollectionID: UUID())
        #expect(await model.activate() == nil)
        #expect(positions.positionCalls == 0)
        #expect(model.currentPosition == nil)
        #expect(!model.showsUserLocation)
        #expect(!model.isLocating)
        model.deactivate()
    }

    @Test func passiveEntryWithDisabledServicesIsSilent() async {
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse, servicesEnabled: false)
        let model = MapViewModel(deviceLocationService: positions, scopeCollectionID: UUID())
        #expect(await model.activate() == nil)
        #expect(positions.positionCalls == 0)
        #expect(model.currentPosition == nil)
        model.deactivate()
    }

    @Test(arguments: [LocationServiceError.timedOut, .positionUnavailable, .invalidPosition,
                      .permissionDenied, .permissionRestricted, .servicesDisabled, .authorizationRequired, .cancelled])
    func passiveAcquisitionFailuresAreSilent(error: LocationServiceError) async throws {
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        positions.immediateResult = .failure(error)
        let scope = UUID()
        let record = try saved(collectionID: scope)
        let routes = CollectionPagingRoutes()
        let model = MapViewModel(deviceLocationService: positions, routeEstimationService: routes,
                                 scopeCollectionID: scope, initialLocationID: record.id)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: UUID(), locations: [record]))
        #expect(await model.activate() == nil)
        #expect(positions.positionCalls == 1)
        #expect(model.currentPosition == nil)
        #expect(model.selectedSavedLocation?.id == record.id)
        #expect(model.route.state == .noOrigin)
        #expect(await routes.requests.isEmpty)
        #expect(!model.isLocating)
        model.deactivate()
    }

    @Test func explicitDeniedLocationStillReturnsPermissionAlert() async {
        let positions = MapPresentationLocationService(status: .denied)
        let model = MapViewModel(deviceLocationService: positions, scopeCollectionID: UUID())
        #expect(await model.activate() == nil)
        #expect(await model.recenter() == .permissionDenied)
        #expect(positions.positionCalls == 0)
        model.deactivate()
    }

    @Test func explicitLocationCanRequestPreviouslyUndeterminedPermission() async throws {
        let positions = MapPresentationLocationService(status: .notDetermined)
        positions.authorizationAfterRequest = MapPresentationLocationService.allowed
        positions.immediateResult = .success(try DevicePosition(
            coordinate: Coordinate(latitude: 30, longitude: 40), timestamp: CollectionMapFixture.date,
            horizontalAccuracyMetres: 5, authorization: MapPresentationLocationService.allowed))
        let model = MapViewModel(deviceLocationService: positions, scopeCollectionID: UUID())
        #expect(await model.activate() == nil)
        #expect(positions.positionCalls == 0)
        #expect(await model.recenter() == nil)
        #expect(positions.positionCalls == 1)
        #expect(model.visiblePlace?.id == .currentPosition)
        #expect(model.locationFocus?.coordinate == model.currentPosition?.coordinate)
        model.deactivate()
    }

    /// AC-24/56: one transient card precedes the complete list and survives saved-card paging.
    @Test(arguments: CollectionTemporarySource.allCases)
    func temporaryCardPagesWithSavedLocationsAndCloseReturnsToFirst(source: CollectionTemporarySource) async throws {
        let scope = UUID()
        let first = try saved(id: CollectionMapFixture.firstID, collectionID: scope, createdOffset: 1)
        let second = try saved(id: CollectionMapFixture.secondID, collectionID: scope)
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        let position = try DevicePosition(coordinate: Coordinate(latitude: 30, longitude: 40),
            timestamp: CollectionMapFixture.date, horizontalAccuracyMetres: 5,
            authorization: MapPresentationLocationService.allowed)
        positions.immediateResult = .success(position)
        let model = MapViewModel(deviceLocationService: positions, scopeCollectionID: scope,
                                 initialLocationID: second.id)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: UUID(), locations: [second, first]))
        #expect(await model.activate() == nil)
        let candidate = PlaceCandidate(id: UUID(), source: .appleMaps, placeIdentity: nil,
            name: CollectionMapFixture.visibleName, address: nil, category: nil, coordinate: position.coordinate)
        switch source {
        case .currentPosition: #expect(await model.recenter() == nil)
        case .search: model.selectSearchCandidate(candidate)
        case .nativePOI:
            model.updateMapSelection(MapSelection(candidate.id))
            let task = model.beginMapFeatureSelection { candidate }
            await task?.value
        }
        let temporary = try #require(model.collectionTemporaryPlace)
        let layout = MapCardLayout(size: CGSize(width: 700, height: 400), regularWidth: false,
                                   leadingIsPhysicalLeft: true)
        let temporaryWidth = layout.carouselCardWidth(itemCount: model.collectionCardPlaces.count)
        #expect(temporaryWidth < layout.cardWidth)
        #expect(model.collectionCardPlaces.map(\.id) == [temporary.id, .savedLocation(first.id), .savedLocation(second.id)])
        #expect(model.visiblePlace?.id == temporary.id)
        #expect(model.selectedPageIndex == 0)
        #expect(!model.canPagePrevious)
        #expect(model.showsClose(for: temporary))
        #expect(!model.showsClose(for: model.quickPlace(for: first)))
        model.pageSelection(by: 1)
        #expect(model.selectedSavedLocation?.id == first.id)
        #expect(layout.carouselCardWidth(itemCount: model.collectionCardPlaces.count) == temporaryWidth)
        #expect(model.collectionTemporaryPlace == temporary)
        model.pageSelection(by: -1)
        #expect(model.visiblePlace?.id == temporary.id)
        #expect(model.selectedSavedLocation == nil)
        #expect(layout.carouselCardWidth(itemCount: model.collectionCardPlaces.count) == temporaryWidth)
        if source == .nativePOI {
            #expect(model.mapSelection == MapSelection(candidate.id))
            #expect(model.candidateForCustomAnnotation == nil)
            model.updateMapSelection(nil)
            model.selectSavedLocation(first.id)
            model.selectCollectionCard(temporary.id)
            model.showDetails()
            model.deactivate()
            #expect(await model.activate() == nil)
            #expect(model.mapSelection == nil)
            model.selectedDetail = nil
        }
        #expect(positions.positionCalls == (source == .currentPosition ? 2 : 1))
        model.pageSelection(by: 1)
        model.pageSelection(by: 1)
        #expect(model.selectedSavedLocation?.id == second.id)
        #expect(!model.canPageNext)
        model.selectCollectionCard(temporary.id)
        model.dismissSearchCandidate()
        #expect(model.collectionTemporaryPlace == nil)
        #expect(model.collectionCardPlaces.map(\.id) == [.savedLocation(first.id), .savedLocation(second.id)])
        #expect(model.selectedSavedLocation?.id == first.id)
        #expect(model.cameraPosition.region?.center.latitude == first.coordinate.latitude)
        #expect(model.cameraPosition.region?.center.longitude == first.coordinate.longitude)
        #expect(model.scopeCollectionID == scope)
        #expect(model.libraryRevision == 1)
        #expect(!model.showsClose(for: try #require(model.visiblePlace)))
        model.deactivate()
    }

    @Test func newerCandidateReplacesTemporaryCardAndFitAllClearsIt() throws {
        let scope = UUID()
        let record = try saved(collectionID: scope)
        let model = MapViewModel(deviceLocationService: NoCollectionMapPosition(), scopeCollectionID: scope,
                                 initialLocationID: record.id)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: UUID(), locations: [record]))
        let old = PlaceCandidate(id: UUID(), source: .appleMaps, placeIdentity: nil,
            name: CollectionMapFixture.visibleName, address: nil, category: nil, coordinate: record.coordinate)
        let replacement = PlaceCandidate(id: UUID(), source: .appleMaps, placeIdentity: nil,
            name: CollectionMapFixture.hiddenName, address: nil, category: nil, coordinate: record.coordinate)
        model.selectSearchCandidate(old)
        model.selectSavedLocation(record.id)
        model.selectSearchCandidate(replacement)
        #expect(model.collectionCardPlaces.map(\.id) == [.searchCandidate(replacement.id), .savedLocation(record.id)])
        let layout = MapCardLayout(size: CGSize(width: 400, height: 700), regularWidth: false,
                                   leadingIsPhysicalLeft: true)
        #expect(layout.carouselCardWidth(itemCount: model.collectionCardPlaces.count) < layout.cardWidth)
        model.selectCollectionCard(.searchCandidate(old.id))
        #expect(model.visiblePlace?.id == .searchCandidate(replacement.id))
        model.fitAll()
        #expect(model.collectionTemporaryPlace == nil)
        #expect(model.visiblePlace == nil)
    }

    private func saved(id: UUID = UUID(), collectionID: UUID, latitude: Double = 10,
                       longitude: Double = 20, createdOffset: Double = 0,
                       displayName: String? = nil) throws -> SavedLocation {
        SavedLocation(id: id, collectionID: collectionID, placeIdentity: nil, source: .manualCoordinate,
            name: id == CollectionMapFixture.firstID ? CollectionMapFixture.visibleName : CollectionMapFixture.hiddenName,
            displayName: displayName, address: nil, coordinate: try Coordinate(latitude: latitude, longitude: longitude),
            category: nil, notes: nil, assets: [], isFavorite: false,
            createdAt: CollectionMapFixture.date.addingTimeInterval(createdOffset),
            updatedAt: CollectionMapFixture.date, revision: 1)
    }
    private func snapshot(collectionID: UUID, otherID: UUID, locations: [SavedLocation],
                          revision: Int64 = 1) -> LocationLibrarySnapshot {
        let summaries = [collectionID, otherID].map { id in
            CollectionSummary(collection: Collection(id: id,
                name: id == collectionID ? CollectionMapFixture.collectionName : CollectionMapFixture.otherName,
                isDefault: id == otherID, createdAt: CollectionMapFixture.date,
                updatedAt: CollectionMapFixture.date, revision: 1),
                locationCount: locations.filter { $0.collectionID == id }.count)
        }
        return LocationLibrarySnapshot(collections: summaries, locations: locations, libraryRevision: revision)
    }

    /// AC-24/56: both map scopes label saved pins with Name even when Custom Name exists.
    @Test(arguments: [false, true])
    func savedMarkerUsesNameWhileCardKeepsCustomName(collectionScoped: Bool) throws {
        let scope = CollectionMapFixture.firstID
        let other = CollectionMapFixture.secondID
        let location = try saved(id: CollectionMapFixture.firstID, collectionID: scope,
                                 displayName: CollectionMapFixture.customName)
        let model = MapViewModel(deviceLocationService: NoCollectionMapPosition(),
                                 scopeCollectionID: collectionScoped ? scope : nil)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other, locations: [location]))
        let record = try #require(model.annotationGroups.first?.records.first)
        #expect(record.title == CollectionMapFixture.visibleName)
        model.selectSavedLocation(location.id)
        #expect(model.visiblePlace?.name == CollectionMapFixture.customName)
        #expect(model.selectedSavedLocation?.displayName == CollectionMapFixture.customName)
    }

    /// J-03/AC-56: the row's selected ID is immediate, while full collection records page in stable list order.
    @Test func fullCollectionPagesInListOrderWithoutWrapOrCrossScopeRecords() throws {
        let scope = UUID()
        let other = UUID()
        let first = try saved(id: CollectionMapFixture.firstID, collectionID: scope)
        let second = try saved(id: CollectionMapFixture.secondID, collectionID: scope)
        let newest = try saved(collectionID: scope, createdOffset: 1)
        let unrelated = try saved(collectionID: other)
        let model = MapViewModel(deviceLocationService: NoCollectionMapPosition(), scopeCollectionID: scope,
                                 initialLocationID: first.id)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other,
                                             locations: [unrelated, second, first, newest]))
        #expect(model.savedLocations.map(\.id) == [newest.id, first.id, second.id])
        #expect(model.selectedSavedLocation?.id == first.id)
        #expect(model.selectedDetail == nil)
        #expect(model.selectedPageIndex == 1)
        model.pageSelection(by: 1)
        #expect(model.selectedSavedLocation?.id == second.id)
        #expect(!model.canPageNext)
        model.pageSelection(by: 1)
        #expect(model.selectedSavedLocation?.id == second.id)
        model.pageSelection(by: -1)
        model.pageSelection(by: -1)
        #expect(model.selectedSavedLocation?.id == newest.id)
        #expect(!model.canPagePrevious)
        model.pageSelection(by: -1)
        #expect(model.selectedSavedLocation?.id == newest.id)
        model.selectSavedLocation(unrelated.id)
        #expect(model.selectedSavedLocation?.id == newest.id)
    }

    /// AC-56: filtered list state survives map navigation while map scope uses every collection record.
    @Test func filteredListRetainsQueryWhileMapIncludesHiddenRecords() async throws {
        let container = try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
        let collections = SwiftDataCollectionRepository(store: LibraryStore(container: container))
        let scope = UUID()
        let other = UUID()
        let visible = try saved(id: CollectionMapFixture.firstID, collectionID: scope)
        let hidden = try saved(id: CollectionMapFixture.secondID, collectionID: scope)
        let data = snapshot(collectionID: scope, otherID: other, locations: [visible, hidden])
        let router = Router<HomeRoute>(root: .root)
        router.push(.collection(id: scope))
        let detail = CollectionDetailViewModel(collectionID: scope, repository: collections, router: router,
            locationRepository: FiniteCollectionMapRepository(value: data))
        await detail.observe()
        detail.query = CollectionMapFixture.visibleName
        #expect(detail.filteredLocations.map(\.id) == [visible.id])
        #expect(detail.collection?.locationCount == 2)
        router.push(.collectionMap(collectionID: scope, initialLocationID: visible.id))
        let map = MapViewModel(deviceLocationService: NoCollectionMapPosition(), scopeCollectionID: scope,
                               initialLocationID: visible.id)
        map.applyLibrarySnapshot(data)
        #expect(Set(map.savedLocations.map(\.id)) == Set([visible.id, hidden.id]))
        router.paths.removeLast()
        #expect(detail.query == CollectionMapFixture.visibleName)
        #expect(detail.filteredLocations.map(\.id) == [visible.id])
        #expect(router.paths == [.collection(id: scope)])
    }

    /// AC-31/58/INV-09: collection paging, Show All and stale observations cannot alter Global selection/camera.
    @Test func collectionAndGlobalStateRemainIndependentAndOlderDataCannotRestoreSelection() throws {
        let scope = UUID()
        let other = UUID()
        let first = try saved(collectionID: scope)
        let second = try saved(collectionID: scope, latitude: 12)
        let globalRecord = try saved(collectionID: other, latitude: 40)
        let data = snapshot(collectionID: scope, otherID: other, locations: [first, second, globalRecord], revision: 3)
        let global = MapViewModel(deviceLocationService: NoCollectionMapPosition())
        let scoped = MapViewModel(deviceLocationService: NoCollectionMapPosition(), scopeCollectionID: scope,
                                  initialLocationID: first.id)
        global.applyLibrarySnapshot(data)
        scoped.applyLibrarySnapshot(data)
        global.selectSavedLocation(globalRecord.id)
        let globalFocus = global.locationFocus
        let globalCamera = try #require(global.cameraPosition.region)
        scoped.selectSavedLocation(second.id)
        scoped.fitAll()
        #expect(scoped.selectedSavedLocation == nil)
        #expect(scoped.savedLocations.count == 2)
        #expect(global.selectedSavedLocation == globalRecord)
        #expect(global.locationFocus == globalFocus)
        #expect(global.cameraPosition.region?.center.latitude == globalCamera.center.latitude)
        #expect(global.cameraPosition.region?.center.longitude == globalCamera.center.longitude)
        scoped.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other, locations: [], revision: 2))
        #expect(scoped.savedLocations.count == 2)
        #expect(scoped.libraryRevision == 3)
    }

    /// AC-58/INV-09: the single presentation owner serializes dismissal/reopen without touching map identity.
    /// These are coordinator semantics; compact/regular rendering still requires device evidence.
    @Test func repeatedPresentationTransitionsRetainSelectedRecordAndRouteExactlyOnce() throws {
        let scope = UUID()
        let other = UUID()
        let place = try saved(collectionID: scope)
        let map = MapViewModel(deviceLocationService: NoCollectionMapPosition(), scopeCollectionID: scope,
                               initialLocationID: place.id)
        map.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other, locations: [place]))
        let presentation = MapPresentationState()
        let router = Router<HomeRoute>(root: .root)
        router.push(.collection(id: scope))
        router.push(.collectionMap(collectionID: scope, initialLocationID: place.id))
        let paths = router.paths
        for _ in 0..<5 {
            presentation.openMapDetail()
            presentation.openMapDetail()
            #expect(presentation.presentedMapSheet == .detail)
            presentation.openMapCollectionPicker()
            #expect(presentation.presentedMapSheet == nil)
            presentation.mapPresentationDidDismiss()
            #expect(presentation.presentedMapSheet == .collectionPicker)
            presentation.dismissMapPresentation()
            presentation.mapPresentationDidDismiss()
            #expect(presentation.presentedMapSheet == nil)
            #expect(map.selectedSavedLocation?.id == place.id)
            #expect(map.scopeCollectionID == scope)
            #expect(router.paths == paths)
        }
    }

    /// AC-43/54: paging estimates only settled selections, never every scoped card; detail and new data reuse the route.
    @Test func pagingRequestsRoutesOnlyForSelectedRecordsAndDetailReusesThem() async throws {
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        positions.immediateResult = .success(try DevicePosition(
            coordinate: Coordinate(latitude: 0, longitude: 0), timestamp: CollectionMapFixture.date,
            horizontalAccuracyMetres: 5, authorization: MapPresentationLocationService.allowed))
        let routes = CollectionPagingRoutes()
        let scope = UUID()
        let other = UUID()
        let first = try saved(id: CollectionMapFixture.firstID, collectionID: scope, latitude: 10)
        let second = try saved(id: CollectionMapFixture.secondID, collectionID: scope, latitude: 11)
        let third = try saved(id: CollectionMapFixture.thirdID, collectionID: scope, latitude: 12)
        let model = MapViewModel(deviceLocationService: positions, routeEstimationService: routes,
                                 scopeCollectionID: scope)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other, locations: [third, second, first]))
        #expect(await model.activate() == nil)
        #expect(positions.positionCalls == 1)
        model.selectSavedLocation(first.id)
        await model.route.awaitPendingEstimate()
        #expect(await routes.requests.map(\.destination.savedLocationID) == [first.id])
        model.pageSelection(by: 1)
        await model.route.awaitPendingEstimate()
        #expect(await routes.requests.map(\.destination.savedLocationID) == [first.id, second.id])
        model.showDetails()
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other,
                                             locations: [third, second, first], revision: 2))
        await model.route.awaitPendingEstimate()
        #expect(await routes.requests.map(\.destination.savedLocationID) == [first.id, second.id])
        #expect(model.selectedSavedLocation?.id == second.id)
        #expect(positions.positionCalls == 1)
        model.deactivate()
    }

    /// AC-43/54/58: rapid/reversed scroll targets are transient; only the settled surviving target changes selection and ETA.
    @Test(arguments: CollectionCarouselOutcome.allCases)
    func carouselIntermediateTargetsCannotSelectOrRequestRoutes(outcome: CollectionCarouselOutcome) async throws {
        let positions = MapPresentationLocationService(status: .authorizedWhenInUse)
        positions.immediateResult = .success(try DevicePosition(
            coordinate: Coordinate(latitude: 0, longitude: 0), timestamp: CollectionMapFixture.date,
            horizontalAccuracyMetres: 5, authorization: MapPresentationLocationService.allowed))
        let routes = CollectionPagingRoutes()
        let scope = UUID()
        let other = UUID()
        let first = try saved(id: CollectionMapFixture.firstID, collectionID: scope, latitude: 10)
        let second = try saved(id: CollectionMapFixture.secondID, collectionID: scope, latitude: 11)
        let third = try saved(id: CollectionMapFixture.thirdID, collectionID: scope, latitude: 12)
        let model = MapViewModel(deviceLocationService: positions, routeEstimationService: routes,
                                 scopeCollectionID: scope)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other, locations: [first, second, third]))
        #expect(await model.activate() == nil)
        model.selectSavedLocation(first.id)
        await model.route.awaitPendingEstimate()
        let initialCamera = model.locationFocus
        var carousel = MapCardCarouselSelection(targetID: first.id)
        for intermediateID in [second.id, third.id, second.id, first.id, second.id] {
            carousel.targetID = intermediateID
            let target = carousel.settledTarget(isScrolling: true, selectedID: model.selectedSavedLocation?.id)
            #expect(target == nil)
            if let target { model.selectSavedLocation(target) }
            await model.route.awaitPendingEstimate()
            #expect(model.selectedSavedLocation?.id == first.id)
            #expect(model.locationFocus == initialCamera)
            #expect(await routes.requests.map(\.destination.savedLocationID) == [first.id])
        }
        var expectedRoutes = [first.id]
        var expectedSelection = first.id
        switch outcome {
        case .settleOnSecond:
            expectedRoutes.append(second.id)
            expectedSelection = second.id
        case .cancelAtFirst:
            carousel.targetID = first.id
        case .newerPinSelection:
            model.selectSavedLocation(third.id)
            await model.route.awaitPendingEstimate()
            carousel.synchronize(selectedID: model.selectedSavedLocation?.id)
            expectedRoutes.append(third.id)
            expectedSelection = third.id
        case .targetDeleted:
            model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other,
                                                 locations: [first, third], revision: 2))
        }
        let settled = carousel.settledTarget(isScrolling: false, selectedID: model.selectedSavedLocation?.id)
        if outcome == .cancelAtFirst || outcome == .newerPinSelection { #expect(settled == nil) }
        if let settled { model.selectSavedLocation(settled) }
        await model.route.awaitPendingEstimate()
        #expect(model.selectedSavedLocation?.id == expectedSelection)
        #expect(await routes.requests.map(\.destination.savedLocationID) == expectedRoutes.map(Optional.some))
        #expect(positions.positionCalls == 1)
        model.deactivate()
    }

    /// AC-31/46/58: old observations cannot consume a pending explicit saved-place lookup;
    /// a newer user selection invalidates that lookup before its authoritative result arrives.
    @Test(arguments: [false, true])
    func suspendedSavedPlaceLookupWaitsForCurrentDataAndRespectsNewSelection(newCandidateWins: Bool) async throws {
        let scope = UUID()
        let other = UUID()
        let prior = try saved(id: CollectionMapFixture.firstID, collectionID: scope)
        let requested = try saved(id: CollectionMapFixture.secondID, collectionID: scope, latitude: 11)
        let oldData = snapshot(collectionID: scope, otherID: other, locations: [prior], revision: 1)
        let currentData = snapshot(collectionID: scope, otherID: other, locations: [prior, requested], revision: 3)
        let repository = SuspendedCollectionMapLookup(value: currentData)
        let model = MapViewModel(deviceLocationService: NoCollectionMapPosition(), locationRepository: repository,
                                 initialLocationID: prior.id)
        model.applyLibrarySnapshot(oldData)
        let resolving = Task { await model.resolveSavedLocationRequest(id: requested.id) }
        await repository.started.wait()
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other, locations: [prior], revision: 2))
        #expect(model.selectedSavedLocation == prior)
        #expect(model.unavailableSavedLocationEvent == 0)
        let newer = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: CollectionMapFixture.visibleName, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 40, longitude: 50))
        if newCandidateWins { model.selectSearchCandidate(newer) }
        await repository.release.open()
        await resolving.value
        if newCandidateWins {
            #expect(model.selectedCandidate == newer)
            #expect(model.selectedSavedLocation == nil)
            #expect(model.visiblePlace?.coordinate == newer.coordinate)
        } else {
            #expect(model.selectedSavedLocation == requested)
            #expect(model.visiblePlace?.coordinate == requested.coordinate)
            #expect(model.libraryRevision == 3)
        }
        #expect(model.unavailableSavedLocationEvent == 0)
    }

    /// AC-31/46/58, INV-09: MapKit deselection/restoration callbacks do not cancel authoritative saved-place navigation.
    @Test(arguments: CollectionMapBookkeeping.allCases)
    func mapSelectionBookkeepingPreservesSuspendedSavedPlaceLookup(callback: CollectionMapBookkeeping) async throws {
        let scope = UUID()
        let other = UUID()
        let prior = try saved(id: CollectionMapFixture.firstID, collectionID: scope)
        let requested = try saved(id: CollectionMapFixture.secondID, collectionID: scope, latitude: 11)
        let repository = SuspendedCollectionMapLookup(value: snapshot(collectionID: scope, otherID: other,
            locations: [prior, requested], revision: 2))
        let model = MapViewModel(deviceLocationService: NoCollectionMapPosition(), locationRepository: repository,
                                 initialLocationID: prior.id)
        model.applyLibrarySnapshot(snapshot(collectionID: scope, otherID: other, locations: [prior], revision: 1))
        if callback != .inactive { #expect(await model.activate() == nil) }
        let restoringSelection = model.mapSelection
        let resolving = Task { await model.resolveSavedLocationRequest(id: requested.id) }
        await repository.started.wait()
        switch callback {
        case .optionalNil: model.updateMapSelection(nil)
        case .emptyFeature: model.updateMapSelection(MapSelection<UUID>(nil as MapFeature?))
        case .inactive: model.updateMapSelection(MapSelection(UUID()))
        case .sameSelection: model.updateMapSelection(restoringSelection)
        }
        await repository.release.open()
        await resolving.value
        #expect(model.selectedSavedLocation == requested)
        #expect(model.visiblePlace?.coordinate == requested.coordinate)
        #expect(model.libraryRevision == 2)
        #expect(model.unavailableSavedLocationEvent == 0)
        model.deactivate()
    }

    /// J-03/AC-56/67: complete-scope camera handles empty/coincident/antimeridian collections.
    @Test func fitAllIncludesEveryPointAcrossAntimeridianAndCoincidentCoordinates() throws {
        #expect(MapSavedCamera.region(for: []) == nil)
        let west = try Coordinate(latitude: -5, longitude: -179)
        let east = try Coordinate(latitude: 5, longitude: 179)
        let fit = try #require(MapSavedCamera.region(for: [west, east]))
        #expect(abs(fit.center.longitude) == 180)
        #expect(fit.span.longitudeDelta >= 2)
        #expect(fit.span.longitudeDelta < 10)
        #expect(fit.span.latitudeDelta >= 10)
        let coincident = try #require(MapSavedCamera.region(for: [west, west]))
        #expect(coincident.center.latitude == west.latitude)
        #expect(coincident.center.longitude == west.longitude)
        #expect(coincident.span.latitudeDelta > 0)
        #expect(coincident.span.longitudeDelta > 0)
    }
}

@MainActor
private final class CarouselResizePreferences: PreferenceStore {
    var language: Language = .system
    var theme: AppTheme = .system
    var mapType: MapType = .standard
    var distanceUnit: DistanceUnit = .kilometre
}

private struct FiniteCollectionMapRepository: LocationRepository {
    let value: LocationLibrarySnapshot
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot { value }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        AsyncThrowingStream { continuation in continuation.yield(value); continuation.finish() }
    }
    func location(id: UUID) async throws -> SavedLocation? { value.locations.first { $0.id == id } }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit { throw LocationWriteError.storageFailure }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageFailure
    }
}

private actor CollectionPagingRoutes: RouteEstimationService {
    private(set) var requests: [RouteRequest] = []
    func estimateRoute(_ request: RouteRequest) async throws(PlaceServiceError) -> RouteEstimate {
        requests.append(request)
        throw .noRoute
    }
}

private actor SuspendedCollectionMapLookup: LocationRepository {
    let value: LocationLibrarySnapshot
    let started = CollectionObservationGate()
    let release = CollectionObservationGate()
    init(value: LocationLibrarySnapshot) { self.value = value }
    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        await started.open()
        await release.wait()
        return value
    }
    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func location(id: UUID) async throws -> SavedLocation? { value.locations.first { $0.id == id } }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit { throw LocationWriteError.storageFailure }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageFailure
    }
}
