//
//  DSToastManager.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 7/10/26.
//

import Foundation
import Observation

/// A bounded, scene-owned notification. A new message replaces the previous one.
struct DSToastPresentation: Identifiable {
    let id: UUID
    let message: LocalizedStringResource
    let duration: Duration
    let localizationKey: String?

    init(id: UUID, message: LocalizedStringResource, duration: Duration, localizationKey: String? = nil) {
        self.id = id
        self.message = message
        self.duration = duration
        self.localizationKey = localizationKey
    }

    @MainActor
    func resolvedMessage(locale: Locale, bundle: Bundle = .main) -> LocalizedStringResource {
        guard let localizationKey else { return message }
        return LocalizationManager.localizedResource(
            MessageKey(rawValue: localizationKey), locale: locale, bundle: bundle
        )
    }

    nonisolated private struct MessageKey: LocalizedKey {
        let rawValue: String
    }
}

@MainActor
@Observable
final class DSToastManager {
    private(set) var currentPresentation: DSToastPresentation?

    init(currentPresentation: DSToastPresentation? = nil) {
        self.currentPresentation = currentPresentation
    }

    func show(_ message: LocalizedStringResource, duration: Duration = .seconds(3)) {
        currentPresentation = DSToastPresentation(id: UUID(), message: message, duration: duration)
    }

    /// Retains the owning feature's key so a visible toast follows app-language changes.
    func show(_ key: some LocalizedKey, duration: Duration = .seconds(3)) {
        currentPresentation = DSToastPresentation(
            id: UUID(),
            message: LocalizedStringResource(String.LocalizationValue(key.rawValue)),
            duration: duration,
            localizationKey: key.rawValue
        )
    }

    /// A cancelled timer or an old close action must not dismiss a replacement.
    func dismiss(presentationID: UUID? = nil) {
        if let presentationID, currentPresentation?.id != presentationID { return }
        currentPresentation = nil
    }
}
