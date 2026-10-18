//
//  MapContainer.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

@MainActor
final class MapContainer {
    let deviceLocationService: any DeviceLocationService
    let placeIdentityResolutionService: any PlaceIdentityResolutionService
    let reverseGeocodingService: any ReverseGeocodingService
    let routeEstimationService: any RouteEstimationService
    private let placeSearchService: any PlaceSearchService

    init(
        deviceLocationService: any DeviceLocationService,
        placeSearchService: any PlaceSearchService,
        placeIdentityResolutionService: any PlaceIdentityResolutionService,
        reverseGeocodingService: any ReverseGeocodingService,
        routeEstimationService: any RouteEstimationService
    ) {
        self.deviceLocationService = deviceLocationService
        self.placeSearchService = placeSearchService
        self.placeIdentityResolutionService = placeIdentityResolutionService
        self.reverseGeocodingService = reverseGeocodingService
        self.routeEstimationService = routeEstimationService
    }

    func makeMapView() -> MapView {
        MapView(
            viewModel: MapViewModel(
                deviceLocationService: deviceLocationService,
                placeSearchService: placeSearchService,
                reverseGeocodingService: reverseGeocodingService,
                routeEstimationService: routeEstimationService,
                mapFeatureResolver: { feature async throws(PlaceServiceError) in
                    try await AppleMapFeatureResolver.resolve(feature)
                }
            )
        )
    }
}
