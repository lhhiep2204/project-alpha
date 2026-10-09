//
//  LocationMapDomainTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import Foundation
import Testing
@testable import ProjectAlpha

private enum ServiceDomainFixture {
    static let timestamp = Date(timeIntervalSinceReferenceDate: 1_000)
    static let locale = "vi"
    static let query = "Library"
}

/// AC-37, AC-43/54, AC-19: Foundation-only boundary values remain usable off the UI actor.
struct LocationMapDomainTests {
    private func position(age: TimeInterval = 0, accuracy: Double = 25,
                          status: LocationAuthorizationStatus = .authorizedWhenInUse,
                          reduced: Bool = false, enabled: Bool = true) throws -> DevicePosition {
        try DevicePosition(coordinate: Coordinate(latitude: 0, longitude: 0),
                           timestamp: ServiceDomainFixture.timestamp.addingTimeInterval(-age),
                           horizontalAccuracyMetres: accuracy,
                           authorization: LocationAuthorization(status: status,
                                                               accuracy: reduced ? .reduced : .full,
                                                               servicesEnabled: enabled))
    }

    /// AC-37: any valid past fix, including a much older cached position, remains usable.
    @Test func pastPositionAgeAndReducedMetadataRemainValid() throws {
        let acceptedAges: [TimeInterval] = [30, 30.001, 10 * 365 * 24 * 60 * 60]
        for age in acceptedAges {
            let fix = try position(age: age, accuracy: 1_200, reduced: true)
            try CurrentPositionPolicy.validate(fix, now: ServiceDomainFixture.timestamp)
            #expect(fix.timestamp == ServiceDomainFixture.timestamp.addingTimeInterval(-age))
            #expect(fix.coordinate.latitude == 0 && fix.coordinate.longitude == 0)
            #expect(fix.horizontalAccuracyMetres == 1_200)
            #expect(fix.authorization.accuracy == .reduced)
        }
        #expect(throws: LocationServiceError.invalidPosition) {
            try CurrentPositionPolicy.validate(position(age: -0.001), now: ServiceDomainFixture.timestamp)
        }
    }

    /// AC-37: denied, restricted, disabled and undetermined do not become usable fixes.
    @Test func authorizationFailuresRemainDistinct() throws {
        for (status, expected) in [(LocationAuthorizationStatus.denied, LocationServiceError.permissionDenied),
                                   (.restricted, .permissionRestricted), (.notDetermined, .authorizationRequired)] {
            #expect(throws: expected) {
                try CurrentPositionPolicy.validate(position(status: status), now: ServiceDomainFixture.timestamp)
            }
        }
        #expect(throws: LocationServiceError.servicesDisabled) {
            try CurrentPositionPolicy.validate(position(enabled: false), now: ServiceDomainFixture.timestamp)
        }
        try CurrentPositionPolicy.validate(position(status: .authorizedAlways), now: ServiceDomainFixture.timestamp)
    }

    /// AC-37: negative/nonfinite sensor accuracy or time cannot cross the service boundary.
    @Test func invalidSensorMetadataIsRejected() throws {
        for accuracy in [-1.0, Double.nan, .infinity, -.infinity] {
            #expect(throws: LocationServiceError.invalidPosition) { try position(accuracy: accuracy) }
        }
        #expect(throws: LocationServiceError.invalidPosition) {
            try DevicePosition(coordinate: Coordinate(latitude: 0, longitude: 0),
                               timestamp: Date(timeIntervalSinceReferenceDate: .infinity),
                               horizontalAccuracyMetres: 0,
                               authorization: position().authorization)
        }
    }

    /// AC-19: unusable geographic bias is rejected before provider work.
    @Test func searchRegionAcceptsWorldBoundaryButRejectsInvalidSpans() throws {
        let center = try Coordinate(latitude: 0, longitude: 0)
        _ = try PlaceSearchRegion(center: center, latitudeDelta: 180, longitudeDelta: 360)
        for invalid in [0.0, -1, Double.nan, .infinity, 180.001] {
            #expect(throws: PlaceServiceError.invalidRequest) {
                try PlaceSearchRegion(center: center, latitudeDelta: invalid, longitudeDelta: 1)
            }
        }
        #expect(throws: PlaceServiceError.invalidRequest) {
            try PlaceSearchRegion(center: center, latitudeDelta: 1, longitudeDelta: 360.001)
        }
    }

    /// AC-43/54: no-ID destinations, origins, mode and generation all distinguish route work.
    @Test func routeIdentityAndMetricValidation() throws {
        let origin = RouteEndpoint(coordinate: try Coordinate(latitude: 0, longitude: 0), savedLocationID: nil, placeIdentity: nil)
        let destination = RouteEndpoint(coordinate: try Coordinate(latitude: 1, longitude: 1), savedLocationID: nil, placeIdentity: nil)
        let other = RouteEndpoint(coordinate: try Coordinate(latitude: 2, longitude: 2), savedLocationID: nil, placeIdentity: nil)
        let request = RouteRequest(origin: origin, destination: destination, mode: .walking, generation: 1)
        #expect(request != RouteRequest(origin: origin, destination: other, mode: .walking, generation: 1))
        #expect(request != RouteRequest(origin: other, destination: destination, mode: .walking, generation: 1))
        #expect(request != RouteRequest(origin: origin, destination: destination, mode: .driving, generation: 1))
        #expect(request != RouteRequest(origin: origin, destination: destination, mode: .walking, generation: 2))
        let stationary = try RouteEstimate(request: request, distanceMetres: 0, duration: 0, computedAt: ServiceDomainFixture.timestamp)
        #expect(stationary.mode == .walking)
        for invalid in [-1.0, Double.nan, .infinity] {
            #expect(throws: PlaceServiceError.invalidResponse) {
                try RouteEstimate(request: request, distanceMetres: invalid, duration: 1, computedAt: ServiceDomainFixture.timestamp)
            }
            #expect(throws: PlaceServiceError.invalidResponse) {
                try RouteEstimate(request: request, distanceMetres: 1, duration: invalid, computedAt: ServiceDomainFixture.timestamp)
            }
        }
    }
}
