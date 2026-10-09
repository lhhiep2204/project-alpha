//
//  Language.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/9/26.
//

import Foundation

/// Stable localization directory identifiers, separate from persisted Language raw values.
nonisolated enum LanguageCode {
    static let arabic = "ar"
    static let bengali = "bn"
    static let chineseSimplified = "zh-Hans"
    static let dutch = "nl"
    static let english = "en"
    static let french = "fr"
    static let german = "de"
    static let hebrew = "he"
    static let hindi = "hi"
    static let indonesian = "id"
    static let italian = "it"
    static let japanese = "ja"
    static let korean = "ko"
    static let portuguese = "pt"
    static let russian = "ru"
    static let spanish = "es"
    static let thai = "th"
    static let turkish = "tr"
    static let ukrainian = "uk"
    static let vietnamese = "vi"
}

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
        case .system: Locale.preferredLanguages.first ?? LanguageCode.english
        case .arabic: LanguageCode.arabic
        case .bengali: LanguageCode.bengali
        case .chineseSimplified: LanguageCode.chineseSimplified
        case .dutch: LanguageCode.dutch
        case .english: LanguageCode.english
        case .french: LanguageCode.french
        case .german: LanguageCode.german
        case .hebrew: LanguageCode.hebrew
        case .hindi: LanguageCode.hindi
        case .indonesian: LanguageCode.indonesian
        case .italian: LanguageCode.italian
        case .japanese: LanguageCode.japanese
        case .korean: LanguageCode.korean
        case .portuguese: LanguageCode.portuguese
        case .russian: LanguageCode.russian
        case .spanish: LanguageCode.spanish
        case .thai: LanguageCode.thai
        case .turkish: LanguageCode.turkish
        case .ukrainian: LanguageCode.ukrainian
        case .vietnamese: LanguageCode.vietnamese
        }
    }

    /// Whether this language is written right-to-left.
    var isRTL: Bool {
        switch self {
        case .arabic, .hebrew: true
        case .system:
            Locale.Language(identifier: Locale.preferredLanguages.first ?? LanguageCode.english).characterDirection == .rightToLeft
        default: false
        }
    }

    /// The `Locale` corresponding to the selected language, used for MapKit and other locale-aware APIs.
    var locale: Locale {
        if case .system = self { return .current }
        return Locale(identifier: code)
    }
}
