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
    private let locationRepositoryOverride: (any LocationRepository)?
    private let mediaServiceOverride: (any LocationMediaService)?

    init(
        preferenceStore: any PreferenceStore,
        collectionRepositoryOverride: (any CollectionRepository)? = nil,
        locationRepositoryOverride: (any LocationRepository)? = nil,
        mediaServiceOverride: (any LocationMediaService)? = nil,
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
        self.locationRepositoryOverride = locationRepositoryOverride
        self.mediaServiceOverride = mediaServiceOverride
    }

    func locationRepository() async throws -> any LocationRepository {
        if let locationRepositoryOverride { return locationRepositoryOverride }
        guard collectionRepositoryOverride == nil else { throw LocationWriteError.storageUnavailable }
        return try await libraryProvider.locationRepository()
    }

    func locationMediaService() async throws -> (any LocationMediaService)? {
        if let mediaServiceOverride { return mediaServiceOverride }
        guard collectionRepositoryOverride == nil else { return nil }
        return try await libraryProvider.mediaService()
    }

    func performLibraryMaintenance() async {
        guard collectionRepositoryOverride == nil else { return }
        await libraryProvider.performMaintenance()
    }

    func collectionRepository() async throws -> any CollectionRepository {
        if let collectionRepositoryOverride { return collectionRepositoryOverride }
        return try await libraryProvider.collectionRepository()
    }
}

/// Serializes the one-time disk store open across all scenes without blocking the UI actor.
private actor LibraryRepositoryProvider {
    private var store: LibraryStore?
    private var media: LocalLocationMediaService?

    private func openedStore() throws -> LibraryStore {
        if let store { return store }
        let store = LibraryStore(container: try LibraryStoreConfiguration.makeContainer())
        self.store = store
        return store
    }

    func collectionRepository() throws -> any CollectionRepository {
        SwiftDataCollectionRepository(store: try openedStore())
    }

    func locationRepository() throws -> any LocationRepository {
        SwiftDataLocationRepository(store: try openedStore())
    }

    func performMaintenance() async {
        // Called only after the usable library is published to the scene.
        try? await media?.startMaintenance()
    }

    func mediaService() async throws -> any LocationMediaService {
        if let media { return media }
        let service = LocalLocationMediaService(store: try openedStore())
        media = service
        return service
    }
}
