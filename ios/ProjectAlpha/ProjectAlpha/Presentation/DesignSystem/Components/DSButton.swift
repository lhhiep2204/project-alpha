//
//  DSButton.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 29/10/26.
//

import Observation
import SwiftUI

/// Scene-local feedback survives an action dismissing its button's presentation.
@Observable
@MainActor
final class DSButtonFeedback {
    private(set) var activationCount = 0

    func activate() {
        activationCount &+= 1
    }
}

private struct DSButtonFeedbackKey: EnvironmentKey {
    static let defaultValue: DSButtonFeedback? = nil
}

extension EnvironmentValues {
    var dsButtonFeedback: DSButtonFeedback? {
        get { self[DSButtonFeedbackKey.self] }
        set { self[DSButtonFeedbackKey.self] = newValue }
    }
}

struct DSButtonFeedbackHost: ViewModifier {
    @State var feedback = DSButtonFeedback()

    func body(content: Content) -> some View {
        content
            .environment(\.dsButtonFeedback, feedback)
            .sensoryFeedback(.impact(weight: .light), trigger: feedback.activationCount)
    }
}

extension View {
    func dsButtonFeedback() -> some View {
        modifier(DSButtonFeedbackHost())
    }
}

/// Native button behavior with the same light impact as map-card activation.
/// Feedback follows activation, rather than pressed-state or gesture changes.
struct DSButton<Label: View>: View {
    @Environment(\.dsButtonFeedback) private var sceneFeedback
    @State private var feedbackTrigger = false
    private let role: ButtonRole?
    private let action: () -> Void
    private let label: Label

    init(
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(role: role) {
            if let sceneFeedback {
                sceneFeedback.activate()
            } else {
                // Standalone previews and isolated hosts have no scene owner.
                feedbackTrigger.toggle()
            }
            action()
        } label: {
            label
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
    }
}

extension DSButton where Label == Text {
    init(_ key: some LocalizedKey, action: @escaping () -> Void) {
        self.init(action: action) { Text(key) }
    }
}

#Preview {
    DSButton(CommonKeys.add) {}
        .buttonStyle(.bordered)
        .padding()
}
