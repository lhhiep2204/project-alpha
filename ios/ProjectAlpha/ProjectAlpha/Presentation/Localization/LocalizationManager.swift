import SwiftUI

/// Maps the app-owned language preference to scene-local SwiftUI environment values.
/// It intentionally has no mutable global bundle or UIKit appearance side effects.
@MainActor
enum LocalizationManager {
    static func locale(for language: Language) -> Locale {
        language.locale
    }

    static func layoutDirection(for language: Language) -> LayoutDirection {
        language.layoutDirection
    }
}
