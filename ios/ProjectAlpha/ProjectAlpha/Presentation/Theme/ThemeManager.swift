import SwiftUI

/// Converts the app-owned appearance preference into SwiftUI's native color-scheme policy.
/// Preference state remains exclusively in `AppPreferences`.
@MainActor
enum ThemeManager {
    static func preferredColorScheme(for theme: AppTheme) -> ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
