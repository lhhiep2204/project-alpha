//
//  ViewOwnershipTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/9/26.
//

import Observation
import SwiftUI
import UIKit
import XCTest
@testable import ProjectAlpha

private enum OwnershipTestValue {
    static let detailReady = "Collection detail rendered ready"
    static let detailRenamed = "Collection detail rendered committed rename"
    static let detailName = "Trips"
    static let renamedDetailName = "Renamed Trips"
    static let localeInvalidated = "Locale dependency invalidated"
    static let featureAppeared = "Feature appeared"
    static let parentReconstructed = "Parent reconstructed"
    static let originalModelLost = "The original model must remain owned by SwiftUI @State"
    static let featureIdentifierPrefix = "feature-"
    static let toastAppeared = "Constrained toast appeared"
    static let toastDismissedWithVoiceOver = "VoiceOver toast dismissed at its configured duration"
    static let editorAppeared = "Collection editor appeared"
    static let editorSavingRendered = "Collection editor rendered saving state"
    static let editorFailureRendered = "Collection editor rendered editable failure state"
    static let editorOriginalName = "Trips"
    static let editorDraftName = "Updated Trips"
    static let disabledTextFieldPredicate = "enabled == NO"
    static let enabledTextFieldPredicate = "enabled == YES"
    static let toastViewport = CGSize(width: 320, height: 120)
    static let minimumInteractiveSize = 44.0
    static let toastGeometryAttachment = "Toast public UIKit layout diagnostics"
    static let toastGeometryLogPrefix = "TOAST_LAYOUT_DIAGNOSTICS "
    static let viewport = "viewport"
    static let fittedSize = "fittedSize"
    static let windowFrame = "windowFrame"
    static let windowBounds = "windowBounds"
    static let windowSafeAreaInsets = "windowSafeAreaInsets"
    static let hostFrame = "hostFrame"
    static let hostBounds = "hostBounds"
    static let hostSafeAreaInsets = "hostSafeAreaInsets"
    static let scrollViews = "scrollViews"
    static let scrollFrame = "scrollFrame"
    static let scrollBounds = "scrollBounds"
    static let scrollContentSize = "scrollContentSize"
    static let scrollAdjustedContentInset = "scrollAdjustedContentInset"
    static let detailReadDiagnostics = "Location detail committed read rendering"
    static let detailReadDiagnosticsPrefix = "DETAIL_READ_DIAGNOSTICS "
    static let detailNavigationKey = "navigationItems"
    static let detailNavigationTitleKey = "title"
    static let detailNavigationActionsKey = "rightActions"
    static let detailFieldsKey = "fields"
    static let detailLabelsKey = "accessibilityLabels"
    static let detailIdentifiersKey = "accessibilityIdentifiers"
    static let detailBoundsKey = "bounds"
    static let detailWindowKey = "hasWindow"
    static let detailHiddenKey = "isHidden"
    static let detailEnabledKey = "isEnabled"
    static let detailInteractionKey = "isUserInteractionEnabled"
    static let detailResponderKey = "canBecomeFirstResponder"
    static let detailHittableKey = "isHittableEditableField"
    static let cameraNotes = "Keep this unsaved location draft"
    static let readSheetAttachment = "Location detail sheet containment"
}

