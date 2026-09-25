import Foundation

/// Instance-backed adapter. App composition chooses the defaults suite.
/// Existing keys/raw values are preserved so scaffold preferences survive the refactor.
@MainActor
final class UserDefaultsPreferenceStore: PreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    // MARK: - Keys

    enum Keys {
        static let language = "CURRENT_LANGUAGE"
        static let theme = "APP_THEME"
        static let mapType = "DEFAULT_MAP_TYPE"
        static let distanceUnit = "DISTANCE_UNIT"
    }

    // MARK: - Language

    var language: Language {
        get {
            defaults.string(forKey: Keys.language)
                .flatMap(Language.init(rawValue:)) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.language) }
    }

    // MARK: - Appearance

    var theme: AppTheme {
        get {
            defaults.string(forKey: Keys.theme)
                .flatMap(AppTheme.init(rawValue:)) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.theme) }
    }

    // MARK: - Map Type

    var mapType: MapType {
        get {
            defaults.string(forKey: Keys.mapType)
                .flatMap(MapType.init(rawValue:)) ?? .standard
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.mapType) }
    }

    // MARK: - Distance Unit

    var distanceUnit: DistanceUnit {
        get {
            defaults.string(forKey: Keys.distanceUnit)
                .flatMap(DistanceUnit.init(rawValue:)) ?? .kilometre
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.distanceUnit) }
    }
}
