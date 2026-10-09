//
//  CommonToastTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 7/10/26.
//

import CoreGraphics
import Foundation
import Testing
@testable import ProjectAlpha

@MainActor
struct CommonToastTests {
    /// AC-37 / AC-60 / D-17: an intentional upward swipe hides feedback; other drags retain it.
    @Test(arguments: [
        (CGSize(width: 0, height: -60), true),
        (CGSize(width: 0, height: -24), true),
        (CGSize(width: 20, height: -60), true),
        (CGSize(width: -20, height: -60), true),
        (CGSize(width: 0, height: -23), false),
        (CGSize.zero, false),
        (CGSize(width: 0, height: 60), false),
        (CGSize(width: 60, height: 0), false),
        (CGSize(width: -60, height: 0), false),
        (CGSize(width: 60, height: -30), false),
        (CGSize(width: -60, height: -30), false),
        (CGSize(width: 60, height: -60), false)
    ])
    func onlyIntentionalUpwardSwipesDismiss(translation: CGSize, shouldDismiss: Bool) throws {
        let manager = DSToastManager()
        manager.show(DSToastPreviewFixtures.message)
        let presentation = try #require(manager.currentPresentation)

        if DSToastDismissalPolicy.shouldDismiss(translation: translation) {
            manager.dismiss(presentationID: presentation.id)
        }

        if shouldDismiss {
            #expect(manager.currentPresentation == nil)
        } else {
            #expect(manager.currentPresentation?.id == presentation.id)
        }
    }

    /// AC-37 / D-03: obsolete timer, swipe, or accessibility actions cannot hide newer feedback.
    @Test func replacementCannotBeDismissedByAnOldPresentationAction() throws {
        let manager = DSToastManager()
        manager.show(DSToastPreviewFixtures.message)
        let first = try #require(manager.currentPresentation)
        manager.show(DSToastPreviewFixtures.message, duration: .seconds(5))
        let replacement = try #require(manager.currentPresentation)
        #expect(first.id != replacement.id)
        #expect(replacement.duration == .seconds(5))

        manager.dismiss(presentationID: first.id)
        #expect(manager.currentPresentation?.id == replacement.id)
        manager.dismiss(presentationID: replacement.id)
        #expect(manager.currentPresentation == nil)
    }

    /// AC-37 / D-03 / D-11: dismissing feedback belongs to exactly one scene.
    @Test func scenesOwnIndependentToastState() throws {
        let first = DSToastManager()
        let second = DSToastManager()
        first.show(DSToastPreviewFixtures.message)
        #expect(first.currentPresentation != nil)
        #expect(second.currentPresentation == nil)
        second.show(DSToastPreviewFixtures.longMessage)
        let secondPresentationID = try #require(second.currentPresentation).id
        first.dismiss()
        #expect(first.currentPresentation == nil)
        #expect(second.currentPresentation?.id == secondPresentationID)
    }
}
