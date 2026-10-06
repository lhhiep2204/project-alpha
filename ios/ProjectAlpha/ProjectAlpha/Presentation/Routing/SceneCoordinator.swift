import Foundation
import Observation

/// One owner per scene. Routers never retain the coordinator or feature models.
@Observable @MainActor
final class SceneCoordinator {
    var selectedTab: MainTab = .home
    let homeRouter = Router<HomeRoute>(root: .root)
    let mapRouter = Router<MapRoute>(root: .root)
    let settingsRouter = Router<SettingsRoute>(root: .root)

    /// Immediate display context for a collection selected in this scene.
    /// The destination resolves the current collection from storage after entry.
    private var collectionTitleHints: [UUID: String] = [:]

    func setCollectionTitleHint(id: UUID, name: String) {
        collectionTitleHints[id] = name
    }

    func collectionTitleHint(for id: UUID) -> String? {
        collectionTitleHints[id]
    }

    func clearCollectionTitleHint(for id: UUID) {
        collectionTitleHints.removeValue(forKey: id)
    }
}
