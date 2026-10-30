//
//  MapSavedCamera.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import MapKit

/// Smallest wrapped longitude interval, with useful zoom for one/coincident points.
enum MapSavedCamera {
    static func region(for coordinates: [Coordinate]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map { coordinate in
            coordinate.longitude < 0 ? coordinate.longitude + Metrics.fullCircle : coordinate.longitude
        }.sorted()
        let lowerLatitude = latitudes.min() ?? 0
        let upperLatitude = latitudes.max() ?? 0
        var largestGap = -Double.infinity
        var intervalStart = longitudes[0]
        for index in longitudes.indices {
            let next = index + 1 < longitudes.count ? longitudes[index + 1] : longitudes[0] + Metrics.fullCircle
            let gap = next - longitudes[index]
            if gap > largestGap {
                largestGap = gap
                intervalStart = next.truncatingRemainder(dividingBy: Metrics.fullCircle)
            }
        }
        let longitudeSpan = max(0, Metrics.fullCircle - largestGap)
        var longitude = intervalStart + longitudeSpan / 2
        if longitude > Metrics.halfCircle { longitude -= Metrics.fullCircle }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (lowerLatitude + upperLatitude) / 2, longitude: longitude),
            span: MKCoordinateSpan(
                latitudeDelta: min(Metrics.maximumLatitudeSpan, max(Metrics.minimumSpan, (upperLatitude - lowerLatitude) * Metrics.padding)),
                longitudeDelta: min(Metrics.fullCircle, max(Metrics.minimumSpan, longitudeSpan * Metrics.padding))
            )
        )
    }

    private enum Metrics {
        static let minimumSpan = 0.01
        static let padding = 1.3
        static let fullCircle = 360.0
        static let halfCircle = 180.0
        static let maximumLatitudeSpan = 170.0
    }
}
