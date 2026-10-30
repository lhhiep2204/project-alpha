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

    var carouselViewportWidth: CGFloat {
        guard cardAtLeading else { return max(0, size.width) }
        let fullWidth = cardWidth + 2 * Self.edgePadding
        return min(fullWidth, max(0, size.width) * MapCarouselMetrics.maximumViewportFraction)
    }

    /// All collection items share one width, including the temporary first
    /// item. Reserve room inside the viewport for the next item in every size.
    func carouselCardWidth(itemCount: Int) -> CGFloat {
        let available = max(0, carouselViewportWidth - 2 * Self.edgePadding)
        guard itemCount > 1 else { return available }
        return min(available, max(MapCarouselMetrics.minimumItemWidth,
                                  available * MapCarouselMetrics.minimumItemFraction,
                                  available - MapCarouselMetrics.peekWidth))
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

enum MapCarouselMetrics {
    static let selectedCardOpacity = 1.0
    static let unselectedCardOpacity = 0.6
    static let spacing: CGFloat = 12
    static let peekWidth: CGFloat = 28
    static let maximumViewportFraction: CGFloat = 0.5
    static let minimumItemFraction: CGFloat = 0.5
    // Two 44-point action targets, their 8-point gap and 12-point card padding.
    static let minimumItemWidth: CGFloat = 120
}

private enum MapCardLayoutMetrics {
    static let wideAspectRatio = 1.1
    static let wideWidthFraction = 0.48
    static let maximumWideWidth: CGFloat = 380
    static let initialReferenceHeight: CGFloat = 304
}
