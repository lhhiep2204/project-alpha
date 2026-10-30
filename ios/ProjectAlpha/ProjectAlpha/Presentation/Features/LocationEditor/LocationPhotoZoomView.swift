//
//  LocationPhotoZoomView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/10/26.
//

import SwiftUI
import UIKit

/// UIKit owns the continuous pinch/pan interaction and its native zoom animation.
/// The raster is decoded once by LocationPhotoImage, outside the UI actor.
struct LocationPhotoZoomView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let image: CGImage
    var isActive = true
    @State private var request: LocationPhotoZoomRequest?

    private enum Shortcut {
        static let zoomIn = "+"
        static let zoomOut = "-"
    }

    var body: some View {
        LocationPhotoZoomCanvas(image: image, isActive: isActive, animated: !reduceMotion, request: request)
            .contextMenu {
                DSButton(LocationKeys.zoomIn) { zoom(.inward) }
                DSButton(LocationKeys.zoomOut) { zoom(.outward) }
            }
            .background {
                DSButton(LocationKeys.zoomIn) { zoom(.inward) }
                    .keyboardShortcut(KeyEquivalent(Character(Shortcut.zoomIn)), modifiers: [])
                    .disabled(!isActive).hidden()
                DSButton(LocationKeys.zoomOut) { zoom(.outward) }
                    .keyboardShortcut(KeyEquivalent(Character(Shortcut.zoomOut)), modifiers: [])
                    .disabled(!isActive).hidden()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LocationKeys.photos))
            .accessibilityAction(named: Text(LocationKeys.zoomIn)) { zoom(.inward) }
            .accessibilityAction(named: Text(LocationKeys.zoomOut)) { zoom(.outward) }
            .accessibilityScrollAction { edge in
                switch edge {
                case .top: zoom(.up)
                case .bottom: zoom(.down)
                case .leading: zoom(.left)
                case .trailing: zoom(.right)
                }
            }
            .background {
                DSButton(CommonKeys.back) { zoom(.left) }
                    .keyboardShortcut(.leftArrow, modifiers: .shift).disabled(!isActive).hidden()
                DSButton(CommonKeys.next) { zoom(.right) }
                    .keyboardShortcut(.rightArrow, modifiers: .shift).disabled(!isActive).hidden()
                DSButton(CommonKeys.back) { zoom(.up) }
                    .keyboardShortcut(.upArrow, modifiers: .shift).disabled(!isActive).hidden()
                DSButton(CommonKeys.next) { zoom(.down) }
                    .keyboardShortcut(.downArrow, modifiers: .shift).disabled(!isActive).hidden()
            }
    }

    private func zoom(_ direction: LocationPhotoZoomRequest.Direction) {
        request = LocationPhotoZoomRequest(direction: direction)
    }
}

struct LocationPhotoZoomRequest: Equatable {
    enum Direction { case inward, outward, up, down, left, right }
    let id = UUID()
    let direction: Direction
}

private struct LocationPhotoZoomCanvas: UIViewRepresentable {
    let image: CGImage
    let isActive: Bool
    let animated: Bool
    let request: LocationPhotoZoomRequest?

    func makeUIView(context: Context) -> LocationPhotoScrollView {
        LocationPhotoScrollView(image: image)
    }

    func updateUIView(_ view: LocationPhotoScrollView, context: Context) {
        view.animatesZoom = animated
        view.setActive(isActive)
        view.apply(request)
    }
}

/// Image coordinates stay independent of safe-area chrome and the current zoom.
final class LocationPhotoScrollView: UIScrollView, UIScrollViewDelegate {
    private enum Metric {
        static let maximumRelativeScale: CGFloat = 4
        static let doubleTapRelativeScale: CGFloat = 2
        static let zoomStep: CGFloat = 1.5
        static let scaleTolerance: CGFloat = 0.001
    }

    let photoView: UIImageView
    var animatesZoom = true
    private var previousSize = CGSize.zero
    private var appliedRequestID: UUID?
    private var active = true

