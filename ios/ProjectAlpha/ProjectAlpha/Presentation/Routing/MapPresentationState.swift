//
//  MapPresentationState.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation
import Observation

/// Owned by one map session; never shared between Collection Map and Global Map.
@Observable @MainActor
final class MapPresentationState {
    private(set) var mapPresentation: MapPresentation = .none
    @ObservationIgnored private var pendingMapPresentation: MapPresentation?
    @ObservationIgnored private var mapDismissalInFlight = false

    /// One sheet item per map session across adaptive layouts.
    var presentedMapSheet: MapPresentation? {
        mapPresentation == .none ? nil : mapPresentation
    }

    func openMapSearch() {
        requestMapPresentation(.search)
    }

    func closeMapSearch() {
        closeMapPresentation(.search)
    }

    func openMapCapture() { requestMapPresentation(.capture) }
    func closeMapCapture() { closeMapPresentation(.capture) }
    func openMapCollectionPicker() { requestMapPresentation(.collectionPicker) }
    func closeMapCollectionPicker() { closeMapPresentation(.collectionPicker) }

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

}
