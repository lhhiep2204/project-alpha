//
//  MapRouteModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import CoreLocation
import Foundation
import Observation

enum MapRouteState: Equatable {
    case idle
    case noOrigin
    case distanceOnly(distanceMetres: Double)
    case loading(distanceMetres: Double, mode: RouteMode)
    case available(distanceMetres: Double, estimate: RouteEstimate)
    case unavailable(distanceMetres: Double, mode: RouteMode)
}

private struct MapRouteKey: Equatable {
    let origin: Coordinate
    let destinationID: MapQuickPlaceID
    let destination: RouteEndpoint
    let mode: RouteMode
}

/// One map session owns this model. Provider work never requests device permission.
@MainActor
@Observable
final class MapRouteModel {
    private let service: (any RouteEstimationService)?
    private var origin: Coordinate?
    private var destination: MapQuickPlace?
    private var active = false
    private var generation: UInt64 = 0
    private var key: MapRouteKey?
    private var task: Task<Void, Never>?
    private(set) var state: MapRouteState = .idle

    init(service: (any RouteEstimationService)?) { self.service = service }

    static func automaticMode(distanceMetres: Double) -> RouteMode? {
        RouteModePolicy.automaticMode(distanceMetres: distanceMetres)
    }

    func update(origin: Coordinate?, destination: MapQuickPlace?) {
        self.origin = origin
        self.destination = destination
        refresh()
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active {
            refresh()
        } else if task != nil {
            cancel()
            key = nil
        }
    }

    func awaitPendingEstimate() async { await task?.value }

    private func refresh() {
        guard let destination, !destination.isCurrentPosition else {
            reset(to: .idle)
            return
        }
        guard let origin else {
            reset(to: .noOrigin)
            return
        }
        let distance = CLLocation(latitude: origin.latitude, longitude: origin.longitude).distance(
            from: CLLocation(latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
        )
        guard let mode = Self.automaticMode(distanceMetres: distance) else {
            reset(to: .distanceOnly(distanceMetres: distance))
            return
        }
        let newKey = MapRouteKey(
            origin: origin, destinationID: destination.id,
            destination: RouteEndpoint(
                coordinate: destination.coordinate, savedLocationID: nil,
                placeIdentity: destination.placeIdentity
            ), mode: mode
        )
        guard key != newKey else { return }
        cancel()
        key = newKey
        guard active else {
            key = nil
            state = .loading(distanceMetres: distance, mode: mode)
            return
        }
        guard let service else {
            state = .unavailable(distanceMetres: distance, mode: mode)
            return
        }
        state = .loading(distanceMetres: distance, mode: mode)
        let request = RouteRequest(
            origin: RouteEndpoint(coordinate: origin, savedLocationID: nil, placeIdentity: nil),
            destination: newKey.destination, mode: mode, generation: generation
        )
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do {
                let estimate = try await service.estimateRoute(request)
                guard let self, self.accepts(request, key: newKey) else { return }
                self.task = nil
                guard estimate.request == request else {
                    self.state = .unavailable(distanceMetres: distance, mode: mode)
                    return
                }
                self.state = .available(distanceMetres: distance, estimate: estimate)
            } catch {
                guard let self, self.accepts(request, key: newKey) else { return }
                self.task = nil
                self.state = .unavailable(distanceMetres: distance, mode: mode)
            }
        }
    }

    private func accepts(_ request: RouteRequest, key: MapRouteKey) -> Bool {
        active && !Task.isCancelled && request.generation == generation && self.key == key
    }

    private func reset(to state: MapRouteState) {
        cancel()
        key = nil
        self.state = state
    }

    private func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }
}
