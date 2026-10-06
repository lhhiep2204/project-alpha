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
    private let libraryProvider = LibraryRepositoryProvider()
    private let collectionRepositoryOverride: (any CollectionRepository)?

    init(
        preferenceStore: any PreferenceStore,
        collectionRepositoryOverride: (any CollectionRepository)? = nil
    ) {
        preferences = AppPreferences(store: preferenceStore)
        homeContainer = HomeContainer()
        mapContainer = MapContainer()
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
