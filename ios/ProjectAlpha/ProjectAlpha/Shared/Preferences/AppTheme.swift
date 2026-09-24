/// User-selectable appearance policy. `.system` preserves the platform default.
nonisolated enum AppTheme: String, CaseIterable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}