    init(image: CGImage) {
        photoView = UIImageView(image: UIImage(cgImage: image))
        super.init(frame: .zero)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        scrollsToTop = false
        backgroundColor = .clear
        photoView.frame = CGRect(origin: .zero, size: photoView.image!.size)
        addSubview(photoView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if previousSize != bounds.size {
            // Preserve the image point at the viewport center and relative zoom on resize.
            let oldCenter = CGPoint(x: bounds.minX + previousSize.width / 2,
                                    y: bounds.minY + previousSize.height / 2)
            let focus = photoView.convert(oldCenter, from: self)
            let relativeScale = previousSize == .zero ? 1 : zoomScale / minimumZoomScale
            previousSize = bounds.size
            let fit = min(bounds.width / photoView.bounds.width, bounds.height / photoView.bounds.height)
            minimumZoomScale = fit
            maximumZoomScale = fit * Metric.maximumRelativeScale
            setZoomScale(min(maximumZoomScale, max(fit, fit * relativeScale)), animated: false)
            centerPhoto()
            if relativeScale > 1 { center(on: focus) }
        }
        centerPhoto()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photoView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if !value { setZoomScale(minimumZoomScale, animated: false) }
    }

    func apply(_ request: LocationPhotoZoomRequest?) {
        guard let request, request.id != appliedRequestID else { return }
        appliedRequestID = request.id
        guard active else { return }
        switch request.direction {
        case .inward: zoom(toScale: zoomScale * Metric.zoomStep, at: visiblePhotoCenter)
        case .outward: zoom(toScale: zoomScale / Metric.zoomStep, at: visiblePhotoCenter)
        case .up: pan(dx: 0, dy: -bounds.height / 2)
        case .down: pan(dx: 0, dy: bounds.height / 2)
        case .left: pan(dx: -bounds.width / 2, dy: 0)
        case .right: pan(dx: bounds.width / 2, dy: 0)
        }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard active else { return }
        toggleZoom(at: gesture.location(in: photoView))
    }

    func toggleZoom(at point: CGPoint) {
        let target = zoomScale > minimumZoomScale + Metric.scaleTolerance
            ? minimumZoomScale : minimumZoomScale * Metric.doubleTapRelativeScale
        zoom(toScale: target, at: point)
    }

    func zoom(toScale scale: CGFloat, at point: CGPoint) {
        let target = min(maximumZoomScale, max(minimumZoomScale, scale))
        if target <= minimumZoomScale + Metric.scaleTolerance {
            setZoomScale(minimumZoomScale, animated: animatesZoom)
        } else {
            let rect = CGRect(x: point.x - bounds.width / target / 2,
                              y: point.y - bounds.height / target / 2,
                              width: bounds.width / target, height: bounds.height / target)
            zoom(to: rect, animated: animatesZoom)
        }
    }

    private var visiblePhotoCenter: CGPoint {
        photoView.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: self)
    }

    private func centerPhoto() {
        let horizontal = max(0, (bounds.width - photoView.frame.width) / 2)
        let vertical = max(0, (bounds.height - photoView.frame.height) / 2)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != inset { contentInset = inset }
        // A fitted image yields horizontal swipes to the enclosing page view.
        panGestureRecognizer.isEnabled = zoomScale > minimumZoomScale + Metric.scaleTolerance
    }

    private func pan(dx: CGFloat, dy: CGFloat) {
        let point = CGPoint(x: contentOffset.x + dx, y: contentOffset.y + dy)
        setContentOffset(clampedOffset(point), animated: animatesZoom)
    }

    private func center(on point: CGPoint) {
        let x = point.x * zoomScale - bounds.width / 2
        let y = point.y * zoomScale - bounds.height / 2
        contentOffset = clampedOffset(CGPoint(x: x, y: y))
    }

    private func clampedOffset(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(-contentInset.left, point.x), max(-contentInset.left, contentSize.width - bounds.width + contentInset.right)),
            y: min(max(-contentInset.top, point.y), max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)))
    }
}

#Preview {
    LocationPhotoImage(asset: LocationEditorPreview.photoAssets[0],
                       mediaService: LocationEditorPreview.photoService(), thumbnail: false, zoomable: true)
        .background(.black)
}
