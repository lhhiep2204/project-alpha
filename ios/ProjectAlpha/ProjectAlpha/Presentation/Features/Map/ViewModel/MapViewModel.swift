//
//  MapViewModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation
import MapKit
import Observation
import SwiftUI

enum MapLocationIssue: Equatable {
    case servicesDisabled
    case restricted
    case timedOut
    case unavailable
}

enum MapLocationOutcome: Equatable {
    case permissionDenied
    case toast(MapLocationIssue)
}

struct MapLocationFocus: Equatable {
    let coordinate: Coordinate
    let generation: Int
}

@Observable
@MainActor
final class MapViewModel {
    private let router: Router<MapRoute>
    private let deviceLocationService: any DeviceLocationService
    private var operationGeneration = 0
    private var initialPositionCompleted = false
    private var userChangedCamera = false
    private var consumedRecenterRequestID = 0
    private var isActive = false

    var cameraPosition: MapCameraPosition = .rect(.world)
    private(set) var locationFocus: MapLocationFocus?
    private(set) var isLocating = false
    private(set) var showsUserLocation = false
    private(set) var recenterRequestID = 0
    var permissionAlertPresented = false

    var hasPendingRecenterRequest: Bool {
        recenterRequestID != consumedRecenterRequestID
    }

    init(router: Router<MapRoute>, deviceLocationService: any DeviceLocationService) {
        self.router = router
        self.deviceLocationService = deviceLocationService
    }

    /// Called only by the selected Map destination's foreground lifecycle task.
    /// A cancelled first acquisition can resume on return; completed attempts never refocus.
    func activate() async -> MapLocationOutcome? {
        isActive = true
        return await locate(isExplicit: false)
    }

    func recenter() async -> MapLocationOutcome? {
        guard isActive else { return nil }
        return await locate(isExplicit: true)
    }

    func requestRecenter() {
        guard isActive, !isLocating else { return }
        recenterRequestID += 1
    }

    func performPendingRecenter() async -> MapLocationOutcome? {
        guard hasPendingRecenterRequest else { return nil }
        consumedRecenterRequestID = recenterRequestID
        return await recenter()
    }

    /// The view cancels its structured task at the same boundary. Generation invalidation
    /// also rejects a service that returns after cancellation or a later activation.
    func deactivate() {
        isActive = false
        operationGeneration += 1
        consumedRecenterRequestID = recenterRequestID
        isLocating = false
        showsUserLocation = false
    }

    func userDidChangeCamera() {
        userChangedCamera = true
    }

    func focusCamera(on focus: MapLocationFocus) {
        let center = CLLocationCoordinate2D(
            latitude: focus.coordinate.latitude,
            longitude: focus.coordinate.longitude
        )
        // Keep a useful existing zoom; a world-scale initial map uses neighbourhood scale.
        let retainedSpan = cameraPosition.region?.span
        let span = retainedSpan.flatMap { span in
            span.latitudeDelta <= MapCameraMetrics.maximumRetainedSpan
                && span.longitudeDelta <= MapCameraMetrics.maximumRetainedSpan ? span : nil
        } ?? MKCoordinateSpan(
            latitudeDelta: MapCameraMetrics.neighbourhoodSpan,
            longitudeDelta: MapCameraMetrics.neighbourhoodSpan
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func locate(isExplicit: Bool) async -> MapLocationOutcome? {
        guard !isLocating else { return nil }
        operationGeneration += 1
        let generation = operationGeneration
        isLocating = true
        defer {
            if generation == operationGeneration { isLocating = false }
        }

        let authorization = await deviceLocationService.authorization()
        guard accepts(generation) else { return nil }
        showsUserLocation = authorization.servicesEnabled && authorization.status.allowsPosition

        if !isExplicit, initialPositionCompleted { return nil }

        if !authorization.servicesEnabled {
            initialPositionCompleted = true
            return .toast(.servicesDisabled)
        }
        if authorization.status == .denied {
            initialPositionCompleted = true
            return isExplicit ? .permissionDenied : nil
        }
        if authorization.status == .restricted {
            initialPositionCompleted = true
            return .toast(.restricted)
        }

        do {
            let position = try await deviceLocationService.currentPosition()
            guard accepts(generation) else { return nil }
            initialPositionCompleted = true
            showsUserLocation = position.authorization.servicesEnabled
                && position.authorization.status.allowsPosition
            if isExplicit || !userChangedCamera {
                locationFocus = MapLocationFocus(coordinate: position.coordinate, generation: generation)
            }
            return nil
        } catch {
            guard accepts(generation), error != .cancelled else { return nil }
            let latestAuthorization = await deviceLocationService.authorization()
            guard accepts(generation) else { return nil }
            showsUserLocation = latestAuthorization.servicesEnabled && latestAuthorization.status.allowsPosition
            initialPositionCompleted = true
            switch error {
            case .permissionDenied:
                showsUserLocation = false
                return isExplicit ? .permissionDenied : nil
            case .servicesDisabled:
                showsUserLocation = false
                return .toast(.servicesDisabled)
            case .permissionRestricted:
                showsUserLocation = false
                return .toast(.restricted)
            case .timedOut: return .toast(.timedOut)
            case .authorizationRequired, .positionUnavailable, .invalidPosition, .stalePosition:
                return .toast(.unavailable)
            case .cancelled: return nil
            }
        }
    }

    private func accepts(_ generation: Int) -> Bool {
        isActive && generation == operationGeneration && !Task.isCancelled
    }
}

private enum MapCameraMetrics {
    static let neighbourhoodSpan = 0.01
    static let maximumRetainedSpan = 1.0
}