/// Exercises actual SwiftUI state storage, not just references created in a unit test.
@MainActor
final class ViewOwnershipTests: XCTestCase {
    func testMapCardKeepsFactsAndIndependentActionsAccessible() async throws {
        let place = MapQuickPlacePreviewFixtures.searchPlace
        var detailActivations = 0
        let host = UIHostingController(rootView:
            MapQuickPlaceCard(place: place, width: 360, height: 320,
                onClose: {}, onOpenInMaps: {}, onViewDetails: { detailActivations += 1 }, onReferenceHeightChange: { _ in },
                canSave: true, surfaceStyle: .opaque)
                .environment(\.locale, Locale(identifier: LanguageCode.english)))
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
                self.detailAccessibilityObjects(in: host.view).contains { $0.accessibilityLabel == place.address }
            }
        }, object: nil)], timeout: 5)
        let objects = detailAccessibilityObjects(in: host.view)
        let labels = objects.compactMap(\.accessibilityLabel)
        XCTAssertTrue(labels.contains(try XCTUnwrap(place.name)))
        XCTAssertTrue(labels.contains(try XCTUnwrap(place.address)))
        let locale = Locale(identifier: LanguageCode.english)
        for coordinate in [place.coordinate.latitude, place.coordinate.longitude] {
            let formatted = coordinate.formatted(.number.precision(.fractionLength(6)).locale(locale))
            XCTAssertTrue(labels.contains { $0.contains(formatted) }, formatted)
        }
        for label in [MapKeys.viewDetails.rawValue, CommonKeys.close.rawValue,
                      CommonKeys.add.rawValue, CommonKeys.openInMaps.rawValue] {
            XCTAssertTrue(objects.contains { $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.button) }, label)
        }
        let details = try XCTUnwrap(objects.first {
            $0.accessibilityLabel == MapKeys.viewDetails.rawValue && $0.accessibilityTraits.contains(.button)
        })
        XCTAssertTrue(details.accessibilityActivate())
        XCTAssertEqual(detailActivations, 1)
    }

    /// AC-24/60, D-17, approved all-card-actions refinement: a saved card
    /// exposes five full-target actions; Favorite remains in full detail only.
    func testSavedMapCardExposesIndependentDetailActions() async throws {
        try await assertMapCardDetailActions(saved: true)
    }

    /// AC-24/60, D-17: an unsaved card exposes Add, Maps, Copy and Share,
    /// while saved-only mutations remain absent.
    func testUnsavedMapCardExposesOnlyApplicableDetailActions() async throws {
        try await assertMapCardDetailActions(saved: false)
    }

    /// AC-24/60, D-17: limited width retains direct Edit and a native More menu
    /// instead of silently dropping secondary actions or opening detail.
    func testNarrowSavedMapCardKeepsEditAndMoreAccessible() async throws {
        try await assertMapCardDetailActions(saved: true, width: 160)
    }

    /// AC-24/60, D-17: when even two targets do not fit, More remains a full
    /// native target and Edit moves into that menu rather than clipping the card.
    func testExtremelyNarrowSavedMapCardKeepsMoreAccessible() async throws {
        try await assertMapCardDetailActions(saved: true, width: 100)
    }

    private func assertMapCardDetailActions(saved: Bool, width: CGFloat = 360) async throws {
        let narrow = width < 360
        let onlyMore = width < 160
        let place = MapQuickPlacePreviewFixtures.searchPlace
        let payload = LocationDetailPayload(name: try XCTUnwrap(place.name), address: place.address,
            coordinate: place.coordinate, notes: OwnershipTestValue.cameraNotes)
        var detailActivations = 0
        var updateActivations = 0
        var mapsActivations = 0
        var favoriteActivations = 0
        var deleteActivations = 0
        var copyFeedback: [LocationKeys] = []
        let configuration = MapQuickCardActionConfiguration(payload: payload, isFavorite: false, canMutate: true,
            onFavorite: { favoriteActivations += 1 }, onDelete: { deleteActivations += 1 },
            onCopied: { copyFeedback.append($0) })
        let host = UIHostingController(rootView:
            MapQuickPlaceCard(place: place, width: width, height: 320,
                onClose: {}, onOpenInMaps: { mapsActivations += 1 },
                onViewDetails: { detailActivations += 1 }, onReferenceHeightChange: { _ in },
                showsClose: false, isSaved: saved, canSave: true,
                onSave: { updateActivations += 1 }, surfaceStyle: .opaque, detailActions: configuration)
                .environment(\.locale, Locale(identifier: LanguageCode.english)))
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
                self.detailAccessibilityObjects(in: host.view).contains {
                    $0.accessibilityLabel == (narrow ? CommonKeys.moreActions.rawValue : CommonKeys.share.rawValue)
                        && $0.accessibilityTraits.contains(.button)
                }
            }
        }, object: nil)], timeout: 5)
        let buttons = detailAccessibilityObjects(in: host.view).filter { $0.accessibilityTraits.contains(.button) }
        if narrow {
            let expectedLabels = onlyMore ? [CommonKeys.moreActions.rawValue]
                : [CommonKeys.edit.rawValue, CommonKeys.moreActions.rawValue]
            for label in expectedLabels {
                let matches = buttons.filter { $0.accessibilityLabel == label }
                XCTAssertEqual(matches.count, 1, label)
                let action = try XCTUnwrap(matches.first)
                XCTAssertGreaterThanOrEqual(action.accessibilityFrame.width, OwnershipTestValue.minimumInteractiveSize, label)
                XCTAssertGreaterThanOrEqual(action.accessibilityFrame.height, OwnershipTestValue.minimumInteractiveSize, label)
            }
            if onlyMore {
                XCTAssertFalse(buttons.contains { $0.accessibilityLabel == CommonKeys.edit.rawValue })
            } else {
                let update = try XCTUnwrap(buttons.first { $0.accessibilityLabel == CommonKeys.edit.rawValue })
                XCTAssertTrue(update.accessibilityActivate())
            }
            XCTAssertEqual(updateActivations, onlyMore ? 0 : 1)
            XCTAssertEqual(detailActivations, 0)
            XCTAssertEqual(mapsActivations, 0)
            XCTAssertEqual(favoriteActivations, 0)
            XCTAssertEqual(deleteActivations, 0)
            XCTAssertTrue(copyFeedback.isEmpty)
            return
        }
        let expectedLabels = [saved ? CommonKeys.edit.rawValue : CommonKeys.add.rawValue,
            CommonKeys.openInMaps.rawValue, CommonKeys.copy.rawValue, CommonKeys.share.rawValue]
            + (saved ? [CommonKeys.delete.rawValue] : [])
        for label in expectedLabels {
            let matches = buttons.filter { $0.accessibilityLabel == label }
            XCTAssertEqual(matches.count, 1, label)
            let action = try XCTUnwrap(matches.first)
            XCTAssertGreaterThanOrEqual(action.accessibilityFrame.width, OwnershipTestValue.minimumInteractiveSize, label)
            XCTAssertGreaterThanOrEqual(action.accessibilityFrame.height, OwnershipTestValue.minimumInteractiveSize, label)
        }
        XCTAssertFalse(buttons.contains { $0.accessibilityLabel == CommonKeys.moreActions.rawValue })
        XCTAssertFalse(buttons.contains { $0.accessibilityLabel == LocationKeys.addFavorite.rawValue })
        if !saved {
            XCTAssertFalse(buttons.contains { $0.accessibilityLabel == LocationKeys.addFavorite.rawValue })
            XCTAssertFalse(buttons.contains { $0.accessibilityLabel == CommonKeys.delete.rawValue })
        }
        XCTAssertEqual(detailActivations, 0)
        for label in [saved ? CommonKeys.edit.rawValue : CommonKeys.add.rawValue,
                      CommonKeys.openInMaps.rawValue] {
            let action = try XCTUnwrap(buttons.first { $0.accessibilityLabel == label })
            XCTAssertTrue(action.accessibilityActivate(), label)
        }
        if saved {
            for label in [CommonKeys.delete.rawValue] {
                let action = try XCTUnwrap(buttons.first { $0.accessibilityLabel == label })
                XCTAssertTrue(action.accessibilityActivate(), label)
            }
        }
        XCTAssertEqual(updateActivations, 1)
        XCTAssertEqual(mapsActivations, 1)
        XCTAssertEqual(favoriteActivations, 0)
        XCTAssertEqual(deleteActivations, saved ? 1 : 0)
        XCTAssertTrue(copyFeedback.isEmpty)
        XCTAssertEqual(detailActivations, 0)
    }

    /// AC-24/60, D-17: Maps and native Share remain in their owning read-detail sheet.
    func testReadDetailMapsAndShareActionsAreInsidePresentedSheet() async throws {
        let state = PhotoSheetHarnessState()
        let host = UIHostingController(rootView: DetailReadSheetHarness(state: state))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        state.showEditor = true
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                guard let sheet = host.presentedViewController, !sheet.isBeingPresented else { return false }
                return sheet.view.window != nil
            }
        }, object: nil)], timeout: 5)
        let sheet = try XCTUnwrap(host.presentedViewController)
        attachDetailReadDiagnostics(in: sheet.view, controller: sheet)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = OwnershipTestValue.readSheetAttachment
        attachment.lifetime = .keepAlways
        add(attachment)
        let buttons = detailAccessibilityObjects(in: sheet.view).filter { $0.accessibilityTraits.contains(.button) }
        let sheetFrame = sheet.view.convert(sheet.view.bounds, to: nil)
        for label in [CommonKeys.openInMaps.rawValue, CommonKeys.share.rawValue] {
            let matches = buttons.filter { $0.accessibilityLabel == label }
            XCTAssertEqual(matches.count, 1, label)
            let action = try XCTUnwrap(matches.first)
            XCTAssertTrue(sheetFrame.contains(action.accessibilityFrame), label)
            XCTAssertGreaterThanOrEqual(action.accessibilityFrame.width, OwnershipTestValue.minimumInteractiveSize, label)
            XCTAssertGreaterThanOrEqual(action.accessibilityFrame.height, OwnershipTestValue.minimumInteractiveSize, label)
        }
    }

    /// AC-24/44/45/47, D-03/D-13: the real Save onChange returns a read-origin sheet to read in place.
    func testNewDetailSaveKeepsSameSheetAndShowsCommittedReadMode() async throws {
        try await assertDetailSaveKeepsSameSheet(saved: false)
    }

    func testSavedDetailSaveKeepsSameSheetAndShowsCommittedReadMode() async throws {
        try await assertDetailSaveKeepsSameSheet(saved: true)
    }

    private func assertDetailSaveKeepsSameSheet(saved: Bool) async throws {
        let repository = DetailPresentationRepository()
        let original = saved ? try DetailPresentationFixture.saved() : nil
        let candidate = PlaceCandidate(id: UUID(), source: .manualCoordinate, placeIdentity: nil,
            name: DetailPresentationFixture.name, address: nil, category: nil,
            coordinate: try Coordinate(latitude: 10, longitude: 20))
        let model: LocationCaptureModel
        if let original {
            model = LocationCaptureModel(savedLocation: original, repository: repository,
                collectionRepository: DetailPresentationCollections())
        } else {
            model = LocationCaptureModel(candidate: candidate, destinationCollectionID: UUID(),
                repository: repository, collectionRepository: DetailPresentationCollections(),
                createdAt: DetailPresentationFixture.date)
        }
        model.notes = DetailPresentationFixture.editedNotes
        let place = MapQuickPlace(id: original.map { .savedLocation($0.id) } ?? .searchCandidate(candidate.id),
            name: candidate.name, address: nil, coordinate: candidate.coordinate,
            horizontalAccuracyMetres: nil, timestamp: nil, placeIdentity: nil)
        let context = LocationDetailsReadContext(place: place, savedLocation: original)
        let state = PhotoSheetHarnessState()
        let host = UIHostingController(rootView: DetailSaveSheetHarness(state: state, model: model, context: context))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        state.showEditor = true
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                guard let parent = host.presentedViewController else { return false }
                return parent.viewIfLoaded?.window != nil && !parent.isBeingPresented
                    && !self.descendantTextFields(in: parent.view).isEmpty
            }
        }, object: nil)], timeout: 5)
        let parent = try XCTUnwrap(host.presentedViewController)
        await model.save()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                // This host owns UIKit presentation lifecycle; SwiftUI content accessibility
                // is checked through the system UI tree, not UIKit subview enumeration.
                self.detailNavigationItems(in: parent).contains { $0.title == MapKeys.viewDetails.rawValue }
            }
        }, object: nil)], timeout: 5)
        XCTAssertTrue(host.presentedViewController === parent)
        XCTAssertTrue(state.showEditor)
        XCTAssertEqual(state.dismissals, 0)
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                self.descendantTextFields(in: parent.view).allSatisfy {
                    !self.isHittableEditableField($0, in: parent.view)
                }
            }
        }, object: nil)], timeout: 5)
        attachDetailReadDiagnostics(in: parent.view, controller: parent)
        XCTAssertFalse(model.isEditing)
        XCTAssertTrue(descendantTextFields(in: parent.view).filter {
            isHittableEditableField($0, in: parent.view)
        }.isEmpty)
        XCTAssertEqual(model.commit?.location.notes, DetailPresentationFixture.editedNotes)
        // Pure presentation tests verify committed notes before observation;
        // rendered controls/text belong to the UI acceptance boundary.
        let creates = await repository.creates.count
        let updates = await repository.updates.count
        XCTAssertEqual(creates, saved ? 0 : 1)
        XCTAssertEqual(updates, saved ? 1 : 0)
    }

    /// Recycled Form backing views may remain descendants after read mode replaces their rows.
    /// Only an enabled field actually reachable through the rendered hit-test tree is an editor control.
    private func isHittableEditableField(_ field: UITextField, in root: UIView) -> Bool {
        guard field.isEnabled, field.isUserInteractionEnabled, let window = field.window,
              !field.bounds.isEmpty else { return false }
        var ancestor: UIView? = field
        while let view = ancestor {
            if view.isHidden || view.alpha <= 0.01 || !view.isUserInteractionEnabled { return false }
            ancestor = view.superview
        }
        let center = CGPoint(x: field.bounds.midX, y: field.bounds.midY)
        let rootPoint = field.convert(center, to: root)
        guard root.bounds.contains(rootPoint) else { return false }
        let hit = window.hitTest(field.convert(center, to: window), with: nil)
        return hit === field || hit?.isDescendant(of: field) == true
    }

    private func detailNavigationItems(in controller: UIViewController) -> [UINavigationItem] {
        let ownItems: [UINavigationItem]
        if let navigation = controller as? UINavigationController {
            ownItems = [navigation.navigationBar.topItem, navigation.topViewController?.navigationItem].compactMap { $0 }
        } else { ownItems = [] }
        return ownItems + controller.children.flatMap { detailNavigationItems(in: $0) }
    }

    private func attachDetailReadDiagnostics(in root: UIView, controller: UIViewController) {
        let objects = detailAccessibilityObjects(in: root)
        let diagnostics: [String: Any] = [
            OwnershipTestValue.detailNavigationKey: detailNavigationItems(in: controller).map { item in
                [
                    OwnershipTestValue.detailNavigationTitleKey: item.title ?? String(),
                    OwnershipTestValue.detailNavigationActionsKey: (item.rightBarButtonItems ?? []).map {
                        $0.title ?? $0.accessibilityLabel ?? String()
                    }
                ] as [String: Any]
            },
            OwnershipTestValue.detailFieldsKey: descendantTextFields(in: root).map { field in
                [
                    OwnershipTestValue.detailBoundsKey: String(describing: field.convert(field.bounds, to: root)),
                    OwnershipTestValue.detailWindowKey: field.window != nil,
                    OwnershipTestValue.detailHiddenKey: field.isHidden,
                    OwnershipTestValue.detailEnabledKey: field.isEnabled,
                    OwnershipTestValue.detailInteractionKey: field.isUserInteractionEnabled,
                    OwnershipTestValue.detailResponderKey: field.canBecomeFirstResponder,
                    OwnershipTestValue.detailHittableKey: isHittableEditableField(field, in: root)
                ] as [String: Any]
            },
            OwnershipTestValue.detailLabelsKey: objects.compactMap(\.accessibilityLabel),
            OwnershipTestValue.detailIdentifiersKey: objects.compactMap {
                ($0 as? UIView)?.accessibilityIdentifier ?? ($0 as? UIAccessibilityElement)?.accessibilityIdentifier
            }
        ]
        let diagnosticsText = String(describing: diagnostics)
        print(OwnershipTestValue.detailReadDiagnosticsPrefix + diagnosticsText)
        let attachment = XCTAttachment(string: diagnosticsText)
        attachment.name = OwnershipTestValue.detailReadDiagnostics
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func detailAccessibilityObjects(in root: UIView) -> [NSObject] {
        var seen: Set<ObjectIdentifier> = []
        func visit(_ object: NSObject) -> [NSObject] {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return [] }
            var children = (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
            }
            let views = (object as? UIView)?.subviews ?? []
            return [object] + children.flatMap(visit) + views.flatMap(visit)
        }
        return visit(root)
    }

    /// AC-45 / INV-08/09: actual editor sheets must retain ownership around child pickers.
    /// Camera uses the simulator fallback; hardware capture and actual menu taps are separate UI checks.
    func testCameraChildKeepsParentLocationSheetAndDraft() async throws {
        try await assertPhotoChildKeepsParent(camera: true)
    }

    func testLibraryChildKeepsParentLocationSheetAndDraft() async throws {
        try await assertPhotoChildKeepsParent(camera: false)
    }

    private func assertPhotoChildKeepsParent(camera: Bool) async throws {
        let model = LocationEditorPreview.photoModel()
        model.notes = OwnershipTestValue.cameraNotes
        let draft = model.draft
        let mediaDraftID = model.mediaDraftID
        let state = PhotoSheetHarnessState()
        let photos = LocationPhotoPresentation()
        let host = UIHostingController(rootView: PhotoSheetHarness(state: state, model: model, photos: photos))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        state.showEditor = true
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                host.presentedViewController?.viewIfLoaded?.window != nil
                    && host.presentedViewController?.isBeingPresented == false
            }
        }, object: nil)], timeout: 5)
        let parent = try XCTUnwrap(host.presentedViewController)
        parent.view.layoutIfNeeded()
        for scroll in descendantScrollViews(in: parent.view) where scroll.contentSize.height > scroll.bounds.height {
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
                y: max(-scroll.adjustedContentInset.top,
                       scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            scroll.layoutIfNeeded()
        }
        if camera { photos.showCamera = true } else { photos.showPhotoLibrary = true }
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                parent.presentedViewController?.viewIfLoaded?.window != nil
                    && parent.presentedViewController?.isBeingPresented == false
            }
        }, object: nil)], timeout: 5)
        let child = try XCTUnwrap(parent.presentedViewController)
        // A covered Form can recycle its photo row during sheet/viewport changes.
        // The child belongs to the editor even after that row leaves the viewport.
        for scroll in descendantScrollViews(in: parent.view) where scroll.contentSize.height > scroll.bounds.height {
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: false)
            scroll.layoutIfNeeded()
        }
        let parentDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                host.presentedViewController !== parent || parent.isBeingDismissed
                    || !state.showEditor || state.dismissals != 0
                    || parent.presentedViewController !== child || child.isBeingDismissed
            }
        }, object: nil)
        parentDismissed.isInverted = true
        await fulfillment(of: [parentDismissed], timeout: 1)
        if camera { photos.showCamera = false } else { photos.showPhotoLibrary = false }
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { parent.presentedViewController == nil }
        }, object: nil)], timeout: 5)
        XCTAssertTrue(host.presentedViewController === parent)
        XCTAssertTrue(state.showEditor)
        XCTAssertEqual(state.dismissals, 0)
        XCTAssertEqual(model.draft, draft)
        XCTAssertEqual(model.mediaDraftID, mediaDraftID)
        XCTAssertNil(model.commit)
        XCTAssertFalse(model.isCancelled)
    }

    /// AC-05/63, D-01/03/19: the real detail view keeps observing after loading changes content.
    /// This is UIKit/SwiftUI lifecycle coverage, not manual first-frame or modal-interaction evidence.
    func testCollectionDetailKeepsReadyContentAndReceivesLaterCommit() async throws {
        let id = UUID()
        let collection = Collection(id: id, name: OwnershipTestValue.detailName, isDefault: false,
                                    createdAt: Date(timeIntervalSince1970: 1),
                                    updatedAt: Date(timeIntervalSince1970: 1), revision: 1)
        let initial = CollectionListSnapshot(
            collections: [CollectionSummary(collection: collection, locationCount: 0)], libraryRevision: 1
        )
        let repository = DetailLifecycleRepository(initial: initial)
        let router = Router<HomeRoute>(paths: [.collection(id: id)], root: .root)
        let model = CollectionDetailViewModel(collectionID: id, repository: repository, router: router)
        let ready = expectation(description: OwnershipTestValue.detailReady)
        ready.assertForOverFulfill = false
        let renamed = expectation(description: OwnershipTestValue.detailRenamed)
        renamed.assertForOverFulfill = false
        let host = UIHostingController(rootView: DetailLifecycleHarness(
            model: model,
            ready: { ready.fulfill() },
            renamed: { renamed.fulfill() }
        ).environment(SceneCoordinator()))
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
        // Expectations acknowledge rendered state transitions; no sleep orders the stream.
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(model.phase, .ready)
        let updated = Collection(id: id, name: OwnershipTestValue.renamedDetailName, isDefault: false,
                                 createdAt: collection.createdAt,
                                 updatedAt: Date(timeIntervalSince1970: 2), revision: 2)
        await repository.publish(CollectionListSnapshot(
            collections: [CollectionSummary(collection: updated, locationCount: 0)], libraryRevision: 2
        ))
        await fulfillment(of: [renamed], timeout: 5)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.collection?.collection, updated)
        XCTAssertEqual(model.displayTitle(hint: nil), OwnershipTestValue.renamedDetailName)
        XCTAssertEqual(router.paths, [.collection(id: id)])
        let subscriptions = await repository.subscriptionCount
        XCTAssertEqual(subscriptions, 1)
        await repository.finish()
    }

    /// AC-37 / AC-60: the real SwiftUI toast keeps long AX text scrollable in a short scene.
    /// This hosted lifecycle check supplements, rather than replaces, assistive/device QA.
    func testToastLongAccessibilityTextFitsShortViewportAndScrolls() async throws {
        let appeared = expectation(description: OwnershipTestValue.toastAppeared)
        let host = UIHostingController(rootView:
            DSToastView(
                presentation: DSToastPreviewFixtures.longPresentation,
                maximumHeight: OwnershipTestValue.toastViewport.height,
                onDismiss: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .onAppear { appeared.fulfill() }
        )
        // This fixture's viewport is the toast component's content area, rather than
        // a scene including system chrome. The modifier integration below owns safe areas.
        host.safeAreaRegions = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame.size = OwnershipTestValue.toastViewport
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        await fulfillment(of: [appeared], timeout: 5)
        host.view.frame = CGRect(origin: .zero, size: OwnershipTestValue.toastViewport)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let fitted = host.sizeThatFits(in: OwnershipTestValue.toastViewport)
        let diagnostics: [String: Any] = [
            OwnershipTestValue.viewport: String(describing: OwnershipTestValue.toastViewport),
            OwnershipTestValue.fittedSize: String(describing: fitted),
            OwnershipTestValue.windowFrame: String(describing: window.frame),
            OwnershipTestValue.windowBounds: String(describing: window.bounds),
            OwnershipTestValue.windowSafeAreaInsets: String(describing: window.safeAreaInsets),
            OwnershipTestValue.hostFrame: String(describing: host.view.frame),
            OwnershipTestValue.hostBounds: String(describing: host.view.bounds),
            OwnershipTestValue.hostSafeAreaInsets: String(describing: host.view.safeAreaInsets),
            OwnershipTestValue.scrollViews: descendantScrollViews(in: host.view).map { scroll in
                [
                    OwnershipTestValue.scrollFrame: String(describing: scroll.convert(scroll.bounds, to: host.view)),
                    OwnershipTestValue.scrollBounds: String(describing: scroll.bounds),
                    OwnershipTestValue.scrollContentSize: String(describing: scroll.contentSize),
                    OwnershipTestValue.scrollAdjustedContentInset: String(describing: scroll.adjustedContentInset)
                ]
            }
        ]
        let diagnosticsData = try JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys])
        let diagnosticsText = String(decoding: diagnosticsData, as: UTF8.self)
        let attachment = XCTAttachment(string: diagnosticsText)
        attachment.name = OwnershipTestValue.toastGeometryAttachment
        attachment.lifetime = .keepAlways
        add(attachment)
        print(OwnershipTestValue.toastGeometryLogPrefix + diagnosticsText)
        XCTAssertLessThanOrEqual(fitted.height, OwnershipTestValue.toastViewport.height)
        XCTAssertGreaterThanOrEqual(fitted.height, OwnershipTestValue.minimumInteractiveSize)
        let scroll = try XCTUnwrap(descendantScrollViews(in: host.view).first)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertGreaterThan(scroll.bounds.height, 0)
        XCTAssertTrue(host.view.bounds.contains(scroll.convert(scroll.bounds, to: host.view)))
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
        XCTAssertGreaterThan(scroll.contentOffset.y, 0)
    }

    /// AC-37 / AC-60: scene-level toast uses the real safe-area proposal at AX text sizes.
    /// Swipe dismissal and assistive operability require the separate UI/device gate.
    func testToastModifierKeepsScrollableTextInsideSceneSafeArea() async throws {
        let appeared = expectation(description: OwnershipTestValue.toastAppeared)
        let manager = DSToastManager(currentPresentation: DSToastPresentation(
            id: DSToastPreviewFixtures.identifier,
            message: DSToastPreviewFixtures.longMessage,
            duration: .seconds(3_600)
        ))
        let host = UIHostingController(rootView:
            Color.clear
                .dsToast(manager: manager)
                .environment(\.dynamicTypeSize, .accessibility5)
                .onAppear { appeared.fulfill() }
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame.size = OwnershipTestValue.toastViewport
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            manager.dismiss()
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        await fulfillment(of: [appeared], timeout: 5)
        host.view.frame = CGRect(origin: .zero, size: OwnershipTestValue.toastViewport)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let safeViewport = host.view.safeAreaLayoutGuide.layoutFrame
        let scroll = try XCTUnwrap(descendantScrollViews(in: host.view).first)
        XCTAssertTrue(safeViewport.contains(scroll.convert(scroll.bounds, to: host.view)))
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertGreaterThan(scroll.bounds.height, 0)
    }

    /// AC-37/D-17: VoiceOver announcement must not suppress automatic dismissal.
    /// The zero-duration fixture is observed through a state transition, without a timing sleep.
    func testToastAutomaticallyDismissesWhileVoiceOverIsEnabled() async throws {
        let dismissed = expectation(description: OwnershipTestValue.toastDismissedWithVoiceOver)
        let manager = DSToastManager(currentPresentation: DSToastPresentation(
            id: DSToastPreviewFixtures.identifier,
            message: DSToastPreviewFixtures.message,
            duration: .zero
        ))
        withObservationTracking {
            _ = manager.currentPresentation?.id
        } onChange: {
            dismissed.fulfill()
        }
        let host = UIHostingController(rootView:
            Color.clear.modifier(DSToastModifier(manager: manager, voiceOverOverride: true))
        )
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
        await fulfillment(of: [dismissed], timeout: 5)
        XCTAssertNil(manager.currentPresentation)
    }

    /// AC-41/INV-07/D-09: the hosted collection name field cannot be edited during a pending save,
    /// then becomes editable again after the repository reports failure without dropping the draft.
    func testCollectionEditorFieldLocksDuringSaveAndUnlocksAfterFailure() async throws {
        let original = Collection(
            id: UUID(), name: OwnershipTestValue.editorOriginalName, isDefault: false,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2), revision: 1
        )
        let repository = SuspendedCollectionUpdateRepository()
        let model = CollectionEditorViewModel(
            useCases: CollectionUseCases(repository: repository), target: .edit(original)
        )
        model.name = OwnershipTestValue.editorDraftName
        let appeared = expectation(description: OwnershipTestValue.editorAppeared)
        let saving = expectation(description: OwnershipTestValue.editorSavingRendered)
        let failed = expectation(description: OwnershipTestValue.editorFailureRendered)
        let host = UIHostingController(rootView: EditorSavingHarness(
            model: model,
            appeared: { appeared.fulfill() },
            saving: { saving.fulfill() },
            failed: { failed.fulfill() }
        ))
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
        await fulfillment(of: [appeared], timeout: 5)
        let save = Task { await model.save(now: Date(timeIntervalSince1970: 3)) }
        await repository.started.wait()
        await fulfillment(of: [saving], timeout: 5)
        let nameField = try XCTUnwrap(descendantTextFields(in: host.view).first)
        let disabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: OwnershipTestValue.disabledTextFieldPredicate), object: nameField
        )
        await fulfillment(of: [disabled], timeout: 5)
        XCTAssertFalse(nameField.isEnabled)
        XCTAssertEqual(model.name, OwnershipTestValue.editorDraftName)

        await repository.release.open()
        let saved = await save.value
        XCTAssertFalse(saved)
        await fulfillment(of: [failed], timeout: 5)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: OwnershipTestValue.enabledTextFieldPredicate), object: nameField
        )
        await fulfillment(of: [enabled], timeout: 5)
        XCTAssertTrue(nameField.isEnabled)
        XCTAssertEqual(model.name, OwnershipTestValue.editorDraftName)
    }

    private func descendantScrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { descendantScrollViews(in: $0) }
    }

    private func descendantTextFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { descendantTextFields(in: $0) }
    }

    func testFeatureModelsSurviveParentReconstruction() async throws {
        let repository = SwiftDataCollectionRepository(store: LibraryStore(
            container: try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
        ))
        try await assertRetained(factory: {
            HomeViewModel(
                repository: repository,
                useCases: CollectionUseCases(repository: repository)
            )
        }, content: { HomeView(viewModel: $0, selection: .constant(nil)) })
        try await assertRetained(factory: {
            MapViewModel(deviceLocationService: MapPresentationLocationService())
        }, content: { MapView(viewModel: $0, rendersLiveMap: false) })
    }

    func testLanguageChangesInvalidateObservedLocale() async {
        let preferences = AppPreferences(store: MemoryPreferences())
        let changed = expectation(description: OwnershipTestValue.localeInvalidated)
        withObservationTracking {
            _ = preferences.language.locale
        } onChange: {
            changed.fulfill()
        }
        preferences.language = .vietnamese
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(preferences.language.locale.identifier, LanguageCode.vietnamese)
    }

    private func assertRetained<Model: AnyObject, Content: View>(
        factory: @escaping @MainActor () -> Model,
        content: @escaping @MainActor (Model) -> Content
    ) async throws {
        let signal = RenderSignal()
        let probe = ModelProbe()
        let appeared = expectation(description: OwnershipTestValue.featureAppeared)
        let updated = expectation(description: OwnershipTestValue.parentReconstructed)
        let host = UIHostingController(rootView: OwnershipHarness(
            signal: signal, probe: probe, factory: factory, content: content,
            appeared: { appeared.fulfill() }, updated: { updated.fulfill() }
        )
            .environment(AppPreferences(store: MemoryPreferences()))
            .environment(DSToastManager())
            .environment(SceneCoordinator()))
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
        await fulfillment(of: [appeared], timeout: 5)
        XCTAssertNotNil(probe.first)
        let previousCount = probe.constructions
        signal.revision += 1
        await fulfillment(of: [updated], timeout: 5)
        XCTAssertGreaterThan(probe.constructions, previousCount)
        XCTAssertNotNil(probe.first, OwnershipTestValue.originalModelLost)
    }
}

