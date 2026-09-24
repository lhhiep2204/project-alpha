import SwiftUI

/// Receives composed destinations without depending on App's DI containers.
struct MainTabView<Home: View, MapContent: View, Settings: View>: View {
    @Bindable var coordinator: SceneCoordinator
    @ViewBuilder let home: (HomeRoute) -> Home
    @ViewBuilder let map: (MapRoute) -> MapContent
    @ViewBuilder let settings: (SettingsRoute) -> Settings

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            RouterView(router: coordinator.homeRouter, destination: home)
                .tabItem { Label(MainTab.home.title, systemImage: MainTab.home.systemImage) }
                .tag(MainTab.home)
            RouterView(router: coordinator.mapRouter, destination: map)
                .tabItem { Label(MainTab.map.title, systemImage: MainTab.map.systemImage) }
                .tag(MainTab.map)
            RouterView(router: coordinator.settingsRouter, destination: settings)
                .tabItem { Label(MainTab.settings.title, systemImage: MainTab.settings.systemImage) }
                .tag(MainTab.settings)
        }
    }
}
