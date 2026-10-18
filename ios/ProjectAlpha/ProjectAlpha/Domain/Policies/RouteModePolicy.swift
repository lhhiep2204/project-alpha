//
//  RouteModePolicy.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation

/// Automatic travel mode uses direct distance, never a synthetic travel time.
nonisolated enum RouteModePolicy {
    static func automaticMode(distanceMetres: Double) -> RouteMode? {
        guard distanceMetres.isFinite, distanceMetres >= 0 else { return nil }
        if distanceMetres <= maximumWalkingDistanceMetres { return .walking }
        return .driving
    }

    private static let maximumWalkingDistanceMetres = 1_000.0
}
