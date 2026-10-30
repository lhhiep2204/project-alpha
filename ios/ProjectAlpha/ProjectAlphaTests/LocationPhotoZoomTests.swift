//
//  LocationPhotoZoomTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/10/26.
//

import SwiftUI
import Testing
import UIKit
import XCTest
@testable import ProjectAlpha

@MainActor
struct LocationPhotoZoomTests {
    @Test func fittedPortraitAndLandscapeImagesAreCentered() {
        for size in [CGSize(width: 600, height: 800), CGSize(width: 800, height: 400)] {
            let view = makeView(imageSize: size)
            let frame = view.photoView.convert(view.photoView.bounds, to: view)
            #expect(abs(frame.midX - view.bounds.midX) < 0.5)
            #expect(abs(frame.midY - view.bounds.midY) < 0.5)
            #expect(!view.panGestureRecognizer.isEnabled)
        }
    }

    @Test func doubleTapTargetsTheTappedImagePointAndTogglesBackToFit() {
        let view = makeView(imageSize: CGSize(width: 600, height: 800))
        let points = [CGPoint(x: 200, y: 280), CGPoint(x: 400, y: 520)]
        for point in points {
            view.toggleZoom(at: point)
            #expect(abs(view.zoomScale / view.minimumZoomScale - 2) < 0.01)
            let visibleCenter = view.photoView.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), from: view)
            #expect(abs(visibleCenter.x - point.x) < 1)
            #expect(abs(visibleCenter.y - point.y) < 1)
            #expect(view.panGestureRecognizer.isEnabled)
            view.toggleZoom(at: point)
            #expect(view.zoomScale == view.minimumZoomScale)
            #expect(!view.panGestureRecognizer.isEnabled)
        }
    }

    @Test func pageChangeResetsZoomAndRequestsAreAppliedOnlyOnce() {
        let view = makeView(imageSize: CGSize(width: 600, height: 800))
        let request = LocationPhotoZoomRequest(direction: .inward)
        view.apply(request)
        let scale = view.zoomScale
        view.apply(request)
        #expect(view.zoomScale == scale)
        view.setActive(false)
        #expect(view.zoomScale == view.minimumZoomScale)
        view.apply(LocationPhotoZoomRequest(direction: .inward))
        #expect(view.zoomScale == view.minimumZoomScale)
    }

    @Test func resizingRetainsRelativeZoomAndImageFocus() {
        let view = makeView(imageSize: CGSize(width: 600, height: 800))
        let focus = CGPoint(x: 300, y: 400)
        view.toggleZoom(at: focus)
        view.frame.size = CGSize(width: 700, height: 400)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(abs(view.zoomScale / view.minimumZoomScale - 2) < 0.01)
        let center = view.photoView.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), from: view)
        #expect(abs(center.x - focus.x) < 1)
        #expect(abs(center.y - focus.y) < 1)
    }

    @Test func zoomAtEdgesStaysWithinImageAndMaximumScale() {
        let view = makeView(imageSize: CGSize(width: 600, height: 800))
        view.zoom(toScale: view.maximumZoomScale * 10, at: CGPoint(x: 600, y: 800))
        #expect(view.zoomScale == view.maximumZoomScale)
        #expect(view.contentOffset.x <= view.contentSize.width - view.bounds.width + view.contentInset.right + 1)
        #expect(view.contentOffset.y <= view.contentSize.height - view.bounds.height + view.contentInset.bottom + 1)
    }

    @Test func semanticPanMovesZoomedViewportAndClampsAtEdges() {
        let view = makeView(imageSize: CGSize(width: 600, height: 800))
        view.toggleZoom(at: CGPoint(x: 300, y: 400))
        let initial = view.contentOffset
        view.apply(LocationPhotoZoomRequest(direction: .right))
        #expect(view.contentOffset.x > initial.x)
        view.apply(LocationPhotoZoomRequest(direction: .left))
        #expect(view.contentOffset.x < initial.x + 1)
        view.apply(LocationPhotoZoomRequest(direction: .down))
        #expect(view.contentOffset.y > initial.y)
        for _ in 0..<10 { view.apply(LocationPhotoZoomRequest(direction: .up)) }
        #expect(view.contentOffset.y == -view.contentInset.top)
    }

    private func makeView(imageSize: CGSize) -> LocationPhotoScrollView {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
        }
        let view = LocationPhotoScrollView(image: image.cgImage!)
        view.animatesZoom = false
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 700)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return view
    }
}

/// Exercises the real paging viewport; a correct indicator alone does not prove page alignment.
@MainActor
final class LocationPhotoPagingTests: XCTestCase {
    func testSelectedPhotoPagingAndResizeKeepWholePagesAligned() async throws {
        let assets = LocationEditorPreview.photoAssets
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: LocationPhotoViewer(
            assets: assets, selectedID: assets[1].assetID, mediaService: nil))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        await assertAlignedPage(1, in: host.view, count: assets.count)
        let control = try XCTUnwrap(findPageControl(in: host.view))
        XCTAssertEqual(control.numberOfPages, assets.count)
        XCTAssertEqual(control.currentPage, 1)
        for index in [2, 1, 0, 1, 2] {
            control.currentPage = index
            control.sendActions(for: .valueChanged)
            await assertAlignedPage(index, in: host.view, count: assets.count)
        }
        window.frame.size = CGSize(width: 700, height: 400)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        await assertAlignedPage(2, in: host.view, count: assets.count, expectedWidth: 700)
        XCTAssertEqual(control.currentPage, 2)
        let controlFrame = control.convert(control.bounds, to: host.view)
        XCTAssertGreaterThanOrEqual(controlFrame.height, 44)
        XCTAssertLessThanOrEqual(controlFrame.maxY, host.view.safeAreaLayoutGuide.layoutFrame.maxY)
    }

    private func assertAlignedPage(_ index: Int, in view: UIView, count: Int, expectedWidth: CGFloat? = nil) async {
        let aligned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                guard let scroll = self.findPager(in: view), scroll.bounds.width > 0 else { return false }
                let width = scroll.bounds.width
                if let expectedWidth {
                    guard abs(view.bounds.width - expectedWidth) < 1,
                          abs(width - expectedWidth) < 1 else { return false }
                }
                return abs(scroll.contentSize.width - width * CGFloat(count)) < 1
                    && abs(scroll.contentOffset.x + scroll.adjustedContentInset.left - width * CGFloat(index)) < 1
            }
        }, object: nil)
        await fulfillment(of: [aligned], timeout: 5)
    }

    private func findPager(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, !(scroll is LocationPhotoScrollView),
           scroll.contentSize.width > scroll.bounds.width { return scroll }
        return view.subviews.lazy.compactMap { self.findPager(in: $0) }.first
    }

    private func findPageControl(in view: UIView) -> UIPageControl? {
        if let control = view as? UIPageControl { return control }
        return view.subviews.lazy.compactMap { self.findPageControl(in: $0) }.first
    }
}
