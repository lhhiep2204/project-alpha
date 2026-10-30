//
//  DSButtonTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 29/10/26.
//

import Observation
import SwiftUI
import UIKit
import XCTest
@testable import ProjectAlpha

/// Native accessibility activation verifies the rendered control and its action.
@MainActor
final class DSButtonTests: XCTestCase {
    func testNativeButtonIsDiscoverableInHarness() async throws {
        // A native control separates host/AX failures from DSButton regressions.
        try await withRenderedButton(Button(CommonKeys.add) {}) { control in
            XCTAssertTrue(control.accessibilityTraits.contains(.button))
        }
    }

    func testActivationEmitsOnceBeforeActionAndSupportsRepeatedActivation() async throws {
        let feedback = DSButtonFeedback()
        var countsAtAction: [Int] = []
        let button = DSButton(CommonKeys.add) {
            countsAtAction.append(feedback.activationCount)
        }
        .environment(\.dsButtonFeedback, feedback)
        .buttonStyle(.bordered)
        try await withRenderedButton(button) { control in
            XCTAssertEqual(feedback.activationCount, 0)
            XCTAssertTrue(control.accessibilityActivate())
            XCTAssertTrue(control.accessibilityActivate())
            XCTAssertEqual(feedback.activationCount, 2)
            XCTAssertEqual(countsAtAction, [1, 2])
        }
    }

    func testDisabledButtonEmitsNeitherFeedbackNorAction() async throws {
        let feedback = DSButtonFeedback()
        var actions = 0
        let button = DSButton(role: .destructive) { actions += 1 } label: {
            Text(CommonKeys.delete)
        }
        .environment(\.dsButtonFeedback, feedback)
        .disabled(true)
        try await withRenderedButton(button) { control in
            XCTAssertTrue(control.accessibilityTraits.contains(.notEnabled))
            _ = control.accessibilityActivate()
            XCTAssertEqual(feedback.activationCount, 0)
            XCTAssertEqual(actions, 0)
        }
    }

    func testFeedbackRemainsOwnedWhenActionRemovesButton() async throws {
        let feedback = DSButtonFeedback()
        let state = ButtonLifetimeState()
        let manager = DSToastManager()
        manager.show(CommonKeys.close, duration: .seconds(60))
        let content = ButtonLifetimeHarness(state: state)
            .dsToast(manager: manager)
            .modifier(DSButtonFeedbackHost(feedback: feedback))
        try await withRenderedButton(content) { control, root in
            XCTAssertTrue(control.accessibilityActivate())
            XCTAssertFalse(state.isVisible)
            root.setNeedsLayout()
            root.layoutIfNeeded()
            await self.fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated {
                    !self.accessibilityObjects(in: root).contains { $0.accessibilityTraits.contains(.button) }
                }
            }, object: nil)], timeout: 5)
            XCTAssertEqual(feedback.activationCount, 1)
        }
    }

    func testOverlayButtonSharesSceneOwnerAndDismissesWithoutLosingFeedback() async throws {
        let feedback = DSButtonFeedback()
        let state = ButtonLifetimeState()
        let manager = DSToastManager()
        manager.show(CommonKeys.close, duration: .seconds(60))
        // Overlay composition follows AppRootView: feedback wraps the toast and content.
        let content = Color.clear
            .dsToast(manager: manager)
            .overlay {
                ButtonLifetimeHarness(state: state)
            }
            .modifier(DSButtonFeedbackHost(feedback: feedback))
        try await withRenderedButton(content) { control in
            XCTAssertTrue(control.accessibilityActivate())
            XCTAssertFalse(state.isVisible)
            XCTAssertEqual(feedback.activationCount, 1)
        }
    }

    private func withRenderedButton<Content: View>(
        _ content: Content,
        check: (NSObject) throws -> Void
    ) async throws {
        try await withRenderedButton(content) { control, _ in try check(control) }
    }

    private func withRenderedButton<Content: View>(
        _ content: Content,
        check: (NSObject, UIView) async throws -> Void
    ) async throws {
        let host = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                self.accessibilityObjects(in: host.view).contains { $0.accessibilityTraits.contains(.button) }
            }
        }, object: nil)], timeout: 5)
        let button = try XCTUnwrap(accessibilityObjects(in: host.view).first {
            $0.accessibilityTraits.contains(.button)
        })
        try await check(button, host.view)
    }

    private func accessibilityObjects(in root: UIView) -> [NSObject] {
        var seen: Set<ObjectIdentifier> = []
        func visit(_ object: NSObject) -> [NSObject] {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return [] }
            var children = (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
            }
            return [object] + children.flatMap(visit) + ((object as? UIView)?.subviews ?? []).flatMap(visit)
        }
        return visit(root)
    }
}

@Observable
@MainActor
private final class ButtonLifetimeState {
    var isVisible = true
}

private struct ButtonLifetimeHarness: View {
    let state: ButtonLifetimeState

    var body: some View {
        if state.isVisible {
            DSButton(CommonKeys.close) { state.isVisible = false }
        }
    }
}
