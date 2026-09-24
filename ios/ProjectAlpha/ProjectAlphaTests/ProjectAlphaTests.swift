import Foundation
import Observation
import SwiftUI
import Testing
@testable import ProjectAlpha

@MainActor
struct ArchitectureTests {
    @Test func scenesKeepIndependentNavigation() {
        let first = SceneCoordinator()
        let second = SceneCoordinator()
        first.homeRouter.push(.root)
        first.selectedTab = .map
        #expect(second.selectedTab == .home)
        #expect(second.homeRouter.paths.isEmpty)
        #expect(first.homeRouter.paths == [.root])
        first.selectedTab = .settings
        #expect(first.homeRouter.paths == [.root])
        #expect(first.mapRouter.paths.isEmpty)
    }

    @Test func sceneAndFeatureModelsAreReleased() {
        weak var scene: SceneCoordinator?
        weak var home: HomeViewModel?
        weak var map: MapViewModel?
        weak var settings: SettingsViewModel?
        weak var router: Router<HomeRoute>?
        do {
            let owner = SceneCoordinator()
            let homeModel = HomeViewModel(router: owner.homeRouter)
            let mapModel = MapViewModel(router: owner.mapRouter)
            let settingsModel = SettingsViewModel(router: owner.settingsRouter)
            scene = owner
            home = homeModel
            map = mapModel
            settings = settingsModel
            router = owner.homeRouter
            #expect(scene != nil && home != nil && map != nil && settings != nil)
        }
        #expect(scene == nil && home == nil && map == nil && settings == nil && router == nil)
    }

    @Test func preferencesPersistAndInvalidValuesFallBack() throws {
        let suite = "ProjectAlphaTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unsupported-language", forKey: "CURRENT_LANGUAGE")
        defaults.set("unsupported-theme", forKey: "APP_THEME")
        defaults.set("unsupported-map", forKey: "DEFAULT_MAP_TYPE")
        defaults.set("unsupported-unit", forKey: "DISTANCE_UNIT")
        let preferences = AppPreferences(store: UserDefaultsPreferenceStore(defaults: defaults))
        #expect(preferences.language == .system)
        #expect(preferences.theme == .system)
        #expect(preferences.mapType == .standard)
        #expect(preferences.distanceUnit == .kilometre)
        preferences.language = .vietnamese
        preferences.theme = .dark
        preferences.mapType = .hybrid
        preferences.distanceUnit = .mile
        let restored = AppPreferences(store: UserDefaultsPreferenceStore(defaults: defaults))
        #expect(restored.language == .vietnamese)
        #expect(restored.theme == .dark)
        #expect(restored.mapType == .hybrid)
        #expect(restored.distanceUnit == .mile)
    }

    @Test func sharedPreferencesDoNotOwnSceneState() {
        let store = TestPreferenceStore()
        let app = AppContainer(preferenceStore: store)
        let first = SceneCoordinator()
        let second = SceneCoordinator()
        first.selectedTab = .map
        second.homeRouter.push(.root)
        app.preferences.language = .arabic
        app.preferences.theme = .dark
        #expect(app.preferences.language.isRTL)
        #expect(store.language == .arabic)
        #expect(store.theme == .dark)
        #expect(first.selectedTab == .map)
        #expect(second.homeRouter.paths == [.root])
    }

    @Test func preferenceOwnerAndStoreAreReleased() {
        weak var store: TestPreferenceStore?
        weak var preferences: AppPreferences?
        do {
            let backing = TestPreferenceStore()
            let app = AppContainer(preferenceStore: backing)
            store = backing
            preferences = app.preferences
            #expect(preferences != nil)
        }
        #expect(preferences == nil && store == nil)
    }

    @Test func localizationCatalogHasCompleteSupportedLanguageCoverage() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ProjectAlpha/Presentation/Localization/Localizable.xcstrings")
        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try #require(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let requiredKeys = Set(CommonKeys.allCases.map(\.rawValue)
            + CollectionKeys.allCases.map(\.rawValue)
            + ["Home", "Map", "Settings", "Application", "Version"])
        let supportedLanguageCodes = Set(Language.allCases
            .filter { $0 != .system }
            .map(\.code))

        #expect(requiredKeys.isSubset(of: Set(strings.keys)))
        #expect(catalog["sourceLanguage"] as? String == "en")
        #expect(catalog["version"] as? String == "1.0")

        for (key, rawEntry) in strings {
            let entry = try #require(rawEntry as? [String: Any], "Missing catalog entry for \(key).")
            let localizations = try #require(
                entry["localizations"] as? [String: Any],
                "Missing localizations for \(key)."
            )
            #expect(Set(localizations.keys) == supportedLanguageCodes)

            for languageCode in supportedLanguageCodes {
                let localization = try #require(
                    localizations[languageCode] as? [String: Any],
                    "Missing \(languageCode) translation for \(key)."
                )
                let stringUnit = try #require(
                    localization["stringUnit"] as? [String: Any],
                    "Missing string unit for \(key) in \(languageCode)."
                )
                #expect(stringUnit["state"] as? String == "translated")
                #expect(!(stringUnit["value"] as? String ?? "").isEmpty)
            }
        }
    }

    @Test func languageAndThemeConfigurationMapsEverySupportedSelection() {
        #expect(ThemeManager.preferredColorScheme(for: .system) == nil)
        #expect(ThemeManager.preferredColorScheme(for: .light) == .light)
        #expect(ThemeManager.preferredColorScheme(for: .dark) == .dark)

        for language in Language.allCases {
            let expectedLocale = language == .system ? Locale.current.identifier : language.code
            #expect(LocalizationManager.locale(for: language).identifier == expectedLocale)
            #expect(LocalizationManager.layoutDirection(for: language)
                == (language.isRTL ? .rightToLeft : .leftToRight))
        }
    }
}

/// No MainActor annotation: constructing/reading Domain values must work off UI isolation.
struct DomainBoundaryTests {
    @Test func collectionCrossesActorBoundaryAsAValue() async {
        let id = UUID()
        let assetID = UUID()
        let collection = await Task.detached {
            Collection(id: id, name: "Travel", icon: .photo(assetID: assetID),
                       isDefault: false, createdAt: .distantPast,
                       updatedAt: .distantPast, revision: 3)
        }.value
        let returned = await CollectionEcho().echo(collection)
        #expect(returned == collection)
        #expect(returned.id == id)
        #expect(returned.icon == .photo(assetID: assetID))
        #expect(returned.revision == 3)
    }
}

private actor CollectionEcho {
    func echo(_ value: ProjectAlpha.Collection) -> ProjectAlpha.Collection { value }
}

@MainActor
private final class TestPreferenceStore: PreferenceStore {
    var language: Language = .system
    var theme: AppTheme = .system
    var mapType: MapType = .standard
    var distanceUnit: DistanceUnit = .kilometre
}
