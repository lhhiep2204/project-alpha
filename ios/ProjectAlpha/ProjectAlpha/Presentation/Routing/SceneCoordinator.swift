//
//  SceneCoordinator.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/9/26.
//

import Foundation
import Observation

/// Global Map presentations share one scene-owned state across adaptive layouts.
enum MapPresentation: Equatable {
    case none
    case search
}

/// One owner per scene. Routers never retain the coordinator or feature models.
@Observable @MainActor
final class SceneCoordinator {
    var selectedTab: MainTab = .home
    var mapPresentation: MapPresentation = .none
    let homeRouter = Router<HomeRoute>(root: .root)
    let mapRouter = Router<MapRoute>(root: .root)
    let settingsRouter = Router<SettingsRoute>(root: .root)

    /// Immediate display context for a collection selected in this scene.
    /// The destination resolves the current collection from storage after entry.
    private var collectionTitleHints: [UUID: String] = [:]

    func openMapSearch() {
        mapPresentation = .search
    }

    func closeMapSearch() {
        mapPresentation = .none
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
