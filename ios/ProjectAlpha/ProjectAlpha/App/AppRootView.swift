//
//  AppRootView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @State private var coordinator = SceneCoordinator()
    @State private var toastManager = DSToastManager()
    @State private var repository: (any CollectionRepository)?
    @State private var locations: (any LocationRepository)?
    @State private var media: (any LocationMediaService)?
    @State private var libraryFailed = false

    var body: some View {
        let language = container.preferences.language
        let theme = container.preferences.theme

        Group {
            if let repository, let locations {
                MainTabView(coordinator: coordinator) { route, selection in
                    switch route {
                    case .root:
                        container.homeContainer.makeHomeView(
                            repository: repository,
                            selection: selection
                        )
                    case .collection(let id):
                        container.homeContainer.makeCollectionDetailView(
                            id: id,
                            repository: repository,
                            locationRepository: locations,
                            mediaService: media,
                            router: coordinator.homeRouter,
                            onOpenMap: { selectedID in
                                coordinator.openCollectionMap(collectionID: id, locationID: selectedID)
                            }
                        )
                        .id(id)
                    case .collectionMap(let collectionID, let initialLocationID):
                        container.mapContainer.makeMapView(
                            locationRepository: locations,
                            collectionRepository: repository,
                            mediaService: media,
                            scopeCollectionID: collectionID,
                            initialLocationID: initialLocationID
                        )
                        .id(collectionID)
                    }
                } map: { route in
                    switch route {
                    case .root:
                        container.mapContainer.makeMapView(
                            locationRepository: locations,
                            collectionRepository: repository,
                            mediaService: media
                        )
                    }
                } settings: { route in
                    switch route {
                    case .root: container.settingsContainer.makeSettingsView()
                    }
                }
            } else if libraryFailed {
                ContentUnavailableView {
                    Label {
                        Text(CollectionKeys.storageUnavailable)
                    } icon: {
                        Image.appSystemIcon(.folder)
                    }
                } actions: {
                    DSButton(CollectionKeys.retry) {
                        Task { await loadLibrary() }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .dsToast(manager: toastManager)
        .dsButtonFeedback()
        .environment(coordinator)
        .environment(toastManager)
        .environment(container.preferences)
        .environment(\.locale, LocalizationManager.locale(for: language))
        .environment(\.layoutDirection, LocalizationManager.layoutDirection(for: language))
        .preferredColorScheme(ThemeManager.preferredColorScheme(for: theme))
        .task { await loadLibrary() }
    }

    private func loadLibrary() async {
        guard repository == nil else { return }
        do {
            let opened = try await container.collectionRepository()
            let defaultName = LocalizationManager.localizedString(
                CollectionKeys.defaultCollectionName,
                locale: LocalizationManager.locale(for: container.preferences.language)
            )
            _ = try await opened.bootstrap(BootstrapCollectionCommand(
                id: UUID(),
                name: defaultName,
                createdAt: .now
            ))
            let openedLocations = try await container.locationRepository()
            let openedMedia = try await container.locationMediaService()
            locations = openedLocations
            media = openedMedia
            repository = opened
            libraryFailed = false
            await container.performLibraryMaintenance()
        } catch {
            libraryFailed = true
        }
    }
}

#Preview {
    AppRootView(container: AppContainer(
        preferenceStore: PreviewPreferenceStore(),
        collectionRepositoryOverride: PreviewCollectionRepository(),
        locationRepositoryOverride: PreviewLocationRepository()
    ))
}
