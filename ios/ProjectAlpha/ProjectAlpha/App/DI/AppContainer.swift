//
//  AppContainer.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation

@MainActor
final class AppContainer {
    let preferences: AppPreferences
    let homeContainer: HomeContainer
    let mapContainer: MapContainer
    let settingsContainer: SettingsContainer
    let deviceLocationService: any DeviceLocationService
    let placeSearchService: any PlaceSearchService
    let placeIdentityResolutionService: any PlaceIdentityResolutionService
    let reverseGeocodingService: any ReverseGeocodingService
    let routeEstimationService: any RouteEstimationService
    private let libraryProvider = LibraryRepositoryProvider()
    private let collectionRepositoryOverride: (any CollectionRepository)?

    init(
        preferenceStore: any PreferenceStore,
        collectionRepositoryOverride: (any CollectionRepository)? = nil,
        deviceLocationServiceOverride: (any DeviceLocationService)? = nil,
        placeSearchServiceOverride: (any PlaceSearchService)? = nil,
        placeIdentityResolutionServiceOverride: (any PlaceIdentityResolutionService)? = nil,
        reverseGeocodingServiceOverride: (any ReverseGeocodingService)? = nil,
        routeEstimationServiceOverride: (any RouteEstimationService)? = nil
    ) {
        // Adapters retain configuration only; location and provider work begins on demand.
        let appleMapsService = AppleMapsService()
        let deviceLocationService = deviceLocationServiceOverride ?? CoreLocationDeviceService()
        let placeSearchService = placeSearchServiceOverride ?? appleMapsService
        let placeIdentityResolutionService = placeIdentityResolutionServiceOverride ?? appleMapsService
        let reverseGeocodingService = reverseGeocodingServiceOverride ?? appleMapsService
        let routeEstimationService = routeEstimationServiceOverride ?? appleMapsService
        self.deviceLocationService = deviceLocationService
        self.placeSearchService = placeSearchService
        self.placeIdentityResolutionService = placeIdentityResolutionService
        self.reverseGeocodingService = reverseGeocodingService
        self.routeEstimationService = routeEstimationService
        preferences = AppPreferences(store: preferenceStore)
        homeContainer = HomeContainer()
        mapContainer = MapContainer(
            deviceLocationService: deviceLocationService,
            placeSearchService: placeSearchService,
            placeIdentityResolutionService: placeIdentityResolutionService,
            reverseGeocodingService: reverseGeocodingService,
            routeEstimationService: routeEstimationService
        )
        settingsContainer = SettingsContainer()
        self.collectionRepositoryOverride = collectionRepositoryOverride
    }

    func collectionRepository() async throws -> any CollectionRepository {
        if let collectionRepositoryOverride { return collectionRepositoryOverride }
        return try await libraryProvider.collectionRepository()
    }
}

/// Serializes the one-time disk store open across all scenes without blocking the UI actor.
private actor LibraryRepositoryProvider {
    private var repository: (any CollectionRepository)?

    func collectionRepository() throws -> any CollectionRepository {
        if let repository { return repository }
        let store = LibraryStore(container: try LibraryStoreConfiguration.makeContainer())
        let repository = SwiftDataCollectionRepository(store: store)
        self.repository = repository
        return repository
    }
}
