//
//  CurrentPositionPolicy.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import Foundation

/// The approved one-shot policy. Permission-prompt time is excluded from the timeout.
nonisolated enum CurrentPositionPolicy {
    static let acquisitionTimeout: Duration = .seconds(10)

    static func validate(_ position: DevicePosition, now: Date) throws(LocationServiceError) {
        try validateAuthorization(position.authorization)
        let age = now.timeIntervalSince(position.timestamp)
        guard age.isFinite, age >= 0 else { throw .invalidPosition }
    }

    static func validateAuthorization(_ authorization: LocationAuthorization) throws(LocationServiceError) {
        guard authorization.servicesEnabled else { throw .servicesDisabled }
        switch authorization.status {
        case .authorizedWhenInUse, .authorizedAlways: break
        case .notDetermined: throw .authorizationRequired
        case .denied: throw .permissionDenied
        case .restricted: throw .permissionRestricted
        }
    }
}
