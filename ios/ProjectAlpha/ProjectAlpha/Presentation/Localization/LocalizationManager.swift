//
//  LocalizationManager.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/9/26.
//

import SwiftUI

/// Maps the app-owned language preference to scene-local SwiftUI environment values.
/// It intentionally has no mutable global bundle or UIKit appearance side effects.
@MainActor
enum LocalizationManager {
    private static let localizationDirectoryExtension = "lproj"

    static func locale(for language: Language) -> Locale {
        language.locale
    }

    static func layoutDirection(for language: Language) -> LayoutDirection {
        language.layoutDirection
    }

    /// Carries localized copy across presentation models without losing the selected app language.
    static func localizedResource(
        _ key: some LocalizedKey,
        locale: Locale,
        bundle: Bundle = .main
    ) -> LocalizedStringResource {
        let matches = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: [locale.identifier]
        )
        let resourceBundle: LocalizedStringResource.BundleDescription
        if let identifier = matches.first,
           let url = bundle.url(forResource: identifier, withExtension: localizationDirectoryExtension) {
            resourceBundle = .atURL(url)
        } else {
            resourceBundle = .atURL(bundle.bundleURL)
        }
        return LocalizedStringResource(
            String.LocalizationValue(key.rawValue),
            locale: locale,
            bundle: resourceBundle
        )
    }

    /// Resolves strings used by UIKit-backed navigation chrome from the scene locale.
    /// `String(localized:locale:)` formats values for the locale but still selects
    /// the main bundle's launch language when looking up a string.
    static func localizedString(
        _ key: some LocalizedKey,
        locale: Locale,
        bundle: Bundle = .main
    ) -> String {
        let matches = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: [locale.identifier]
        )
        guard let identifier = matches.first,
              let path = bundle.path(forResource: identifier, ofType: localizationDirectoryExtension),
              let localizedBundle = Bundle(path: path) else {
            return NSLocalizedString(key.rawValue, bundle: bundle, comment: String())
        }
        return NSLocalizedString(key.rawValue, bundle: localizedBundle, comment: String())
    }
}
