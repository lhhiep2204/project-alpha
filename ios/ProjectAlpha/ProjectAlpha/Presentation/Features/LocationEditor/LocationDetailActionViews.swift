//
//  LocationDetailActionViews.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 26/10/26.
//

import SwiftUI
import UIKit

enum LocationDetailActionLayout { case detail, card }

struct LocationDetailActionsView: View {
    let payload: LocationDetailPayload
    let isSaved: Bool
    let isFavorite: Bool
    let canUpdate: Bool
    let canMutate: Bool
    let onUpdate: () -> Void
    let onOpenInMaps: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onCopied: (LocationKeys) -> Void
    var layout: LocationDetailActionLayout = .detail
    var rendersOpaqueSurface = false

    var body: some View {
        if layout == .card {
            GlassEffectContainer(spacing: Metrics.spacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Metrics.spacing) { actionButtons(inMenu: false) }
                    HStack(spacing: Metrics.spacing) {
                        updateButton(inMenu: false)
                        mapsButton(inMenu: false)
                        overflowMenu(includeMaps: false)
                    }
                    HStack(spacing: Metrics.spacing) {
                        updateButton(inMenu: false)
                        overflowMenu(includeMaps: true)
                    }
                    overflowMenu(includeMaps: true, includeUpdate: true)
                }
                .buttonStyle(.plain)
            }
        } else {
            LocationDetailActionContainer { actionButtons(inMenu: false) }
        }
    }

    @ViewBuilder
    private func actionButtons(inMenu: Bool) -> some View {
        if layout == .card { updateButton(inMenu: inMenu) }
        mapsButton(inMenu: inMenu)
        secondaryActions(inMenu: inMenu)
    }

    private func updateButton(inMenu: Bool) -> some View {
        DSButton(action: onUpdate) {
            actionLabel(Text(isSaved ? CommonKeys.edit : .add), icon: isSaved ? .edit : .add, inMenu: inMenu)
        }
        .disabled(!canUpdate)
        .accessibilityIdentifier(layout == .card ? LocationDetailActionAccessibility.cardUpdate
            : isSaved ? LocationDetailActionAccessibility.edit : LocationDetailActionAccessibility.add)
    }

    private func mapsButton(inMenu: Bool) -> some View {
        DSButton(action: onOpenInMaps) {
            actionLabel(Text(CommonKeys.openInMaps), icon: .map, inMenu: inMenu)
        }
        .accessibilityIdentifier(layout == .card ? LocationDetailActionAccessibility.cardMaps : LocationDetailActionAccessibility.maps)
    }

    @ViewBuilder
    private func secondaryActions(inMenu: Bool) -> some View {
        Menu {
            DSButton(CommonKeys.copyLocationInfo) { copy(payload.locationInfo, feedback: .locationInfoCopied) }
            if let address = payload.address, !address.isEmpty {
                DSButton(CommonKeys.copyAddress) { copy(address, feedback: .addressCopied) }
            }
            DSButton(CommonKeys.copyCoordinates) { copy(payload.coordinateText, feedback: .coordinatesCopied) }
            if let notes = payload.notes, !notes.isEmpty {
                DSButton(CommonKeys.copyNotes) { copy(notes, feedback: .notesCopied) }
            }
        } label: { actionLabel(Text(CommonKeys.copy), icon: .copy, inMenu: inMenu) }
        .accessibilityIdentifier(layout == .card ? LocationDetailActionAccessibility.cardCopy : LocationDetailActionAccessibility.copy)
        ShareLink(
            item: payload.shareText(includeNotes: false),
            preview: SharePreview(payload.name)
        ) {
            actionLabel(Text(CommonKeys.share), icon: .share, inMenu: inMenu)
        }
        .accessibilityIdentifier(layout == .card ? LocationDetailActionAccessibility.cardShare : LocationDetailActionAccessibility.share)
        if isSaved {
            if layout == .detail {
                DSButton(action: onFavorite) {
                    actionLabel(Text(isFavorite ? LocationKeys.removeFavorite : .addFavorite),
                        icon: isFavorite ? .favorite : .favoriteEmpty, inMenu: inMenu)
                }
                .disabled(!canMutate)
                .accessibilityIdentifier(LocationDetailActionAccessibility.favorite)
            }
            DSButton(role: .destructive, action: onDelete) {
                actionLabel(Text(CommonKeys.delete), icon: .delete, inMenu: inMenu)
            }
            .disabled(!canMutate)
            .accessibilityIdentifier(layout == .card ? LocationDetailActionAccessibility.cardDelete : LocationDetailActionAccessibility.delete)
        }
    }

    private func overflowMenu(includeMaps: Bool, includeUpdate: Bool = false) -> some View {
        Menu {
            if includeUpdate { updateButton(inMenu: true) }
            if includeMaps { mapsButton(inMenu: true) }
            secondaryActions(inMenu: true)
        } label: { actionLabel(Text(CommonKeys.moreActions), icon: .more, inMenu: false) }
        .accessibilityIdentifier(LocationDetailActionAccessibility.cardMore)
    }

    @ViewBuilder
    private func actionLabel(_ title: Text, icon: DSSystemIcon, inMenu: Bool) -> some View {
        if inMenu {
            Label { title } icon: { Image.appSystemIcon(icon) }
        } else {
            LocationDetailActionLabel(title: title, icon: icon, rendersOpaqueSurface: rendersOpaqueSurface)
        }
    }

    private enum Metrics { static let spacing: CGFloat = 8 }

    private func copy(_ value: String, feedback: LocationKeys) {
        UIPasteboard.general.string = value
        onCopied(feedback)
    }
}

