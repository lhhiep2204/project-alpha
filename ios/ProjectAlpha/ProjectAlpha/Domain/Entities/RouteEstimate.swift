//
//  RouteEstimate.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import Foundation

nonisolated enum RouteMode: Hashable, Sendable {
    case walking
    case driving
}

/// Coordinates always participate in request identity, including destinations without provider IDs.
nonisolated struct RouteEndpoint: Hashable, Sendable {
    let coordinate: Coordinate
    let savedLocationID: UUID?
    let placeIdentity: PlaceIdentity?
}

nonisolated struct RouteRequest: Hashable, Sendable {
    let origin: RouteEndpoint
    let destination: RouteEndpoint
    let mode: RouteMode
    let generation: UInt64
}

/// Metric route distance and duration, never a fabricated straight-line ETA.
nonisolated struct RouteEstimate: Hashable, Sendable {
    let request: RouteRequest
    let distanceMetres: Double
    let duration: TimeInterval
    let computedAt: Date

    var mode: RouteMode { request.mode }

    init(
        request: RouteRequest,
        distanceMetres: Double,
        duration: TimeInterval,
        computedAt: Date
    ) throws(PlaceServiceError) {
        guard distanceMetres.isFinite, distanceMetres >= 0,
              duration.isFinite, duration >= 0,
              computedAt.timeIntervalSinceReferenceDate.isFinite
        else { throw .invalidResponse }
        self.request = request
        self.distanceMetres = distanceMetres
        self.duration = duration
        self.computedAt = computedAt
    }
}
