//
//  MainTabView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

/// Receives composed destinations without depending on App's DI containers.
struct MainTabView<Home: View, MapContent: View, Settings: View>: View {
    @Bindable var coordinator: SceneCoordinator
    @ViewBuilder let home: (HomeRoute, Binding<HomeRoute?>) -> Home
    @ViewBuilder let map: (MapRoute) -> MapContent
    @ViewBuilder let settings: (SettingsRoute) -> Settings

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            Tab(MainTab.home.title, systemImage: MainTab.home.systemImage, value: MainTab.home) {
                HomeNavigationView(router: coordinator.homeRouter, destination: home)
            }
            Tab(MainTab.map.title, systemImage: MainTab.map.systemImage, value: MainTab.map) {
                RouterView(router: coordinator.mapRouter, destination: map)
            }
            Tab(MainTab.settings.title, systemImage: MainTab.settings.systemImage, value: MainTab.settings) {
                RouterView(router: coordinator.settingsRouter, destination: settings)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// The same selected Home route drives the wide detail column and compact navigation.
/// The split view remains mounted while the system changes its column presentation.
private struct HomeNavigationView<Destination: View>: View {
    @Bindable var router: Router<HomeRoute>
    @ViewBuilder let destination: (HomeRoute, Binding<HomeRoute?>) -> Destination

    private var selection: Binding<HomeRoute?> {
        Binding(
            get: { router.paths.last },
            set: { route in
                router.paths = route.map { [$0] } ?? []
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            destination(.root, selection)
        } detail: {
            if let route = selection.wrappedValue {
                destination(route, selection)
            } else {
                ContentUnavailableView(
                    LocalizedStringKey(CollectionKeys.selectCollection.rawValue),
                    systemImage: DSSystemIcon.folder.rawValue
                )
            }
        }
    }
}

#Preview {
    MainTabView(coordinator: SceneCoordinator()) { _, _ in
        Text(MainTab.home.title)
    } map: { _ in
        Text(MainTab.map.title)
    } settings: { _ in
        Text(MainTab.settings.title)
    }
}

#Preview {
    HomeNavigationView(router: Router(root: HomeRoute.root)) { route, selection in
        switch route {
        case .root:
            List(selection: selection) {
                NavigationLink(value: HomeRoute.collection(id: Collection.mock.id)) {
                    Text(CollectionKeys.defaultCollectionName)
                }
            }
        case .collection:
            Text(CollectionKeys.emptyCollectionTitle)
        }
    }
}
