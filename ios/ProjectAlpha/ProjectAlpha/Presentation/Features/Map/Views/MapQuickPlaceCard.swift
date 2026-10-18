//
//  MapQuickPlaceCard.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 11/10/26.
//

import SwiftUI

struct MapQuickPlaceCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.locale) private var locale
    let place: MapQuickPlace
    let width: CGFloat
    let height: CGFloat
    let onClose: () -> Void
    let onOpenInMaps: () -> Void
    let onViewDetails: () -> Void
    let onReferenceHeightChange: (CGFloat) -> Void
    var route: MapRouteModel? = nil
    var distanceUnit: DistanceUnit = .kilometre

    var body: some View {
        let contentPadding = MapQuickCardMetrics.contentPadding

        return ViewThatFits(in: .vertical) {
            cardContent(.all, includesMaps: true)
            cardContent(.all, includesMaps: false)
            cardContent(.route, includesMaps: true)
            cardContent(.route, includesMaps: false)
            cardContent(.address, includesMaps: true)
            cardContent(.address, includesMaps: false)
            cardContent(.title, includesMaps: true)
            cardContent(.title, includesMaps: false)
            cardContent(.none, includesMaps: true)
            cardContent(.none, includesMaps: false)
        }
        .frame(width: max(0, width - 2 * MapQuickCardMetrics.contentPadding),
               height: max(0, height - 2 * MapQuickCardMetrics.contentPadding))
        .padding(MapQuickCardMetrics.contentPadding)
        .background {
            referenceTemplate
                .frame(width: max(0, width - 2 * MapQuickCardMetrics.contentPadding))
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.dynamicTypeSize, .large)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height + 2 * contentPadding
                } action: { _, measuredHeight in
                    onReferenceHeightChange(measuredHeight)
                }
                .id(MapQuickCardMeasurementIdentity(width: width, localeIdentifier: locale.identifier))
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if !place.isCurrentPosition {
                closeButton.padding(MapQuickCardMetrics.contentPadding)
            }
        }
        .background(
            reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: MapQuickCardMetrics.cornerRadius)
        )
        .glassEffect(
            reduceTransparency ? .identity : .regular,
            in: .rect(cornerRadius: MapQuickCardMetrics.cornerRadius)
        )
        .accessibilityIdentifier(MapQuickCardAccessibility.card)
    }

    private func cardContent(_ level: MapQuickCardContentLevel, includesMaps: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch level {
                case .all: placeFacts(reference: false)
                case .route:
                    VStack(alignment: .leading, spacing: MapQuickCardMetrics.compactSectionSpacing) {
                        placeSummary
                        routeFacts(reference: false)
                    }
                case .address: placeSummary
                case .title:
                    placeTitle.frame(minHeight: place.isCurrentPosition ? 0 : MapQuickCardMetrics.minimumTarget, alignment: .topLeading)
                case .none: Color.clear.frame(height: closeTextReservation > 0 ? MapQuickCardMetrics.minimumTarget : 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: level == .none ? 0 : MapQuickCardMetrics.factsToActionsSpacing)
            Group {
                if includesMaps { actionButtons } else { detailsButton }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // A complete default-text template determines the outer height. Reserving
    // both two-line fields and the close area makes it independent of place data.
    private var referenceTemplate: some View {
        VStack(alignment: .leading, spacing: MapQuickCardMetrics.factsToActionsSpacing) {
            placeFacts(reference: true)
            actionButtons
        }
    }

    // Visible facts and the default-size template share the same rows and
    // spacing, so the shared height reserves only the inline layout's space.
    private func placeFacts(reference: Bool) -> some View {
        VStack(alignment: .leading, spacing: MapQuickCardMetrics.compactSectionSpacing) {
            placeSummary(reference: reference)

            VStack(alignment: .leading, spacing: MapQuickCardMetrics.factSpacing) {
                routeFacts(reference: reference)
                coordinateFact(reference: reference)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func routeFacts(reference: Bool) -> some View {
        if reference || !place.isCurrentPosition {
            MapRouteSummaryView(
                state: reference ? MapRoutePreviewFixtures.unavailable : (route?.state ?? .noOrigin),
                distanceUnit: distanceUnit
            )
        }
    }

    private func inlineFact<Value: View>(_ key: MapKeys, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MapQuickCardMetrics.factSpacing) {
            HStack(spacing: 0) {
                Text(key)
                Text(verbatim: MapQuickCardMetrics.factLabelSeparator)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            value()
        }
        .font(MapPlaceTypography.fact)
        .accessibilityElement(children: .combine)
    }

    private var coordinateFact: some View { coordinateFact(reference: false) }

    private func coordinateFact(reference: Bool) -> some View {
        inlineFact(.coordinates) {
            HStack(spacing: MapQuickCardMetrics.factSpacing) {
                Text(reference ? MapQuickCardMetrics.referenceLatitude : place.coordinate.latitude, format: .number.precision(.fractionLength(MapQuickCardMetrics.coordinateDigits)))
                Text(reference ? MapQuickCardMetrics.referenceLongitude : place.coordinate.longitude, format: .number.precision(.fractionLength(MapQuickCardMetrics.coordinateDigits)))
            }
        }
    }

    private var placeSummary: some View { placeSummary(reference: false) }

    private func placeSummary(reference: Bool) -> some View {
        VStack(alignment: .leading, spacing: MapQuickCardMetrics.spacing) {
            placeTitle(reference: reference)

            Group {
                if reference {
                    Text(MapKeys.address)
                } else if let address = place.address, !address.isEmpty {
                    Text(address)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(2, reservesSpace: reference)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, reference ? MapQuickCardMetrics.minimumTarget + MapQuickCardMetrics.spacing : closeTextReservation)
        }
        .frame(maxWidth: .infinity, minHeight: !reference && place.isCurrentPosition ? 0 : MapQuickCardMetrics.minimumTarget, alignment: .topLeading)
    }

    private var placeTitle: some View { placeTitle(reference: false) }

    private func placeTitle(reference: Bool) -> some View {
        Group {
            if reference {
                Text(MapKeys.name)
            } else if let name = place.name {
                Text(name)
            } else {
                Text(MapKeys.myLocation)
            }
        }
        .font(.headline)
        .lineLimit(2, reservesSpace: reference)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.trailing, reference ? MapQuickCardMetrics.minimumTarget + MapQuickCardMetrics.spacing : closeTextReservation)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeTextReservation: CGFloat {
        place.isCurrentPosition ? 0 : MapQuickCardMetrics.minimumTarget + MapQuickCardMetrics.spacing
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: MapQuickCardSymbols.close)
                .font(.system(size: MapQuickCardMetrics.closeSymbolSize, weight: .semibold))
                .frame(
                    width: MapQuickCardMetrics.closeVisualSize,
                    height: MapQuickCardMetrics.closeVisualSize
                )
                .background(
                    reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                    in: Circle()
                )
                .glassEffect(
                    reduceTransparency ? .identity : .regular.interactive(),
                    in: .circle
                )
                .frame(
                    width: MapQuickCardMetrics.minimumTarget,
                    height: MapQuickCardMetrics.minimumTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(CommonKeys.close))
        .accessibilityIdentifier(MapQuickCardAccessibility.close)
    }

    private var actionButtons: some View {
        GlassEffectContainer(spacing: MapQuickCardMetrics.actionSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MapQuickCardMetrics.actionSpacing) {
                    detailsButton
                    mapsButton
                }
                .fixedSize(horizontal: true, vertical: false)

                detailsButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailsButton: some View {
        Button(action: onViewDetails) {
            Text(MapKeys.viewDetails)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MapQuickCardMetrics.actionHorizontalPadding)
                .frame(
                    minWidth: MapQuickCardMetrics.minimumTarget,
                    minHeight: MapQuickCardMetrics.actionVisualHeight
                )
                .background(
                    reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                    in: Capsule()
                )
                .glassEffect(
                    reduceTransparency ? .identity : .regular.interactive(),
                    in: .capsule
                )
                .padding(.vertical, MapQuickCardMetrics.actionTargetOutset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -MapQuickCardMetrics.actionTargetOutset)
        .accessibilityIdentifier(MapQuickCardAccessibility.details)
    }

    private var mapsButton: some View {
        Button(action: onOpenInMaps) {
            Text(CommonKeys.openInMaps)
                .font(.footnote)
                .padding(.horizontal, MapQuickCardMetrics.actionHorizontalPadding)
                .frame(
                    minWidth: MapQuickCardMetrics.minimumTarget,
                    minHeight: MapQuickCardMetrics.actionVisualHeight
                )
                .background(
                    reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                    in: Capsule()
                )
                .glassEffect(
                    reduceTransparency ? .identity : .regular.interactive(),
                    in: .capsule
                )
                .padding(.vertical, MapQuickCardMetrics.actionTargetOutset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -MapQuickCardMetrics.actionTargetOutset)
        .accessibilityIdentifier(MapQuickCardAccessibility.openInMaps)
    }
}

private struct MapQuickCardMeasurementIdentity: Hashable {
    let width: CGFloat
    let localeIdentifier: String
}

private enum MapQuickCardContentLevel {
    case all, route, address, title, none
}

private enum MapQuickCardMetrics {
    static let factLabelSeparator = ":"
    static let referenceLatitude: Double = -90
    static let referenceLongitude: Double = -180
    static let spacing: CGFloat = 8
    static let compactSectionSpacing: CGFloat = 4
    static let actionSpacing: CGFloat = 8
    static let factSpacing: CGFloat = 4
    static let actionHorizontalPadding: CGFloat = 8
    static let actionVisualHeight: CGFloat = 32
    // Hit areas extend into the existing clear space above/below the capsules;
    // only their visible height contributes to the card's content fitting.
    static let actionTargetOutset: CGFloat = (minimumTarget - actionVisualHeight) / 2
    static let contentPadding: CGFloat = 12
    static let factsToActionsSpacing: CGFloat = 16
    static let coordinateDigits = 6
    static let cornerRadius: CGFloat = 20
    static let minimumTarget: CGFloat = 44
    static let closeVisualSize: CGFloat = 28
    static let closeSymbolSize: CGFloat = 12
    static let previewHeight: CGFloat = 320
    static let previewWidth: CGFloat = 360
    static let constrainedPreviewHeight: CGFloat = 300
    static let reducedLandscapePreviewHeight: CGFloat = 180
    static let reducedLandscapePreviewWidth: CGFloat = 380
    static let minimalPreviewHeight: CGFloat = 108
    static let currentLandscapePreviewHeight: CGFloat = 206
}

private enum MapQuickCardSymbols {
    static let close = "xmark"
}

private enum MapQuickCardAccessibility {
    static let card = "map.quickPlaceCard"
    static let close = "map.quickPlaceClose"
    static let details = "map.quickPlaceDetails"
    static let openInMaps = "map.quickPlaceOpenInMaps"
}

@MainActor
private enum MapQuickCardPreviewFixtures {
    static let longName = "A much longer place name that occupies two lines on the map card"
    static let longAddress = "A long street address with additional locality information that occupies two lines"
    static let currentLandscapeAddress = "Alley 457 Cach Mang Thang 8, Hoa Hung, Ho Chi Minh City, Vietnam"
    static let currentLandscapeTimestamp = Date(timeIntervalSince1970: 1_791_851_460)

    static let currentLandscapePlace = MapQuickPlace(
        id: .currentPosition,
        name: nil,
        address: currentLandscapeAddress,
        coordinate: try! Coordinate(latitude: 10.780696, longitude: 106.674196),
        horizontalAccuracyMetres: 10,
        timestamp: currentLandscapeTimestamp
    )

    static let longSearchPlace = MapQuickPlace(
        id: MapQuickPlacePreviewFixtures.searchPlace.id,
        name: longName,
        address: longAddress,
        coordinate: MapQuickPlacePreviewFixtures.searchPlace.coordinate,
        horizontalAccuracyMetres: nil,
        timestamp: nil
    )

    static let fullTemplatePlace = MapQuickPlace(
        id: .currentPosition,
        name: longName,
        address: longAddress,
        coordinate: currentLandscapePlace.coordinate,
        horizontalAccuracyMetres: currentLandscapePlace.horizontalAccuracyMetres,
        timestamp: currentLandscapePlace.timestamp
    )
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.fullTemplatePlace,
        width: MapQuickCardMetrics.previewWidth,
        height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in }
    )
    .frame(width: MapQuickCardMetrics.previewWidth)
    .padding()
    .environment(\.dynamicTypeSize, .large)
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickPlacePreviewFixtures.searchPlace,
        width: MapQuickCardMetrics.previewWidth,
        height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in }
    )
    .frame(width: MapQuickCardMetrics.previewWidth)
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.longSearchPlace,
        width: MapQuickCardMetrics.previewWidth,
        height: MapQuickCardMetrics.constrainedPreviewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in }
    )
    .frame(width: MapQuickCardMetrics.previewWidth)
    .padding()
    .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickPlacePreviewFixtures.currentPlace,
        width: MapQuickCardMetrics.previewWidth,
        height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in }
    )
    .frame(width: MapQuickCardMetrics.previewWidth)
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.longSearchPlace,
        width: MapQuickCardMetrics.previewWidth,
        height: MapQuickCardMetrics.minimalPreviewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in }
    )
    .frame(width: MapQuickCardMetrics.previewWidth)
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickPlacePreviewFixtures.currentPlace,
        width: MapQuickCardMetrics.reducedLandscapePreviewWidth,
        height: MapQuickCardMetrics.reducedLandscapePreviewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in }
    )
    .frame(width: MapQuickCardMetrics.reducedLandscapePreviewWidth)
    .padding()
    .environment(\.dynamicTypeSize, .large)
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.currentLandscapePlace,
        width: MapQuickCardMetrics.previewWidth,
        height: MapQuickCardMetrics.currentLandscapePreviewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in }
    )
    .frame(width: MapQuickCardMetrics.previewWidth)
    .padding()
    .environment(\.dynamicTypeSize, .large)
}
