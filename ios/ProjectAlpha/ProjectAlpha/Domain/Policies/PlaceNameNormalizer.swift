import Foundation

/// The compatibility-sensitive identity-name normalization defined for duplicate detection.
nonisolated enum PlaceNameNormalizer {
    static let unnamedManualPinMarker = "dropped-pin"
    private static let whitespaceSeparator = " "
    private static let normalizationLocaleIdentifier = "en_US_POSIX"

    static func normalizedIdentityName(_ name: String, source: LocationSource) -> String {
        let collapsed = name
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: whitespaceSeparator)

        guard !collapsed.isEmpty else {
            return source.isManual ? unnamedManualPinMarker : String()
        }

        return collapsed
            .folding(options: .caseInsensitive, locale: Locale(identifier: normalizationLocaleIdentifier))
            .precomposedStringWithCanonicalMapping
    }
}
