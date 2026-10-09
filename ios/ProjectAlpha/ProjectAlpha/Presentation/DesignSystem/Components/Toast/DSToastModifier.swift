//
//  DSToastModifier.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 7/10/26.
//

import Accessibility
import SwiftUI

/// Install once inside the scene's safe-area-respecting root content.
struct DSToastModifier: ViewModifier {
    let manager: DSToastManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    if let presentation = manager.currentPresentation {
                        let topInset = min(DSSpacing.small, max(0, geometry.size.height - DSToastMetrics.minimumHitSize))
                        DSToastView(
                            presentation: presentation,
                            maximumHeight: max(0, geometry.size.height - topInset)
                        ) {
                            manager.dismiss(presentationID: presentation.id)
                        }
                        .id(presentation.id)
                        .padding(.horizontal, DSSpacing.large)
                        .padding(.top, topInset)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: manager.currentPresentation?.id)
            .task(id: taskIdentity) {
                guard let presentation = manager.currentPresentation else { return }
                if voiceOverEnabled {
                    return
                }
                do {
                    try await Task.sleep(for: max(presentation.duration, .zero))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                manager.dismiss(presentationID: presentation.id)
            }
            .task(id: announcementIdentity) {
                guard voiceOverEnabled, let presentation = manager.currentPresentation else { return }
                AccessibilityNotification.Announcement(
                    String(localized: presentation.resolvedMessage(locale: locale))
                ).post()
            }
    }

    private var taskIdentity: ToastTaskIdentity {
        ToastTaskIdentity(presentationID: manager.currentPresentation?.id, voiceOverEnabled: voiceOverEnabled)
    }

    private struct ToastTaskIdentity: Equatable {
        let presentationID: UUID?
        let voiceOverEnabled: Bool
    }

    private var announcementIdentity: ToastAnnouncementIdentity {
        ToastAnnouncementIdentity(
            presentationID: manager.currentPresentation?.id,
            voiceOverEnabled: voiceOverEnabled,
            localeIdentifier: locale.identifier
        )
    }

    private struct ToastAnnouncementIdentity: Equatable {
        let presentationID: UUID?
        let voiceOverEnabled: Bool
        let localeIdentifier: String
    }
}

extension View {
    func dsToast(manager: DSToastManager) -> some View {
        modifier(DSToastModifier(manager: manager))
    }
}

#Preview {
    Color.secondary.opacity(0.1)
        .dsToast(manager: DSToastPreviewFixtures.manager())
}

#Preview {
    Color.secondary.opacity(0.1)
        .dsToast(manager: DSToastPreviewFixtures.longMessageManager())
        .frame(width: DSToastPreviewFixtures.constrainedWidth, height: DSToastPreviewFixtures.constrainedHeight)
        .environment(\.dynamicTypeSize, .accessibility5)
}
