import Observation

/// One owner per scene. Routers never retain the coordinator or feature models.
@Observable @MainActor
final class SceneCoordinator {
    var selectedTab: MainTab = .home
    let homeRouter = Router<HomeRoute>(root: .root)
    let mapRouter = Router<MapRoute>(root: .root)
    let settingsRouter = Router<SettingsRoute>(root: .root)
}
