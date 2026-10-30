//
//  MapQuickPlaceCard.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 11/10/26.
//

import SwiftUI

/// Explicit opaque rendering also supports deterministic offscreen previews/tests.
/// Shipping callers retain system accessibility behavior through the default case.
enum MapCardSurfaceStyle { case system, opaque }

/// Actions use the map session's existing detail payload and mutation owner.
struct MapQuickCardActionConfiguration {
    let payload: LocationDetailPayload
    let isFavorite: Bool
    let canMutate: Bool
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onCopied: (LocationKeys) -> Void
}

struct MapQuickPlaceCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.locale) private var locale
    @State private var detailFeedback = false
    let place: MapQuickPlace
    let width: CGFloat
    let height: CGFloat
    let onClose: () -> Void
    let onOpenInMaps: () -> Void
    let onViewDetails: () -> Void
    let onReferenceHeightChange: (CGFloat) -> Void
    var route: MapRouteModel? = nil
    var distanceUnit: DistanceUnit = .kilometre
    var showsClose: Bool? = nil
    private var displaysClose: Bool { showsClose ?? !place.isCurrentPosition }
    var isSaved = false
    var isSaving = false
    var canSave = false
    var onSave: () -> Void = {}
    var surfaceStyle: MapCardSurfaceStyle = .system
    var detailActions: MapQuickCardActionConfiguration? = nil
    private var usesOpaqueSurface: Bool { surfaceStyle == .opaque || reduceTransparency }

    var body: some View {
        let contentPadding = MapQuickCardMetrics.contentPadding

        return ZStack {
            Button(action: showDetails) {
                ViewThatFits(in: .vertical) {
                    cardContent(.all)
                    cardContent(.route)
                    cardContent(.address)
                    cardContent(.title)
                    cardContent(.none)
                }
                .frame(width: max(0, width - 2 * MapQuickCardMetrics.contentPadding),
                       height: max(0, height - 2 * MapQuickCardMetrics.contentPadding))
                .padding(MapQuickCardMetrics.contentPadding)
                .frame(width: max(0, width), height: max(0, height))
                .background(
                    usesOpaqueSurface ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: MapQuickCardMetrics.cornerRadius)
                )
                .glassEffect(
                    usesOpaqueSurface ? .identity : .regular,
                    in: .rect(cornerRadius: MapQuickCardMetrics.cornerRadius)
                )
                .contentShape(RoundedRectangle(cornerRadius: MapQuickCardMetrics.cornerRadius))
            }
            .buttonStyle(MapQuickCardTapStyle())
            .accessibilityRepresentation {
                VStack(alignment: .leading) {
                    Button(action: showDetails) { Text(MapKeys.viewDetails) }
                        .buttonStyle(.automatic)
                        .accessibilityIdentifier(MapQuickCardAccessibility.details)
                    placeFacts(reference: false)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: detailFeedback)
        }
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
            if displaysClose {
                closeButton.padding(MapQuickCardMetrics.contentPadding)
            }
        }
        .overlay(alignment: .bottomLeading) {
            actionButtons.padding(MapQuickCardMetrics.contentPadding)
        }
        .accessibilityElement(children: .contain)
    }

    private func showDetails() {
        detailFeedback.toggle()
        onViewDetails()
    }

    private func cardContent(_ level: MapQuickCardContentLevel) -> some View {
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
                    placeTitle.frame(minHeight: displaysClose ? MapQuickCardMetrics.minimumTarget : 0, alignment: .topLeading)
                case .none: Color.clear.frame(height: closeTextReservation > 0 ? MapQuickCardMetrics.minimumTarget : 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
            Spacer(minLength: level == .none ? 0 : MapQuickCardMetrics.factsToActionsSpacing)
            // Foreground controls are siblings of the detail Button, never nested
            // in its label. Reserve their existing fixed target height here.
            Color.clear.frame(height: MapQuickCardMetrics.minimumTarget)
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
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .lineLimit(2, reservesSpace: reference)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, reference ? MapQuickCardMetrics.minimumTarget + MapQuickCardMetrics.spacing : closeTextReservation)
        }
        .frame(maxWidth: .infinity, minHeight: !reference && !displaysClose ? 0 : MapQuickCardMetrics.minimumTarget, alignment: .topLeading)
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
        displaysClose ? MapQuickCardMetrics.minimumTarget + MapQuickCardMetrics.spacing : 0
    }

    private var closeButton: some View {
        DSButton(action: onClose) {
            Image(systemName: MapQuickCardSymbols.close)
                .font(.caption.weight(.semibold))
                .frame(
                    width: MapQuickCardMetrics.closeVisualSize,
                    height: MapQuickCardMetrics.closeVisualSize
                )
                .background(
                    usesOpaqueSurface ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                    in: Circle()
                )
                .glassEffect(
                    usesOpaqueSurface ? .identity : .regular.interactive(),
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

    @ViewBuilder
    private var actionButtons: some View {
        if let detailActions {
            LocationDetailActionsView(
                payload: detailActions.payload,
                isSaved: isSaved,
                isFavorite: detailActions.isFavorite,
                canUpdate: !isSaving && canSave,
                canMutate: detailActions.canMutate,
                onUpdate: onSave,
                onOpenInMaps: onOpenInMaps,
                onFavorite: detailActions.onFavorite,
                onDelete: detailActions.onDelete,
                onCopied: detailActions.onCopied,
                layout: .card,
                rendersOpaqueSurface: usesOpaqueSurface
            )
        } else {
            legacyActionButtons
        }
    }

    private var legacyActionButtons: some View {
        GlassEffectContainer(spacing: MapQuickCardMetrics.actionSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MapQuickCardMetrics.actionSpacing) {
                    saveButton
                    mapsButton
                }
                saveButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var saveButton: some View {
        MapQuickCardAction(key: isSaving ? .saving : nil,
                           symbol: isSaved ? MapQuickCardSymbols.edit : MapQuickCardSymbols.save,
                           identifier: MapQuickCardAccessibility.save, commonKey: isSaved ? .edit : .add,
                           surfaceStyle: usesOpaqueSurface ? .opaque : .system, action: onSave)
            .disabled(isSaving || !canSave)
    }

    private var mapsButton: some View {
        MapQuickCardAction(key: .maps, symbol: MapQuickCardSymbols.maps,
                           identifier: MapQuickCardAccessibility.openInMaps,
                           surfaceStyle: usesOpaqueSurface ? .opaque : .system, action: onOpenInMaps)
            .accessibilityLabel(Text(CommonKeys.openInMaps))
    }
}

/// A standard Button may still activate after a finger slides within its bounds.
/// Use tap recognition for activation, and native Button tracking for pressed
/// appearance so the enclosing carousel can take over a horizontal drag.
private struct MapQuickCardTapStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MapQuickCardTapTarget(action: configuration.trigger) { configuration.label }
    }
}

private struct MapQuickCardTapTarget<Content: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        // Native button tracking alone accepts an in-bounds slide on release.
        // Its action is intentionally empty; only a recognized tap activates.
        Button(action: {}) { content }
            .buttonStyle(MapQuickCardPressedStyle())
            .simultaneousGesture(TapGesture().onEnded { activate() })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate() }
            .focusable(isEnabled)
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                guard isEnabled else { return .ignored }
                activate()
                return .handled
            }
    }

    private func activate() {
        guard isEnabled else { return }
        action()
    }
}

