//
//  DevicePosition.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import Foundation

nonisolated enum LocationAuthorizationStatus: Hashable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorizedWhenInUse
    case authorizedAlways

    var allowsPosition: Bool {
        switch self {
        case .authorizedWhenInUse, .authorizedAlways: true
        case .notDetermined, .denied, .restricted: false
        }
    }
}

nonisolated enum LocationAccuracyAuthorization: Hashable, Sendable {
    case full
    case reduced
}

/// A plain snapshot. Reading it never requests permission.
nonisolated struct LocationAuthorization: Hashable, Sendable {
    let status: LocationAuthorizationStatus
    let accuracy: LocationAccuracyAuthorization
    let servicesEnabled: Bool
}

nonisolated enum LocationServiceError: Error, Equatable, Sendable {
    case servicesDisabled
    case permissionDenied
    case permissionRestricted
    case authorizationRequired
    case positionUnavailable
    case invalidPosition
    case stalePosition
    case timedOut
    case cancelled
}

/// One device fix, including the metadata needed to explain its usefulness.
nonisolated struct DevicePosition: Hashable, Sendable {
    let coordinate: Coordinate
    let timestamp: Date
    let horizontalAccuracyMetres: Double
    let authorization: LocationAuthorization

    init(
        coordinate: Coordinate,
        timestamp: Date,
        horizontalAccuracyMetres: Double,
        authorization: LocationAuthorization
    ) throws(LocationServiceError) {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite,
              horizontalAccuracyMetres.isFinite,
              horizontalAccuracyMetres >= 0
        else {
            throw .invalidPosition
        }

        self.coordinate = coordinate
        self.timestamp = timestamp
        self.horizontalAccuracyMetres = horizontalAccuracyMetres
        self.authorization = authorization
    }
}
