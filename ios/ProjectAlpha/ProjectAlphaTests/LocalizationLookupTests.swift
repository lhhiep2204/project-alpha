import Foundation
import Testing
@testable import ProjectAlpha

/// J-08 / U-17: navigation chrome follows the selected app language.
@MainActor
struct LocalizationLookupTests {
    @Test func selectedLocaleChoosesMatchingTranslation() throws {
        let fixture = try LocalizationBundleFixture()
        defer { fixture.remove() }

        #expect(LocalizationManager.localizedString(
            HomeKeys.title, locale: Locale(identifier: Language.arabic.code), bundle: fixture.bundle
        ) == LocalizationBundleFixture.arabicHome)
        #expect(LocalizationManager.localizedString(
            HomeKeys.title, locale: Locale(identifier: Language.english.code), bundle: fixture.bundle
        ) == LocalizationBundleFixture.englishHome)
    }

    @Test func unavailableLocaleFallsBackToDevelopmentLanguage() throws {
        let fixture = try LocalizationBundleFixture()
        defer { fixture.remove() }

        #expect(LocalizationManager.localizedString(
            HomeKeys.title, locale: Locale(identifier: Language.french.code), bundle: fixture.bundle
        ) == LocalizationBundleFixture.englishHome)
    }
}

private struct LocalizationBundleFixture {
    static let englishHome = "Home fixture"
    static let arabicHome = "الرئيسية"

    private enum Value {
        static let bundlePrefix = "ProjectAlphaLocalization-"
        static let bundleExtension = ".bundle"
        static let developmentRegionKey = "CFBundleDevelopmentRegion"
        static let bundleIdentifierKey = "CFBundleIdentifier"
        static let bundlePackageTypeKey = "CFBundlePackageType"
        static let bundleIdentifierPrefix = "com.projectalpha.localizationfixture."
        static let bundlePackageType = "BNDL"
        static let infoPlistName = "Info.plist"
        static let localizationDirectoryExtension = ".lproj"
        static let localizableStringsName = "Localizable.strings"
        static let stringsLineFormat = "\"%@\" = \"%@\";\n"
    }

    let url: URL
    let bundle: Bundle

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                Value.bundlePrefix + UUID().uuidString + Value.bundleExtension,
                isDirectory: true
            )
        url = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let info: [String: String] = [
            Value.developmentRegionKey: LanguageCode.english,
            Value.bundleIdentifierKey: Value.bundleIdentifierPrefix + UUID().uuidString,
            Value.bundlePackageTypeKey: Value.bundlePackageType
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info, format: .xml, options: 0
        )
        try infoData.write(to: root.appendingPathComponent(Value.infoPlistName))

        for (language, value) in [(LanguageCode.english, Self.englishHome), (LanguageCode.arabic, Self.arabicHome)] {
            let folder = root.appendingPathComponent(
                language + Value.localizationDirectoryExtension,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try String(format: Value.stringsLineFormat, HomeKeys.title.rawValue, value).write(
                to: folder.appendingPathComponent(Value.localizableStringsName),
                atomically: true,
                encoding: .utf8
            )
        }

        bundle = try #require(Bundle(url: root))
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