private struct MapQuickCardPressedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? MapQuickCardMetrics.pressedOpacity : 1)
    }
}

private struct MapQuickCardAction: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let key: LocationKeys?
    let symbol: String
    let identifier: String
    var commonKey: CommonKeys = .add
    var surfaceStyle: MapCardSurfaceStyle = .system
    let action: () -> Void
    private var usesOpaqueSurface: Bool { surfaceStyle == .opaque || reduceTransparency }

    var body: some View {
        DSButton(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .frame(height: MapQuickCardMetrics.actionSymbolHeight)
                .padding(.horizontal, MapQuickCardMetrics.actionHorizontalPadding)
                .padding(.vertical, MapQuickCardMetrics.actionVerticalPadding)
                .frame(minWidth: MapQuickCardMetrics.minimumTarget, maxWidth: .infinity, minHeight: MapQuickCardMetrics.minimumTarget)
                .background(usesOpaqueSurface ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: MapQuickCardMetrics.actionCornerRadius))
                .glassEffect(usesOpaqueSurface ? .identity : .regular.interactive(),
                             in: .rect(cornerRadius: MapQuickCardMetrics.actionCornerRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityIdentifier(identifier)
    }

    private var accessibilityTitle: Text {
        if let key { Text(key) } else { Text(commonKey) }
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
    static let actionSymbolHeight: CGFloat = 20
    static let actionSpacing: CGFloat = 8
    static let factSpacing: CGFloat = 4
    static let actionHorizontalPadding: CGFloat = 8
    static let actionVerticalPadding: CGFloat = 6
    static let contentPadding: CGFloat = 12
    static let factsToActionsSpacing: CGFloat = 16
    static let coordinateDigits = 6
    static let cornerRadius: CGFloat = 20
    static let actionCornerRadius: CGFloat = 16
    static let pressedOpacity = 0.65
    static let minimumTarget: CGFloat = 44
    static let closeVisualSize: CGFloat = 28
    static let previewHeight: CGFloat = 320
    static let previewWidth: CGFloat = 360
    static let overflowPreviewWidth: CGFloat = 100
    static let constrainedPreviewHeight: CGFloat = 300
    static let reducedLandscapePreviewHeight: CGFloat = 180
    static let reducedLandscapePreviewWidth: CGFloat = 380
    static let minimalPreviewHeight: CGFloat = 108
    static let currentLandscapePreviewHeight: CGFloat = 206
}

private enum MapQuickCardSymbols {
    static let close = "xmark"
    static let save = "plus"
    static let edit = DSSystemIcon.edit.rawValue
    static let maps = "map"
}

private enum MapQuickCardAccessibility {
    static let close = "map.quickPlaceClose"
    static let details = "map.quickPlaceDetails"
    static let save = "map.quickPlaceSave"
    static let openInMaps = "map.quickPlaceOpenInMaps"
}

@MainActor
private enum MapQuickCardPreviewFixtures {
    static let longName = "A much longer place name that occupies two lines on the map card"
    static let longAddress = "A long street address with additional locality information that occupies two lines"
    static let currentLandscapeAddress = "Alley 457 Cach Mang Thang 8, Hoa Hung, Ho Chi Minh City, Vietnam"
    static let destination = "My Places"
    static let savedRecordID = "F94A663A-6769-4B7D-A81A-8B03283B3769"
    static let savedNotes = "A saved note available in Copy."
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

    static let savedPlace = MapQuickPlace(
        id: .savedLocation(UUID(uuidString: savedRecordID)!),
        name: longName,
        address: longAddress,
        coordinate: MapQuickPlacePreviewFixtures.searchPlace.coordinate,
        horizontalAccuracyMetres: nil,
        timestamp: nil
    )

    static let savedActions = MapQuickCardActionConfiguration(
        payload: LocationDetailPayload(name: longName, address: longAddress,
            coordinate: savedPlace.coordinate, notes: savedNotes),
        isFavorite: true, canMutate: true,
        onFavorite: {}, onDelete: {}, onCopied: { _ in }
    )

    static let unsavedActions = MapQuickCardActionConfiguration(
        payload: LocationDetailPayload(name: longName, address: longAddress,
            coordinate: longSearchPlace.coordinate, notes: nil),
        isFavorite: false, canMutate: false,
        onFavorite: {}, onDelete: {}, onCopied: { _ in }
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
    MapQuickCardTapTarget(action: {}) {
        Text(MapKeys.viewDetails).padding()
    }
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

#Preview {
    MapQuickCardAction(key: nil, symbol: MapQuickCardSymbols.save,
                       identifier: MapQuickCardAccessibility.save, action: {})
        .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickPlacePreviewFixtures.searchPlace,
        width: MapQuickCardMetrics.previewWidth, height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in },
        canSave: true
    )
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickPlacePreviewFixtures.searchPlace,
        width: MapQuickCardMetrics.previewWidth, height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in },
        showsClose: false,
        isSaved: true
    )
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickPlacePreviewFixtures.currentPlace,
        width: MapQuickCardMetrics.previewWidth, height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in },
        showsClose: true, canSave: true
    )
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.savedPlace,
        width: MapQuickCardMetrics.previewWidth, height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in },
        isSaved: true, canSave: true, surfaceStyle: .system,
        detailActions: MapQuickCardPreviewFixtures.savedActions
    )
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.longSearchPlace,
        width: MapQuickCardMetrics.previewWidth, height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in },
        isSaved: false, canSave: true, surfaceStyle: .system,
        detailActions: MapQuickCardPreviewFixtures.unsavedActions
    )
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.savedPlace,
        width: MapQuickCardMetrics.overflowPreviewWidth, height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in },
        isSaved: true, canSave: true, surfaceStyle: .system,
        detailActions: MapQuickCardPreviewFixtures.savedActions
    )
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.savedPlace,
        width: MapQuickCardMetrics.previewWidth, height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in },
        isSaved: true, canSave: true, surfaceStyle: .opaque,
        detailActions: MapQuickCardPreviewFixtures.savedActions
    )
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.longSearchPlace,
        width: MapQuickCardMetrics.previewWidth, height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in },
        isSaved: false, canSave: true, surfaceStyle: .opaque,
        detailActions: MapQuickCardPreviewFixtures.unsavedActions
    )
    .padding()
}

#Preview {
    MapQuickPlaceCard(
        place: MapQuickCardPreviewFixtures.savedPlace,
        width: MapQuickCardMetrics.overflowPreviewWidth, height: MapQuickCardMetrics.previewHeight,
        onClose: {}, onOpenInMaps: {}, onViewDetails: {}, onReferenceHeightChange: { _ in },
        isSaved: true, canSave: true, surfaceStyle: .opaque,
        detailActions: MapQuickCardPreviewFixtures.savedActions
    )
    .padding()
}
