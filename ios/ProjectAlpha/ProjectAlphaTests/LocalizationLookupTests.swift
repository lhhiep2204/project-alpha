//
//  LocalizationLookupTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 24/9/26.
//

import Foundation
import Testing
@testable import ProjectAlpha

/// J-08 / U-17: navigation chrome follows the selected app language.
@MainActor
struct LocalizationLookupTests {
    /// AC-69/U-17: success feedback ships in every supported app language.
    @Test(arguments: Language.allCases.filter { $0 != .system })
    func successToastsHaveTranslatedCatalogEntries(language: Language) {
        for key in [CollectionKeys.saveSucceeded.rawValue, CollectionKeys.deleteSucceeded.rawValue,
                    LocationKeys.saveSucceeded.rawValue, LocationKeys.deleteSucceeded.rawValue] {
            let translated = LocalizationManager.localizedString(ToastSuccessTestKey(rawValue: key), locale: language.locale)
            #expect(!translated.isEmpty)
            if language != .english { #expect(translated != key) }
        }
    }

    /// AC-55/60: the shipping compiled catalog displays both names literally,
    /// even when user text contains punctuation or format-control characters.
    @Test(arguments: Language.allCases.filter { $0 != .system })
    func conflictComparisonPreservesBothUserNames(language: Language) {
        let message = CollectionKeys.conflictComparisonMessage(
            draftName: CollectionCopyFixture.draftName, latestName: CollectionCopyFixture.latestName,
            locale: language.locale)
        #expect(message.contains(CollectionCopyFixture.draftName))
        #expect(message.contains(CollectionCopyFixture.latestName))
        #expect(!message.contains(CollectionCopyFixture.unexpandedObjectPlaceholder))
    }

    /// AC-36/60: real compiled plural resources preserve the localized singular
    /// grammar for one child and expand the collection name and 0/1/2 counts.
    @Test(arguments: CollectionCopyFixture.languages, [Int64(0), 1, 2])
    func deleteConfirmationUsesCorrectCompiledPlural(language: Language, count: Int64) {
        let expected: String
        switch language {
        case .spanish:
            expected = count == 1
                ? CollectionCopyFixture.spanishOne : CollectionCopyFixture.spanishOther(count)
        case .french:
            expected = count <= 1
                ? CollectionCopyFixture.frenchOne(count) : CollectionCopyFixture.frenchOther
        case .italian:
            expected = count == 1
                ? CollectionCopyFixture.italianOne : CollectionCopyFixture.italianOther(count)
        case .portuguese:
            expected = count <= 1
                ? CollectionCopyFixture.portugueseOne(count) : CollectionCopyFixture.portugueseOther
        default:
            Issue.record()
            return
        }
        #expect(CollectionKeys.deleteCollectionMessage(
            name: CollectionCopyFixture.collectionName, count: count, locale: language.locale) == expected)
    }

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

    @Test func toastResourcePreservesSelectedLanguageAndFallback() throws {
        let fixture = try LocalizationBundleFixture()
        defer { fixture.remove() }
        let arabic = LocalizationManager.localizedResource(
            HomeKeys.title, locale: Locale(identifier: Language.arabic.code), bundle: fixture.bundle
        )
        let fallback = LocalizationManager.localizedResource(
            HomeKeys.title, locale: Locale(identifier: Language.french.code), bundle: fixture.bundle
        )
        #expect(String(localized: arabic) == LocalizationBundleFixture.arabicHome)
        #expect(String(localized: fallback) == LocalizationBundleFixture.englishHome)
    }

    @Test func visibleKeyBasedToastRetranslatesWithoutReplacingPresentation() throws {
        let fixture = try LocalizationBundleFixture()
        defer { fixture.remove() }
        let manager = DSToastManager()
        manager.show(HomeKeys.title)
        let presentation = try #require(manager.currentPresentation)
        let english = presentation.resolvedMessage(
            locale: Locale(identifier: Language.english.code), bundle: fixture.bundle
        )
        let arabic = presentation.resolvedMessage(
            locale: Locale(identifier: Language.arabic.code), bundle: fixture.bundle
        )
        #expect(String(localized: english) == LocalizationBundleFixture.englishHome)
        #expect(String(localized: arabic) == LocalizationBundleFixture.arabicHome)
        #expect(manager.currentPresentation?.id == presentation.id)
        #expect(manager.currentPresentation?.duration == .seconds(3))
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

private enum CollectionCopyFixture {
    static let languages: [Language] = [.spanish, .french, .italian, .portuguese]
    static let collectionName = "Trips 50%"
    static let draftName = "Draft: “50% %@” — α"
    static let latestName = "Latest: ‘100% %1$@’ — العربية"
    static let unexpandedObjectPlaceholder = "%2$@"
    static let spanishOne = "¿Eliminar «Trips 50%» y su 1 lugar? Esta acción no se puede deshacer."
    static func spanishOther(_ count: Int64) -> String {
        "¿Eliminar «Trips 50%» y sus \(count) lugares? Esta acción no se puede deshacer."
    }
    static func frenchOne(_ count: Int64) -> String {
        "Supprimer « Trips 50% » et son \(count) lieu ? Cette action est irréversible."
    }
    static let frenchOther = "Supprimer « Trips 50% » et ses 2 lieux ? Cette action est irréversible."
    static let italianOne = "Eliminare “Trips 50%” e il suo 1 luogo? Questa azione non può essere annullata."
    static func italianOther(_ count: Int64) -> String {
        "Eliminare “Trips 50%” e i suoi \(count) luoghi? Questa azione non può essere annullata."
    }
    static func portugueseOne(_ count: Int64) -> String {
        "Excluir “Trips 50%” e seu \(count) local? Esta ação não pode ser desfeita."
    }
    static let portugueseOther = "Excluir “Trips 50%” e seus 2 locais? Esta ação não pode ser desfeita."
}

nonisolated private struct ToastSuccessTestKey: LocalizedKey {
    let rawValue: String
}