@Observable @MainActor
private final class RenderSignal {
    var revision = 0
}

@MainActor
private final class ModelProbe {
    weak var first: AnyObject?
    var constructions = 0

    func record(_ model: AnyObject) {
        if constructions == 0 { first = model }
        constructions += 1
    }
}

@MainActor
private struct EditorSavingHarness: View {
    @State private var toastManager = DSToastManager()
    let model: CollectionEditorViewModel
    let appeared: () -> Void
    let saving: () -> Void
    let failed: () -> Void

    var body: some View {
        let isSaving = model.isSaving
        NavigationStack { CollectionEditorView(viewModel: model) }
            .environment(toastManager)
            .onAppear(perform: appeared)
            .onChange(of: isSaving) { _, value in
                if value { saving() }
                else { failed() }
            }
    }
}

@MainActor
private struct OwnershipHarness<Model: AnyObject, Content: View>: View {
    let signal: RenderSignal
    let probe: ModelProbe
    let factory: @MainActor () -> Model
    let content: @MainActor (Model) -> Content
    let appeared: () -> Void
    let updated: () -> Void

    var body: some View {
        let revision = signal.revision
        let model = factory()
        let _ = probe.record(model)
        content(model)
            .accessibilityIdentifier(OwnershipTestValue.featureIdentifierPrefix + String(revision))
            .onAppear(perform: appeared)
            .onChange(of: revision) { updated() }
    }
}

