//
//  SceneCoordinator.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/9/26.
//

import Foundation
import Observation

/// Global Map presentations share one scene-owned state across adaptive layouts.
enum MapPresentation: Hashable, Identifiable {
    case none
    case search
    case detail
    case capture
    case collectionPicker

    var id: Self { self }
}

/// One owner per scene. Routers never retain the coordinator or feature models.
@Observable @MainActor
final class SceneCoordinator {
    var selectedTab: MainTab = .home
    let globalMapPresentation = MapPresentationState()
    private(set) var globalLocationID: UUID?
    private(set) var globalLocationFocusRequestID: UUID?
    let homeRouter = Router<HomeRoute>(root: .root)
    let mapRouter = Router<MapRoute>(root: .root)
    let settingsRouter = Router<SettingsRoute>(root: .root)

    /// Immediate display context for a collection selected in this scene.
    /// The destination resolves the current collection from storage after entry.
    private var collectionTitleHints: [UUID: String] = [:]
    var mapPresentation: MapPresentation { globalMapPresentation.mapPresentation }
    var presentedMapSheet: MapPresentation? { globalMapPresentation.presentedMapSheet }
    func openMapSearch() { globalMapPresentation.openMapSearch() }
    func closeMapSearch() { globalMapPresentation.closeMapSearch() }
    func openMapDetail() { globalMapPresentation.openMapDetail() }
    func closeMapDetail() { globalMapPresentation.closeMapDetail() }
    func openMapCapture() { globalMapPresentation.openMapCapture() }
    func closeMapCapture() { globalMapPresentation.closeMapCapture() }
    func openMapCollectionPicker() { globalMapPresentation.openMapCollectionPicker() }
    func closeMapCollectionPicker() { globalMapPresentation.closeMapCollectionPicker() }
    func dismissMapPresentation() { globalMapPresentation.dismissMapPresentation() }
    func mapPresentationDidDismiss() { globalMapPresentation.mapPresentationDidDismiss() }

    func openSavedLocationInGlobalMap(id: UUID) {
        globalLocationID = id
        globalLocationFocusRequestID = UUID()
        selectedTab = .map
    }

    func openCollectionMap(collectionID: UUID, locationID: UUID?) {
        let route = HomeRoute.collectionMap(collectionID: collectionID, initialLocationID: locationID)
        if homeRouter.paths.contains(where: {
            if case .collectionMap = $0 { return true }
            return false
        }) { return }
        homeRouter.paths.append(route)
    }

    func setCollectionTitleHint(id: UUID, name: String) {
        collectionTitleHints[id] = name
    }

    func collectionTitleHint(for id: UUID) -> String? {
        collectionTitleHints[id]
    }

    func clearCollectionTitleHint(for id: UUID) {
        collectionTitleHints.removeValue(forKey: id)
    }
}
