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
    @State private var libraryFailed = false

    var body: some View {
        let language = container.preferences.language
        let theme = container.preferences.theme

        Group {
            if let repository {
                MainTabView(coordinator: coordinator) { route, selection in
                    switch route {
                    case .root:
                        container.homeContainer.makeHomeView(
                            router: coordinator.homeRouter,
                            repository: repository,
                            selection: selection
                        )
                    case .collection(let id):
                        container.homeContainer.makeCollectionDetailView(
                            id: id,
                            repository: repository,
                            router: coordinator.homeRouter
                        )
                        .id(id)
                    }
                } map: { route in
                    switch route {
                    case .root: container.mapContainer.makeMapView(router: coordinator.mapRouter)
                    }
                } settings: { route in
                    switch route {
                    case .root: container.settingsContainer.makeSettingsView(router: coordinator.settingsRouter)
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
                    Button(CollectionKeys.retry) {
                        Task { await loadLibrary() }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .dsToast(manager: toastManager)
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
            repository = opened
            libraryFailed = false
        } catch {
            libraryFailed = true
        }
    }
}

#Preview {
    AppRootView(container: AppContainer(
        preferenceStore: PreviewPreferenceStore(),
        collectionRepositoryOverride: PreviewCollectionRepository()
    ))
}
