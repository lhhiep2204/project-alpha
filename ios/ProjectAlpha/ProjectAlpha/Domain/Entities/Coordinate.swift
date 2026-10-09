//
//  Coordinate.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/9/26.
//

import Foundation

/// A validated geographic coordinate. `(0, 0)` is a valid coordinate.
nonisolated struct Coordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else {
            throw DomainValidationError.invalidCoordinate
        }

        self.latitude = latitude
        self.longitude = longitude
    }

    /// The comparison-only form required by the no-provider-ID duplicate policy.
    var normalizedMicrodegrees: NormalizedCoordinate {
        NormalizedCoordinate(
            latitude: Self.microdegrees(latitude),
            longitude: Self.microdegrees(longitude == 180 ? -180 : longitude)
        )
    }

    /// Great-circle distance in metres. This is used only for the 20 m warning rule.
    func distance(to other: Self) -> Double {
        let earthRadiusMetres = 6_371_000.0
        let latitudeDelta = Self.radians(other.latitude - latitude)
        let longitudeDelta = Self.radians(other.longitude - longitude)
        let latitude1 = Self.radians(latitude)
        let latitude2 = Self.radians(other.latitude)
        let a = pow(sin(latitudeDelta / 2), 2)
            + cos(latitude1) * cos(latitude2) * pow(sin(longitudeDelta / 2), 2)
        return earthRadiusMetres * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func microdegrees(_ value: Double) -> Int {
        let rounded = (value * 1_000_000).rounded(.toNearestOrAwayFromZero)
        return Int(rounded == 0 ? 0 : rounded)
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}

nonisolated struct NormalizedCoordinate: Hashable, Sendable {
    let latitude: Int
    let longitude: Int
}
