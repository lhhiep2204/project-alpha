import Foundation
import Observation
import SwiftUI
import Testing
@testable import ProjectAlpha

private enum TestValue {
    static let preferenceSuitePrefix = "ProjectAlphaTests."
    static let invalidLanguage = "unsupported-language"
    static let invalidTheme = "unsupported-theme"
    static let invalidMap = "unsupported-map"
    static let invalidDistanceUnit = "unsupported-unit"
    static let catalogPath = "ProjectAlpha/Presentation/Localization/Localizable.xcstrings"
    static let catalogStringsKey = "strings"
    static let catalogSourceLanguageKey = "sourceLanguage"
    static let catalogVersionKey = "version"
    static let catalogVersion = "1.1"
    static let catalogLocalizationsKey = "localizations"
    static let catalogStringUnitKey = "stringUnit"
    static let catalogVariationsKey = "variations"
    static let catalogPluralKey = "plural"
    static let catalogOtherKey = "other"
    static let catalogStateKey = "state"
    static let catalogTranslatedState = "translated"
    static let catalogValueKey = "value"
    static let collectionName = "Travel"
}

@MainActor
struct ArchitectureTests {
    /// D-01: app composition supplies preview collection data through its repository override.
    @Test func previewRepositoryOverrideSuppliesCollectionSnapshot() async throws {
        let preview = PreviewCollectionRepository()
        let app = AppContainer(
            preferenceStore: PreviewPreferenceStore(),
            collectionRepositoryOverride: preview
        )
        let supplied = try await app.collectionRepository()
        let expected = try await preview.snapshot()
        #expect(try await supplied.snapshot() == expected)
        #expect(try await app.collectionRepository().snapshot() == expected)
        #expect(expected.collections.map(\.id) == [Collection.mock.id])
    }

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

    @Test func sceneAndFeatureModelsAreReleased() throws {
        weak var scene: SceneCoordinator?
        weak var home: HomeViewModel?
        weak var map: MapViewModel?
        weak var settings: SettingsViewModel?
        weak var router: Router<HomeRoute>?
        do {
            let owner = SceneCoordinator()
            let repository = SwiftDataCollectionRepository(store: LibraryStore(
                container: try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
            ))
            let homeModel = HomeViewModel(
                router: owner.homeRouter,
                repository: repository,
                useCases: CollectionUseCases(repository: repository)
            )
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
        let suite = TestValue.preferenceSuitePrefix + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(TestValue.invalidLanguage, forKey: UserDefaultsPreferenceStore.Keys.language)
        defaults.set(TestValue.invalidTheme, forKey: UserDefaultsPreferenceStore.Keys.theme)
        defaults.set(TestValue.invalidMap, forKey: UserDefaultsPreferenceStore.Keys.mapType)
        defaults.set(TestValue.invalidDistanceUnit, forKey: UserDefaultsPreferenceStore.Keys.distanceUnit)
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
            .appendingPathComponent(TestValue.catalogPath)
        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try #require(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let strings = try #require(catalog[TestValue.catalogStringsKey] as? [String: Any])
        let requiredKeys = Set([CommonKeys.settings.rawValue]
            + SettingsKeys.allCases.map(\.rawValue)
            + HomeKeys.allCases.map(\.rawValue)
            + MapKeys.allCases.map(\.rawValue))
        let supportedLanguageCodes = Set(Language.allCases
            .filter { $0 != .system }
            .map(\.code))

        #expect(requiredKeys.isSubset(of: Set(strings.keys)))
        #expect(catalog[TestValue.catalogSourceLanguageKey] as? String == LanguageCode.english)
        #expect(catalog[TestValue.catalogVersionKey] as? String == TestValue.catalogVersion)

        for rawEntry in strings.values {
            let entry = try #require(rawEntry as? [String: Any])
            let localizations = try #require(
                entry[TestValue.catalogLocalizationsKey] as? [String: Any]
            )
            #expect(Set(localizations.keys) == supportedLanguageCodes)

            for languageCode in supportedLanguageCodes {
                let localization = try #require(
                    localizations[languageCode] as? [String: Any]
                )
                var stringUnits: [[String: Any]] = []
                if let direct = localization[TestValue.catalogStringUnitKey] as? [String: Any] {
                    stringUnits.append(direct)
                } else {
                    let variations = try #require(
                        localization[TestValue.catalogVariationsKey] as? [String: Any]
                    )
                    let plural = try #require(
                        variations[TestValue.catalogPluralKey] as? [String: Any]
                    )
                    #expect(plural[TestValue.catalogOtherKey] != nil)
                    for rawForm in plural.values {
                        let form = try #require(rawForm as? [String: Any])
                        stringUnits.append(try #require(
                            form[TestValue.catalogStringUnitKey] as? [String: Any]
                        ))
                    }
                }
                #expect(!stringUnits.isEmpty)
                for stringUnit in stringUnits {
                    #expect(stringUnit[TestValue.catalogStateKey] as? String == TestValue.catalogTranslatedState)
                    #expect(!(stringUnit[TestValue.catalogValueKey] as? String ?? String()).isEmpty)
                }
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
        let collection = await Task.detached {
            Collection(id: id, name: TestValue.collectionName,
                       isDefault: false, createdAt: .distantPast,
                       updatedAt: .distantPast, revision: 3)
        }.value
        let returned = await CollectionEcho().echo(collection)
        #expect(returned == collection)
        #expect(returned.id == id)
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
