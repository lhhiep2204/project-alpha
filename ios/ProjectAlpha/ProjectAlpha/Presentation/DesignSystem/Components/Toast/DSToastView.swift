//
//  DSToastView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 7/10/26.
//

import SwiftUI

struct DSToastView: View {
    let presentation: DSToastPresentation
    var maximumHeight: CGFloat = .infinity
    let onDismiss: @MainActor () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.locale) private var locale

    var body: some View {
        ViewThatFits(in: .vertical) {
            toastSurface(scrolls: false)
            toastSurface(scrolls: true)
                .frame(maxHeight: maximumHeight)
        }
        .frame(maxHeight: maximumHeight, alignment: .top)
    }

    private var messageText: some View {
        Text(presentation.resolvedMessage(locale: locale))
            .font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(DSToastAccessibilityIdentifier.message)
    }

    private func toastSurface(scrolls: Bool) -> some View {
        toastContent(scrolls: scrolls)
            .padding(.horizontal, DSSpacing.large)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: min(maximumHeight, DSToastMetrics.minimumHitSize))
            .modifier(DSToastSurfaceModifier(reduceTransparency: reduceTransparency))
            .contentShape(Capsule())
            // Keep the scroll view's own drag priority so long messages remain readable.
            // Its surrounding capsule padding still accepts the dismiss gesture.
            .gesture(
                DragGesture(minimumDistance: DSToastMetrics.dismissSwipeDistance)
                    .onEnded { value in
                        if DSToastDismissalPolicy.shouldDismiss(translation: value.translation) {
                            onDismiss()
                        }
                    }
            )
            .contextMenu {
                Button(action: onDismiss) {
                    Text(CommonKeys.close)
                }
            }
            .focusable()
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
            .accessibilityElement(children: scrolls ? .contain : .combine)
            .accessibilityAction(.escape, onDismiss)
            .accessibilityAction(named: Text(CommonKeys.close), onDismiss)
    }

    @ViewBuilder
    private func toastContent(scrolls: Bool) -> some View {
        if scrolls {
            ScrollView(.vertical) {
                messageText.frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier(DSToastAccessibilityIdentifier.messageScrollView)
        } else {
            messageText
        }
    }

    private var verticalPadding: CGFloat {
        min(DSSpacing.small, max(0, (maximumHeight - DSToastMetrics.minimumHitSize) / 2))
    }
}

private struct DSToastSurfaceModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                in: Capsule()
            )
            .glassEffect(reduceTransparency ? .identity : .regular, in: Capsule())
    }
}

/// Only an intentional upward drag dismisses; horizontal and downward drags do not.
nonisolated enum DSToastDismissalPolicy {
    static func shouldDismiss(translation: CGSize) -> Bool {
        translation.height <= -DSToastMetrics.dismissSwipeDistance
            && abs(translation.height) > abs(translation.width)
    }
}

nonisolated enum DSToastMetrics {
    static let minimumHitSize = 44.0
    static let dismissSwipeDistance = 24.0
}

enum DSToastAccessibilityIdentifier {
    static let message = "toast.message"
    static let messageScrollView = "toast.messageScrollView"
}

enum DSToastPreviewFixtures {
    static let identifier = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let message = LocalizedStringResource(String.LocalizationValue(CommonKeys.error.rawValue))
    static let presentation = DSToastPresentation(id: identifier, message: message, duration: .seconds(3))
    static let constrainedHeight = 120.0
    static let constrainedWidth = 320.0
    static let longMessage = LocalizedStringResource(String.LocalizationValue(MapKeys.locationServicesDisabled.rawValue))
    static let longPresentation = DSToastPresentation(id: identifier, message: longMessage, duration: .seconds(3))

    @MainActor
    static func manager() -> DSToastManager {
        DSToastManager(currentPresentation: presentation)
    }

    @MainActor
    static func longMessageManager() -> DSToastManager {
        DSToastManager(currentPresentation: longPresentation)
    }
}

#Preview {
    DSToastView(
        presentation: DSToastPreviewFixtures.longPresentation,
        maximumHeight: DSToastPreviewFixtures.constrainedHeight,
        onDismiss: {}
    )
    .frame(width: DSToastPreviewFixtures.constrainedWidth, height: DSToastPreviewFixtures.constrainedHeight)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview {
    DSToastView(presentation: DSToastPreviewFixtures.presentation, onDismiss: {})
        .padding()
}
