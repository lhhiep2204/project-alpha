import Observation

/// Shared by app scenes. All writes flow through this observable owner.
@Observable @MainActor
final class AppPreferences {
    private let store: any PreferenceStore
    var language: Language { didSet { store.language = language } }
    var theme: AppTheme { didSet { store.theme = theme } }
    var mapType: MapType { didSet { store.mapType = mapType } }
    var distanceUnit: DistanceUnit { didSet { store.distanceUnit = distanceUnit } }

    init(store: any PreferenceStore) {
        self.store = store
        language = store.language
        theme = store.theme
        mapType = store.mapType
        distanceUnit = store.distanceUnit
    }
}
