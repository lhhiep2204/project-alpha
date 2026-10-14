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

    var id: Self { self }
}

/// One owner per scene. Routers never retain the coordinator or feature models.
@Observable @MainActor
final class SceneCoordinator {
    var selectedTab: MainTab = .home
    private(set) var mapPresentation: MapPresentation = .none
    let homeRouter = Router<HomeRoute>(root: .root)
    let mapRouter = Router<MapRoute>(root: .root)
    let settingsRouter = Router<SettingsRoute>(root: .root)

    /// Immediate display context for a collection selected in this scene.
    /// The destination resolves the current collection from storage after entry.
    private var collectionTitleHints: [UUID: String] = [:]
    @ObservationIgnored private var pendingMapPresentation: MapPresentation?
    @ObservationIgnored private var mapDismissalInFlight = false

    /// The only sheet item owned by the Global Map in this scene.
    var presentedMapSheet: MapPresentation? {
        mapPresentation == .none ? nil : mapPresentation
    }

    func openMapSearch() {
        requestMapPresentation(.search)
    }

    func closeMapSearch() {
        closeMapPresentation(.search)
    }

    func openMapDetail() {
        requestMapPresentation(.detail)
    }

    func closeMapDetail() {
        closeMapPresentation(.detail)
    }

    /// Called by the single sheet binding when the system dismisses its item.
    func dismissMapPresentation() {
        guard mapPresentation != .none else { return }
        pendingMapPresentation = nil
        mapPresentation = .none
        mapDismissalInFlight = true
    }

    /// Advance a queued presentation only after SwiftUI acknowledges dismissal.
    func mapPresentationDidDismiss() {
        guard mapDismissalInFlight else { return }
        mapDismissalInFlight = false
        if let pendingMapPresentation {
            self.pendingMapPresentation = nil
            mapPresentation = pendingMapPresentation
        }
    }

    private func requestMapPresentation(_ requested: MapPresentation) {
        guard requested != .none else { return }
        if mapDismissalInFlight {
            pendingMapPresentation = requested
        } else if mapPresentation == .none {
            mapPresentation = requested
        } else if mapPresentation != requested {
            pendingMapPresentation = requested
            mapPresentation = .none
            mapDismissalInFlight = true
        }
    }

    private func closeMapPresentation(_ target: MapPresentation) {
        if pendingMapPresentation == target {
            pendingMapPresentation = nil
        }
        guard mapPresentation == target else { return }
        mapPresentation = .none
        mapDismissalInFlight = true
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
