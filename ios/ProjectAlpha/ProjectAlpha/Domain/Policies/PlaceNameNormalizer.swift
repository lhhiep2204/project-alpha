import Foundation

/// The compatibility-sensitive identity-name normalization defined for duplicate detection.
nonisolated enum PlaceNameNormalizer {
    static let unnamedManualPinMarker = "dropped-pin"

    static func normalizedIdentityName(_ name: String, source: LocationSource) -> String {
        let collapsed = name
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            return source.isManual ? unnamedManualPinMarker : ""
        }

        return collapsed
            .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }
}