/// Use the actual controls to fill a row; wrap only when their full targets cannot fit.
private struct LocationDetailActionContainer<Actions: View>: View {
    let actions: Actions

    init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
    }

    var body: some View {
        GlassEffectContainer(spacing: Metrics.spacing) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.spacing) { actions }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.minimumColumn), spacing: Metrics.spacing)],
                          spacing: Metrics.spacing) { actions }
            }
            .buttonStyle(.plain)
        }
    }

    private enum Metrics {
        static var spacing: CGFloat { 8 }
        static var minimumColumn: CGFloat { 44 }
    }
}

private struct LocationDetailActionLabel: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: Text
    let icon: DSSystemIcon
    var rendersOpaqueSurface = false

    var body: some View {
        Label { title } icon: { Image.appSystemIcon(icon) }
            .labelStyle(.iconOnly)
            .font(.body)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .background((reduceTransparency || rendersOpaqueSurface) ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            .glassEffect((reduceTransparency || rendersOpaqueSurface) ? .identity : .regular.interactive(),
                         in: .rect(cornerRadius: Metrics.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius))
    }

    private enum Metrics { static let cornerRadius: CGFloat = 16 }
}

enum LocationDetailActionAccessibility {
    static let cardUpdate = "map.quickPlaceSave"
    static let cardMaps = "map.quickPlaceOpenInMaps"
    static let cardCopy = "map.quickPlaceCopy"
    static let cardShare = "map.quickPlaceShare"
    static let cardFavorite = "map.quickPlaceFavorite"
    static let cardDelete = "map.quickPlaceDelete"
    static let cardMore = "map.quickPlaceActions"
    static let add = "location.detail.add"
    static let edit = "location.detail.edit"
    static let maps = "location.detail.maps"
    static let copy = "location.detail.copy"
    static let share = "location.detail.share"
    static let favorite = "location.detail.favorite"
    static let delete = "location.detail.delete"
}

private enum LocationDetailActionPreview {
    static let payload = LocationDetailPayload(name: LocationEditorPreview.savedLocation.name,
        address: LocationEditorPreview.savedLocation.address, coordinate: LocationEditorPreview.savedLocation.coordinate,
        notes: LocationEditorPreview.savedLocation.notes)
}

#Preview {
    LocationDetailActionsView(payload: LocationDetailActionPreview.payload, isSaved: true, isFavorite: true,
        canUpdate: true, canMutate: true, onUpdate: {}, onOpenInMaps: {}, onFavorite: {}, onDelete: {}, onCopied: { _ in })
        .padding()
}

#Preview {
    LocationDetailActionsView(payload: LocationDetailActionPreview.payload, isSaved: false, isFavorite: false,
        canUpdate: true, canMutate: false, onUpdate: {}, onOpenInMaps: {}, onFavorite: {}, onDelete: {}, onCopied: { _ in })
        .padding().frame(width: 240)
}

#Preview { LocationDetailActionLabel(title: Text(CommonKeys.copy), icon: .copy).padding() }

/// Keep confirmation/error ownership outside recyclable Form rows.
struct LocationDetailMutationFeedback: ViewModifier {
    @Environment(\.locale) private var locale
    let actions: LocationDetailActionModel?
    let locationID: UUID?
    let onFavorite: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(Text(CommonKeys.delete), isPresented: Binding(
                get: { ownsFeedback && actions?.deleteNeedsConfirmation == true },
                set: { actions?.deleteNeedsConfirmation = $0 })) {
                DSButton(role: .destructive) {
                    if ownsFeedback { onDelete() }
                } label: { Text(CommonKeys.delete) }
                DSButton(role: .cancel) { actions?.cancelDelete() } label: { Text(CommonKeys.cancel) }
            } message: {
                if let target = actions?.deleteTarget {
                    Text(String(format: LocalizationManager.localizedString(LocationKeys.deleteMessage, locale: locale),
                                locale: locale, target.displayName ?? target.name))
                }
            }
            .alert(Text(CommonKeys.error), isPresented: Binding(
                get: { ownsFeedback && actions?.actionError != nil },
                set: { if !$0 { actions?.actionError = nil } })) {
                if actions?.failedAction == .delete, let target = actions?.deleteTarget, !isMissing {
                    DSButton(CommonKeys.retry) {
                        if ownsFeedback { actions?.requestDelete(target) }
                    }
                } else if actions?.failedAction == .favorite, !isMissing {
                    DSButton(CommonKeys.retry) {
                        if ownsFeedback { onFavorite() }
                    }
                }
                DSButton(role: .cancel) { actions?.cancelDelete() } label: { Text(CommonKeys.cancel) }
            } message: { Text(errorKey) }
    }

    private var ownsFeedback: Bool {
        actions?.hasFeedback(for: locationID) == true
    }
    private var isMissing: Bool {
        if case .locationMissing = actions?.actionError { return true }
        return false
    }
    private var errorKey: LocationKeys {
        if isMissing { return .locationMissing }
        if case .editConflict = actions?.actionError { return .deleteConflict }
        return actions?.failedAction == .favorite ? .favoriteFailed : .deleteFailed
    }
}

#Preview {
    LocationDetailActionContainer {
        DSButton {} label: { LocationDetailActionLabel(title: Text(CommonKeys.add), icon: .add) }
        DSButton {} label: { LocationDetailActionLabel(title: Text(CommonKeys.openInMaps), icon: .map) }
        DSButton {} label: { LocationDetailActionLabel(title: Text(CommonKeys.copy), icon: .copy) }
        DSButton {} label: { LocationDetailActionLabel(title: Text(CommonKeys.share), icon: .share) }
    }
    .padding()
}
