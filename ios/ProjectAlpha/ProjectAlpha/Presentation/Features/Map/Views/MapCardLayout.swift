//
//  MapCardLayout.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 11/10/26.
//

import CoreGraphics

struct MapCardLayout: Equatable {
    static let edgePadding: CGFloat = 12
    static let upperControlHeight: CGFloat = 44
    static let legalGap: CGFloat = 8
    // MapKit has no public attribution-frame API. This initial estimate must
    // be calibrated by UI evidence; it is not a system-provided dimension.
    static let estimatedAttributionTopInset: CGFloat = 22

    let size: CGSize
    let regularWidth: Bool
    let leadingIsPhysicalLeft: Bool
    let referenceCardHeight: CGFloat

    init(
        size: CGSize,
        regularWidth: Bool,
        leadingIsPhysicalLeft: Bool,
        referenceCardHeight: CGFloat? = nil
    ) {
        self.size = size
        self.regularWidth = regularWidth
        self.leadingIsPhysicalLeft = leadingIsPhysicalLeft
        self.referenceCardHeight = max(0, referenceCardHeight ?? MapCardLayoutMetrics.initialReferenceHeight)
    }

    func withReferenceCardHeight(_ height: CGFloat?) -> Self {
        Self(size: size, regularWidth: regularWidth,
             leadingIsPhysicalLeft: leadingIsPhysicalLeft, referenceCardHeight: height)
    }

    var cardAtLeading: Bool {
        regularWidth || size.width > size.height * MapCardLayoutMetrics.wideAspectRatio
    }

    var cardWidth: CGFloat {
        let available = max(0, size.width - 2 * Self.edgePadding)
        return cardAtLeading
            ? min(available, size.width * MapCardLayoutMetrics.wideWidthFraction, MapCardLayoutMetrics.maximumWideWidth)
            : available
    }

    var cardBottomInset: CGFloat {
        Self.estimatedAttributionTopInset + Self.legalGap
    }

    var omitsCompassForCard: Bool {
        !cardAtLeading && size.height < Self.upperControlHeight
            + 3 * Self.edgePadding + cardBottomInset + referenceCardHeight
    }

    var cardHeight: CGFloat {
        min(referenceCardHeight, max(0, size.height - topReserved - cardBottomInset))
    }

    private var topReserved: CGFloat {
        cardAtLeading || omitsCompassForCard
            ? Self.edgePadding
            : Self.upperControlHeight + 2 * Self.edgePadding
    }
}

private enum MapCardLayoutMetrics {
    static let wideAspectRatio = 1.1
    static let wideWidthFraction = 0.48
    static let maximumWideWidth: CGFloat = 380
    static let initialReferenceHeight: CGFloat = 304
}
