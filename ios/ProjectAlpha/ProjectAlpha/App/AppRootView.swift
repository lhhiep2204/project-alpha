import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @State private var coordinator = SceneCoordinator()

    var body: some View {
        let language = container.preferences.language
        let theme = container.preferences.theme

        MainTabView(coordinator: coordinator) { route in
            switch route {
            case .root: container.homeContainer.makeHomeView(router: coordinator.homeRouter)
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
        .environment(coordinator)
        .environment(container.preferences)
        .environment(\.locale, LocalizationManager.locale(for: language))
        .environment(\.layoutDirection, LocalizationManager.layoutDirection(for: language))
        .preferredColorScheme(ThemeManager.preferredColorScheme(for: theme))
    }
}

#if DEBUG
#Preview {
    AppRootView(container: AppContainer(preferenceStore: PreviewPreferenceStore()))
}
#endif
