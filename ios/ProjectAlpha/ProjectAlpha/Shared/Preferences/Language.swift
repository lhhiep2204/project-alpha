import Foundation

nonisolated enum Language: String, CaseIterable, Sendable {
    case system = "System"
    case arabic = "Arabic"
    case bengali = "Bengali"
    case chineseSimplified = "Chinese (Simplified)"
    case dutch = "Dutch"
    case english = "English"
    case french = "French"
    case german = "German"
    case hebrew = "Hebrew"
    case hindi = "Hindi"
    case indonesian = "Indonesian"
    case italian = "Italian"
    case japanese = "Japanese"
    case korean = "Korean"
    case portuguese = "Portuguese"
    case russian = "Russian"
    case spanish = "Spanish"
    case thai = "Thai"
    case turkish = "Turkish"
    case ukrainian = "Ukrainian"
    case vietnamese = "Vietnamese"

    /// The `lproj` folder code used to locate the correct localization bundle.
    var code: String {
        switch self {
        case .system: Locale.preferredLanguages.first ?? "en"
        case .arabic: "ar"
        case .bengali: "bn"
        case .chineseSimplified: "zh-Hans"
        case .dutch: "nl"
        case .english: "en"
        case .french: "fr"
        case .german: "de"
        case .hebrew: "he"
        case .hindi: "hi"
        case .indonesian: "id"
        case .italian: "it"
        case .japanese: "ja"
        case .korean: "ko"
        case .portuguese: "pt"
        case .russian: "ru"
        case .spanish: "es"
        case .thai: "th"
        case .turkish: "tr"
        case .ukrainian: "uk"
        case .vietnamese: "vi"
        }
    }

    /// Whether this language is written right-to-left.
    var isRTL: Bool {
        switch self {
        case .arabic, .hebrew: true
        case .system:
            Locale.Language(identifier: Locale.preferredLanguages.first ?? "en").characterDirection == .rightToLeft
        default: false
        }
    }

    /// The `Locale` corresponding to the selected language, used for MapKit and other locale-aware APIs.
    var locale: Locale {
        if case .system = self { return .current }
        return Locale(identifier: code)
    }
}
