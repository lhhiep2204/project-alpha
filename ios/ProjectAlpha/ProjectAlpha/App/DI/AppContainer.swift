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

    init(preferenceStore: any PreferenceStore) {
        preferences = AppPreferences(store: preferenceStore)
        homeContainer = HomeContainer()
        mapContainer = MapContainer()
        settingsContainer = SettingsContainer()
    }
}