@MainActor
private final class MemoryPreferences: PreferenceStore {
    var language: Language = .system
    var theme: AppTheme = .system
    var mapType: MapType = .standard
    var distanceUnit: DistanceUnit = .kilometre
}

@MainActor
private struct DetailLifecycleHarness: View {
    @State private var toastManager = DSToastManager()
    let model: CollectionDetailViewModel
    let ready: () -> Void
    let renamed: () -> Void

    var body: some View {
        NavigationStack {
            CollectionDetailView(viewModel: model)
        }
        .environment(toastManager)
        .onChange(of: model.phase) {
            if model.phase == .ready { ready() }
        }
        .onChange(of: model.collection?.collection.name) {
            if model.collection?.collection.name == OwnershipTestValue.renamedDetailName { renamed() }
        }
    }
}

private enum DetailLifecycleFailure: Error { case unusedOperation }

/// Every subscription receives its own initial result, matching the Domain observation port.
private actor DetailLifecycleRepository: CollectionRepository {
    let initial: CollectionListSnapshot
    private(set) var subscriptionCount = 0
    private var continuations: [AsyncThrowingStream<CollectionListSnapshot, any Error>.Continuation] = []

    init(initial: CollectionListSnapshot) { self.initial = initial }

    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        let (stream, continuation) = AsyncThrowingStream<CollectionListSnapshot, any Error>.makeStream()
        subscriptionCount += 1
        continuations.append(continuation)
        continuation.yield(initial)
        return stream
    }

    func publish(_ snapshot: CollectionListSnapshot) {
        continuations.forEach { $0.yield(snapshot) }
    }

    func finish() {
        continuations.forEach { $0.finish() }
        continuations.removeAll()
    }

    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot {
        throw DetailLifecycleFailure.unusedOperation
    }
    func snapshot() async throws -> CollectionListSnapshot { initial }
    func collection(id: UUID) async throws -> CollectionSummary? {
        initial.collections.first { $0.id == id }
    }
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        throw DetailLifecycleFailure.unusedOperation
    }
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        throw DetailLifecycleFailure.unusedOperation
    }
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit {
        throw DetailLifecycleFailure.unusedOperation
    }
}

@Observable @MainActor
private final class PhotoSheetHarnessState {
    var showEditor = false
    var dismissals = 0
}

@MainActor
private struct PhotoSheetHarness: View {
    @State private var toastManager = DSToastManager()
    @Bindable var state: PhotoSheetHarnessState
    let model: LocationCaptureModel
    let photos: LocationPhotoPresentation

    var body: some View {
        Color.clear.sheet(isPresented: $state.showEditor, onDismiss: { state.dismissals += 1 }) {
            LocationDetailsEditor(model: model, rendersLiveMap: false, photoPresentation: photos)
        }
        .environment(toastManager)
    }
}

@MainActor
private struct DetailSaveSheetHarness: View {
    @State private var toastManager = DSToastManager()
    @Bindable var state: PhotoSheetHarnessState
    let model: LocationCaptureModel
    let context: LocationDetailsReadContext

    var body: some View {
        Color.clear.sheet(isPresented: $state.showEditor, onDismiss: { state.dismissals += 1 }) {
            LocationDetailsEditor(model: model, mode: .update, readContext: context,
                rendersLiveMap: false, onBeginUpdate: { model })
                .environment(\.locale, Locale(identifier: LanguageCode.english))
        }
        .environment(toastManager)
    }
}

@MainActor
private struct DetailReadSheetHarness: View {
    @State private var toastManager = DSToastManager()
    @Bindable var state: PhotoSheetHarnessState

    var body: some View {
        Color.clear.sheet(isPresented: $state.showEditor) {
            LocationDetailsEditor(mode: .read,
                readContext: LocationDetailsReadContext(place: MapQuickPlacePreviewFixtures.searchPlace),
                rendersLiveMap: true)
                .environment(\.locale, Locale(identifier: LanguageCode.english))
        }
        .environment(toastManager)
    }
}
