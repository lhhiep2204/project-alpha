//
//  MapView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct MapView: View {
    @Environment(SceneCoordinator.self) private var coordinator
    @Environment(AppPreferences.self) private var preferences
    @Environment(DSToastManager.self) private var toastManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var localPresentation = MapPresentationState()
    @State private var carouselSelection = MapCardCarouselSelection<MapQuickPlaceID>()
    @State private var pendingSavedID: UUID?
    @State private var showDiscardForSaved = false
    @State private var savedIDAfterDismissal: UUID?
    @State private var handledGlobalFocusRequestID: UUID?
    @State private var cardActionTarget: SavedLocation?
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MapViewModel
    @State private var referenceCardMeasurement: MapCardReferenceMeasurement?
    @State private var pendingReferenceCardMeasurement: MapCardReferenceMeasurement?
    @State private var currentCardMeasurementKey: MapCardReferenceMeasurementKey?
    @Namespace private var mapScope
    private let rendersLiveMap: Bool

    init(viewModel: MapViewModel, rendersLiveMap: Bool = true) {
        _viewModel = State(initialValue: viewModel)
        self.rendersLiveMap = rendersLiveMap
    }

    private var ownsVisibleTab: Bool {
        coordinator.selectedTab == (viewModel.isCollectionMap ? .home : .map)
    }

    private var presentation: MapPresentationState {
        viewModel.isCollectionMap ? localPresentation : coordinator.globalMapPresentation
    }

    private var isMapActive: Bool {
        rendersLiveMap && ownsVisibleTab && scenePhase == .active
    }

    private var isSearchActive: Bool {
        isMapActive && presentation.mapPresentation == .search
    }

    private var searchTaskID: MapSearchTaskID {
        MapSearchTaskID(active: isSearchActive, presentationGeneration: viewModel.placeSearchGeneration)
    }

    private var mapSheet: Binding<MapPresentation?> {
        Binding(
            get: { ownsVisibleTab ? presentation.presentedMapSheet : nil },
            set: { newPresentation in
                guard newPresentation == nil, ownsVisibleTab else { return }
                switch presentation.mapPresentation {
                case .search: closeSearch()
                case .detail: closeDetails()
                case .capture: presentation.closeMapCapture()
                case .collectionPicker: presentation.closeMapCollectionPicker()
                case .none: break
                }
            }
        )
    }

    var body: some View { locationLifecycle }

    private var mapInteractions: some View {
        let searchTaskID = self.searchTaskID
        return mapSurface
            .safeAreaInset(edge: .top, spacing: 0) {
                if viewModel.libraryLoadFailed {
                    MapLibraryRecoveryBanner(onRetry: viewModel.retryLibraryLoading)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DSButton(action: viewModel.fitAll) {
                        Label { Text(LocationKeys.fitAll) } icon: { Image(systemName: MapSymbols.fitAll) }
                    }
                    .disabled(viewModel.savedLocations.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    DSButton(action: openSearch) {
                        Label { Text(CommonKeys.search) } icon: { Image.appSystemIcon(.search) }
                    }
                    .accessibilityIdentifier(MapAccessibility.searchButton)
                    .keyboardShortcut(KeyEquivalent(MapKeyboardShortcuts.search), modifiers: .command)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    MapCurrentLocationButton(isLocating: viewModel.isLocating) {
                        viewModel.requestRecenter()
                    }
                }
            }
            .sheet(item: mapSheet, onDismiss: mapSheetDidDismiss) { presentation in
                switch presentation {
                case .search:
                    if let search = viewModel.placeSearch {
                        MapPlaceSearchView(model: search, onClose: closeSearch)
                    }
                case .detail:
                    if let place = viewModel.presentedDetail {
                        LocationDetailsEditor(
                            model: viewModel.capture, mode: viewModel.isUpdatingDetail ? .update : .read,
                            readContext: LocationDetailsReadContext(
                                place: place, savedLocation: viewModel.displayedSavedLocation,
                                collection: viewModel.collections.first {
                                    $0.id == viewModel.displayedSavedLocation?.collectionID
                                }?.collection,
                                mediaService: viewModel.mediaService, route: viewModel.route,
                                distanceUnit: preferences.distanceUnit,
                                onOpenInMaps: { openInAppleMaps(place) },
                                actions: viewModel.detailActions,
                                onFavorite: { await viewModel.toggleDetailFavorite($0) },
                                onDelete: {
                                    guard await viewModel.deleteDetailLocation() else { return false }
                                    toastManager.show(LocationKeys.deleteSucceeded)
                                    return true
                                }
                            ),
                            onBeginUpdate: {
                                if viewModel.displayedSavedLocation != nil {
                                    guard viewModel.prepareSavedLocationEdit() else { return nil }
                                } else { prepareCapture() }
                                return viewModel.capture
                            },
                            onOpenSaved: receiptOpenAction
                        )
                    }
                case .capture:
                    if let capture = viewModel.capture {
                        LocationDetailsEditor(model: capture, onOpenSaved: openSavedLocation)
                    }
                case .collectionPicker:
                    if let capture = viewModel.capture {
                        LocationCollectionPicker(model: capture)
                    }
                case .none:
                    EmptyView()
                }
            }
            .task(id: searchTaskID) {
                guard !searchTaskID.active
                        || (presentation.mapPresentation == .search && ownsVisibleTab) else { return }
                await viewModel.updatePlaceSearchActivity(
                    isActive: searchTaskID.active,
                    expectedGeneration: searchTaskID.presentationGeneration,
                    localeIdentifier: locale.identifier
                )
            }
            .onChange(of: isSearchActive) { _, active in
                if !active { viewModel.placeSearch?.stop() }
            }
            .onChange(of: presentation.mapPresentation, initial: true) { _, presentation in
                switch presentation {
                case .search: _ = viewModel.openPlaceSearch()
                case .none: viewModel.dismissPlaceSearch()
                case .detail, .capture, .collectionPicker: break
                }
            }
    }

    // Editors own their draft observation. Only the legacy standalone picker needs a map-owned task.
    private var collectionPickerObservationRequestID: UUID? {
        guard ownsVisibleTab, presentation.mapPresentation == .collectionPicker else { return nil }
        return viewModel.capture?.collectionObservationRequestID
    }

    private var selectionRequests: some View {
        mapInteractions
            .task(id: MapLibraryTaskID(active: isMapActive, requestID: viewModel.libraryObservationRequestID)) {
                guard isMapActive else { return }
                await viewModel.observeSavedLocations()
            }
            .task(id: collectionPickerObservationRequestID) {
                guard collectionPickerObservationRequestID != nil else { return }
                await viewModel.capture?.observeCollections()
            }
            .task(id: coordinator.globalLocationFocusRequestID) {
                guard !viewModel.isCollectionMap,
                      let requestID = coordinator.globalLocationFocusRequestID,
                      handledGlobalFocusRequestID != requestID,
                      let id = coordinator.globalLocationID else { return }
                handledGlobalFocusRequestID = requestID
                await viewModel.resolveSavedLocationRequest(id: id)
            }
            .task(id: MapReceiptTaskID(revision: viewModel.libraryRevision,
                                      receiptID: viewModel.retainedReceiptID,
                                      retryID: viewModel.libraryObservationRequestID)) {
                await viewModel.refreshCommittedReceipt(expectedLibraryRevision: viewModel.libraryRevision)
            }
    }

    private var selectionLifecycle: some View {
        selectionRequests
            .onChange(of: viewModel.visiblePlace, initial: true) { _, _ in prepareCapture() }
            .onChange(of: viewModel.libraryRevision) { _, _ in prepareCapture() }
            .onChange(of: viewModel.capture?.destinationCollectionID) { _, _ in viewModel.refreshCaptureMatch() }
            .onChange(of: viewModel.capture?.commit) { _, _ in
                if let capture = viewModel.capture {
                    if capture.commit != nil, presentation.mapPresentation == .capture { presentation.closeMapCapture() }
                    viewModel.acceptCaptureCommit(capture)
                }
            }
            .onChange(of: viewModel.unavailableSavedLocationEvent) { _, _ in
                toastManager.show(MapKeys.placeResolutionFailed)
            }
            .onChange(of: viewModel.scopeUnavailable) { _, missing in
                if missing { dismiss() }
            }
            .onChange(of: locale.identifier, initial: true) { _, identifier in
                viewModel.placeSearch?.updateLocale(identifier)
                viewModel.updateAddressLocale(identifier)
            }
            .onChange(of: viewModel.placeSearch?.resolvedCandidate) { _, candidate in
                guard isSearchActive, let candidate else { return }
                withAnimation(reduceMotion ? nil : .smooth) {
                    viewModel.selectSearchCandidate(candidate)
                }
                closeSearch()
            }
    }

    private var locationLifecycle: some View {
        @Bindable var model = viewModel
        return selectionLifecycle
            .modifier(LocationDetailMutationFeedback(
                actions: ownsVisibleTab && presentation.mapPresentation == .none ? viewModel.detailActions : nil,
                locationID: cardActionTarget?.id,
                onFavorite: retryCardFavorite, onDelete: deleteCardLocation))
            .confirmationDialog(Text(LocationKeys.discardTitle), isPresented: $showDiscardForSaved) {
                DSButton(role: .destructive) {
                    guard let id = pendingSavedID else { return }
                    pendingSavedID = nil
                    Task {
                        await viewModel.capture?.cancel()
                        queueSavedLocation(id)
                    }
                } label: { Text(LocationKeys.discard) }
                DSButton(role: .cancel) { pendingSavedID = nil } label: { Text(LocationKeys.keepEditing) }
            } message: { Text(LocationKeys.discardMessage) }
            .task(id: MapLocationTaskID(active: isMapActive, recenterID: viewModel.recenterRequestID)) {
                guard !Task.isCancelled else { return }
                guard isMapActive else {
                    viewModel.deactivate()
                    return
                }
                let outcome = if viewModel.hasPendingRecenterRequest {
                    await viewModel.performPendingRecenter()
                } else {
                    await viewModel.activate()
                }
                guard !Task.isCancelled, isMapActive else { return }
                present(outcome)
            }
            .onChange(of: isMapActive) { _, active in
                if !active { viewModel.deactivate() }
            }
            .onDisappear { viewModel.deactivate() }
            .onChange(of: viewModel.locationFocus) { _, focus in
                guard let focus else { return }
                withAnimation(reduceMotion ? nil : .smooth) {
                    viewModel.focusCamera(on: focus)
                }
            }
            .onChange(of: viewModel.presentedDetail) { _, detail in
                if detail == nil { viewModel.resumeNativeMapSelection() }
                if detail == nil, presentation.mapPresentation == .detail {
                    closeDetails()
                }
            }
            .onChange(of: viewModel.mapFeatureResolutionFailureID) { _, _ in
                guard isMapActive else { return }
                showToast(.placeResolutionFailed)
            }
            .alert(Text(MapKeys.locationPermissionTitle), isPresented: $model.permissionAlertPresented) {
                DSButton(action: openSettings) {
                    Text(CommonKeys.settings)
                }
                DSButton(role: .cancel, action: {}) {
                    Text(CommonKeys.cancel)
                }
            } message: {
                Text(MapKeys.locationPermissionMessage)
            }
    }

    private var mapSurface: some View {
        GeometryReader { geometry in
            let initialLayout = MapCardLayout(
                size: geometry.size,
                regularWidth: horizontalSizeClass == .regular,
                leadingIsPhysicalLeft: layoutDirection == .leftToRight
            )
            let cardCount = viewModel.isCollectionMap
                ? viewModel.savedLocations.count + (viewModel.collectionTemporaryPlace == nil ? 0 : 1)
                : 1
            let cardWidth = viewModel.isCollectionMap
                ? initialLayout.carouselCardWidth(itemCount: cardCount) : initialLayout.cardWidth
            let measurementKey = MapCardReferenceMeasurementKey(
                cardWidth: cardWidth,
                localeIdentifier: locale.identifier
            )
            let layout = initialLayout.withReferenceCardHeight(
                referenceCardMeasurement?.key == measurementKey
                    ? referenceCardMeasurement?.height
                    : nil
            )

            mapCanvas(
                compassAtTrailing: layout.cardAtLeading,
                showsCompass: viewModel.visiblePlace == nil || !layout.omitsCompassForCard
            )
                .overlay(alignment: layout.cardAtLeading ? .bottomLeading : .bottom) {
                    if let place = viewModel.visiblePlace {
                        if viewModel.isCollectionMap {
                            collectionCards(layout: layout, cardWidth: cardWidth, measurementKey: measurementKey)
                                .padding(.bottom, layout.cardBottomInset)
                        } else {
                            quickCard(place: place, layout: layout, measurementKey: measurementKey)
                        .frame(width: layout.cardWidth)
                        .padding(.horizontal, MapCardLayout.edgePadding)
                        .padding(.bottom, layout.cardBottomInset)
                        }
                    }
                }
                .onAppear {
                    activateCardMeasurementKey(measurementKey)
                    updateFocusViewport(layout)
                }
                .onChange(of: measurementKey) { _, newKey in
                    activateCardMeasurementKey(newKey)
                }
                .onChange(of: layout) { _, newLayout in updateFocusViewport(newLayout) }
        }
    }

    private func quickCard(place: MapQuickPlace, layout: MapCardLayout,
                           measurementKey: MapCardReferenceMeasurementKey,
                           savedID: UUID? = nil, cardWidth: CGFloat? = nil) -> some View {
        MapQuickPlaceCard(
            place: place, width: cardWidth ?? layout.cardWidth, height: layout.cardHeight,
            onClose: { viewModel.dismissSearchCandidate() },
            onOpenInMaps: { openInAppleMaps(place) }, onViewDetails: {
                if viewModel.isCollectionMap { viewModel.selectCollectionCard(place.id) }
                openDetails()
            },
            onReferenceHeightChange: { recordReferenceCardHeight($0, for: measurementKey) },
            route: place.id == viewModel.visiblePlace?.id ? viewModel.route : nil,
            distanceUnit: preferences.distanceUnit,
            showsClose: viewModel.showsClose(for: place),
            isSaved: savedID != nil || (place.id == viewModel.visiblePlace?.id && (viewModel.displayedSavedLocation != nil || viewModel.capture?.commit != nil)),
            isSaving: viewModel.capture?.isSaving ?? false,
            canSave: !viewModel.detailActions.isPerformingAction
                && (savedID != nil || viewModel.displayedSavedLocation != nil || viewModel.capture != nil),
            onSave: {
                if viewModel.isCollectionMap, place.id != viewModel.visiblePlace?.id {
                    viewModel.selectCollectionCard(place.id)
                }
                if viewModel.displayedSavedLocation != nil { editLocation() }
                else { saveLocation() }
            },
            detailActions: cardActionConfiguration(for: place)
        )
    }

    private func cardSavedLocation(for place: MapQuickPlace) -> SavedLocation? {
        if case let .savedLocation(id) = place.id {
            return viewModel.savedLocations.first { $0.id == id }
                ?? viewModel.displayedSavedLocation.flatMap { $0.id == id ? $0 : nil }
        }
        return place.id == viewModel.visiblePlace?.id ? viewModel.displayedSavedLocation : nil
    }

    private func cardActionConfiguration(for place: MapQuickPlace) -> MapQuickCardActionConfiguration {
        let saved = cardSavedLocation(for: place)
        let name = saved?.displayName.flatMap { $0.isEmpty ? nil : $0 }
            ?? saved?.name ?? place.name ?? LocalizationManager.localizedString(MapKeys.myLocation, locale: locale)
        return MapQuickCardActionConfiguration(
            payload: LocationDetailPayload(name: name, address: saved?.address ?? place.address,
                coordinate: place.coordinate, notes: saved?.notes),
            isFavorite: saved?.isFavorite == true,
            canMutate: viewModel.detailActions.canMutate,
            onFavorite: {
                guard let saved else { return }
                cardActionTarget = saved
                retryCardFavorite()
            },
            onDelete: {
                guard let saved else { return }
                cardActionTarget = saved
                viewModel.detailActions.requestDelete(saved)
            },
            onCopied: { toastManager.show($0) })
    }

    private func retryCardFavorite() {
        guard let target = cardActionTarget else { return }
        Task { await viewModel.toggleDetailFavorite(target) }
    }

    private func deleteCardLocation() {
        Task {
            guard await viewModel.deleteDetailLocation() else { return }
            toastManager.show(LocationKeys.deleteSucceeded)
            cardActionTarget = nil
        }
    }

    private func collectionCards(layout: MapCardLayout, cardWidth: CGFloat,
                                 measurementKey: MapCardReferenceMeasurementKey) -> some View {
        let places = viewModel.collectionCardPlaces
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: MapCarouselMetrics.spacing) {
                    ForEach(places) { place in
                        let savedID: UUID? = if case let .savedLocation(id) = place.id { id } else { nil }
                        quickCard(place: place, layout: layout,
                                  measurementKey: measurementKey, savedID: savedID, cardWidth: cardWidth)
                            .opacity(place.id == viewModel.visiblePlace?.id
                                     ? MapCarouselMetrics.selectedCardOpacity
                                     : MapCarouselMetrics.unselectedCardOpacity)
                            .id(place.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, MapCardLayout.edgePadding, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $carouselSelection.targetID, anchor: .leading)
            .onChange(of: viewModel.visiblePlace?.id, initial: true) { _, id in
                carouselSelection.synchronize(selectedID: id)
            }
            .onScrollPhaseChange { _, phase in
                if let id = carouselSelection.settledTarget(isScrolling: phase != .idle,
                                                           selectedID: viewModel.visiblePlace?.id) {
                    viewModel.selectCollectionCard(id)
                }
            }
            .onScrollGeometryChange(for: CGSize.self) { geometry in
                geometry.containerSize
            } action: { _, _ in
                // Rotation can preserve the old pixel offset even when the
                // selected ID has not changed. Re-anchor only after the actual
                // scroll viewport has resized, using the current selection.
                guard let id = viewModel.visiblePlace?.id else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    carouselSelection.synchronize(selectedID: id)
                    proxy.scrollTo(id, anchor: .leading)
                }
            }
        }
        // Keep drawing and interaction inside the same geometry throughout
        // dragging, deceleration and rotation, rather than clipping only at rest.
        .modifier(MapCarouselViewport(
            width: layout.carouselViewportWidth, height: layout.cardHeight
        ))
        .accessibilityScrollAction { direction in
            switch direction {
            case .leading: viewModel.pageSelection(by: -1)
            case .trailing: viewModel.pageSelection(by: 1)
            default: break
            }
        }
        .accessibilityAction(named: Text(LocationKeys.next)) { viewModel.pageSelection(by: 1) }
        .accessibilityAction(named: Text(LocationKeys.previous)) { viewModel.pageSelection(by: -1) }

    }

    private var receiptOpenAction: ((UUID) -> Void)? {
        guard viewModel.selectedSavedLocation == nil else { return nil }
        return openSavedLocation
    }

    private func prepareCapture() {
        viewModel.prepareCapture(fallbackName: LocalizationManager.localizedString(MapKeys.myLocation, locale: locale))
    }

    private func saveLocation() {
        prepareCapture()
        guard viewModel.capture != nil else { return }
        presentation.openMapCapture()
    }

    private func editLocation() {
        guard viewModel.prepareSavedLocationEdit() else { return }
        presentation.openMapCapture()
    }

    private func openSavedLocation(_ id: UUID) {
        if let capture = viewModel.capture, capture.isDirty, !capture.isCancelled {
            pendingSavedID = id
            showDiscardForSaved = true
        } else {
            queueSavedLocation(id)
        }
    }

    private func queueSavedLocation(_ id: UUID) {
        if presentation.mapPresentation != .none {
            savedIDAfterDismissal = id
            presentation.dismissMapPresentation()
        } else {
            activateSavedLocation(id)
        }
    }

    private func activateSavedLocation(_ id: UUID) {
        if viewModel.savedLocations.contains(where: { $0.id == id }) {
            viewModel.selectSavedLocation(id)
        } else {
            coordinator.openSavedLocationInGlobalMap(id: id)
        }
    }

    private func updateFocusViewport(_ layout: MapCardLayout) {
        viewModel.setFocusViewport(
            width: layout.size.width,
            height: layout.size.height,
            cardWidth: layout.cardWidth + 2 * MapCardLayout.edgePadding,
            cardHeight: layout.cardHeight + layout.cardBottomInset,
            cardAtLeading: layout.cardAtLeading,
            leadingIsPhysicalLeft: layout.leadingIsPhysicalLeft
        )
    }

    private func recordReferenceCardHeight(
        _ height: CGFloat,
        for key: MapCardReferenceMeasurementKey
    ) {
        guard height.isFinite, height > 0 else { return }
        let measurement = MapCardReferenceMeasurement(key: key, height: height)
        if currentCardMeasurementKey == nil || currentCardMeasurementKey == key {
            if referenceCardMeasurement != measurement {
                referenceCardMeasurement = measurement
            }
        } else if pendingReferenceCardMeasurement != measurement {
            pendingReferenceCardMeasurement = measurement
        }
    }

    private func activateCardMeasurementKey(_ key: MapCardReferenceMeasurementKey) {
        currentCardMeasurementKey = key
        if pendingReferenceCardMeasurement?.key == key {
            referenceCardMeasurement = pendingReferenceCardMeasurement
        }
        pendingReferenceCardMeasurement = nil
    }

    private func openSearch() {
        presentation.openMapSearch()
        if presentation.mapPresentation == .search {
            viewModel.openPlaceSearch()
        }
    }

    private func closeSearch() {
        viewModel.dismissPlaceSearch()
        presentation.closeMapSearch()
    }

    private func openDetails() {
        viewModel.showDetails()
        guard viewModel.selectedDetail != nil else { return }
        presentation.openMapDetail()
    }

    private func closeDetails() {
        presentation.closeMapDetail()
    }

    private func mapSheetDidDismiss() {
        presentation.mapPresentationDidDismiss()
        if let id = savedIDAfterDismissal, presentation.mapPresentation == .none {
            savedIDAfterDismissal = nil
            activateSavedLocation(id)
        }
        // A queued sheet now owns its content; a tab/background pause can also
        // remove rendering while the scene still owns the current presentation.
        if presentation.mapPresentation == .none {
            viewModel.capture?.endAllEditing()
            viewModel.dismissPlaceSearch()
            viewModel.selectedDetail = nil
        }
    }

    private func openInAppleMaps(_ place: MapQuickPlace) {
        let fallbackName = LocalizationManager.localizedString(MapKeys.myLocation, locale: locale)
        guard let url = MapAppleMapsURL.make(for: place, fallbackName: fallbackName) else { return }
        openURL(url)
    }

    @ViewBuilder
    private func mapCanvas(compassAtTrailing: Bool, showsCompass: Bool) -> some View {
        @Bindable var model = viewModel
        if rendersLiveMap {
            Map(
                position: $model.cameraPosition,
                selection: Binding(
                    get: { viewModel.mapSelection },
                    set: { viewModel.updateMapSelection($0) }
                ),
                scope: mapScope
            ) {
                if isMapActive && viewModel.showsUserLocation {
                    UserAnnotation()
                }
                ForEach(viewModel.annotationGroups) { group in
                    let title = group.records.first { $0.id == viewModel.selectedSavedLocation?.id }?.title
                        ?? group.records.first?.title ?? String()
                    Annotation(coordinate: CLLocationCoordinate2D(
                        latitude: group.coordinate.latitude, longitude: group.coordinate.longitude
                    ), anchor: MapSavedPin.annotationAnchor) {
                        MapSavedPin(group: group, selectedID: viewModel.selectedSavedLocation?.id,
                                    onSelect: viewModel.selectSavedLocation)
                    } label: {
                        Text(verbatim: title)
                    }
                    .annotationTitles(.visible)
                    .tag(MapSelection(group.id))
                }
                if let candidate = viewModel.candidateForCustomAnnotation {
                    Annotation(coordinate: CLLocationCoordinate2D(
                        latitude: candidate.coordinate.latitude,
                        longitude: candidate.coordinate.longitude
                    )) {
                        MapSearchCandidatePin(candidate: candidate)
                    } label: {
                        Text(verbatim: candidate.name)
                    }
                    .annotationTitles(.visible)
                    .tag(MapSelection(candidate.id))
                }
            }
            // Animate programmatic focus from every selection path, including
            // asynchronous resolution, without interpolating user pan/zoom.
            .animation(
                reduceMotion || model.cameraPosition.positionedByUser
                    ? nil : .smooth(duration: MapCameraAnimation.duration),
                value: model.cameraPosition
            )
            .mapFeatureSelectionAccessory(nil)
            .mapFeatureSelectionDisabled { _ in !isMapActive || presentation.mapPresentation != .none }
            .mapStyle(preferences.mapType.mapStyle)
            .overlay(alignment: compassAtTrailing ? .topTrailing : .topLeading) {
                if showsCompass {
                    MapCompass(scope: mapScope)
                        .padding(.top, MapCardLayout.edgePadding)
                        .padding(compassAtTrailing ? .trailing : .leading, MapCardLayout.edgePadding)
                }
            }
            .mapScope(mapScope)
            .onMapCameraChange(frequency: .continuous) {
                // Invalidate a pending location focus during pan/zoom, before the
                // gesture ends. Keep region/search propagation on the end callback.
                if viewModel.cameraPosition.positionedByUser {
                    viewModel.userDidChangeCamera()
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.recordVisibleRegion(context.region)
            }
        } else {
            MapPreviewCanvas()
                .ignoresSafeArea()
        }
    }

    private func present(_ outcome: MapLocationOutcome?) {
        switch outcome {
        case .permissionDenied:
            viewModel.permissionAlertPresented = true
        case let .toast(issue):
            showToast(issue.key)
        case nil:
            break
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            showToast(.locationSettingsUnavailable)
            return
        }
        openURL(url) { accepted in
            if !accepted { showToast(.locationSettingsUnavailable) }
        }
    }

    private func showToast(_ key: MapKeys) {
        toastManager.show(key)
    }
}

private struct MapLibraryTaskID: Equatable {
    let active: Bool
    let requestID: UUID
}

private struct MapReceiptTaskID: Equatable {
    let revision: Int64
    let receiptID: UUID?
    let retryID: UUID
}

private struct MapLocationTaskID: Equatable {
    let active: Bool
    let recenterID: Int
}

private struct MapSearchTaskID: Equatable {
    let active: Bool
    let presentationGeneration: UInt64
}

private struct MapCardReferenceMeasurementKey: Equatable {
    let cardWidth: CGFloat
    let localeIdentifier: String
}

private struct MapCardReferenceMeasurement: Equatable {
    let key: MapCardReferenceMeasurementKey
    let height: CGFloat
}

private extension MapLocationIssue {
    var key: MapKeys {
        switch self {
        case .servicesDisabled: .locationServicesDisabled
        case .restricted: .locationRestricted
        case .timedOut: .locationTimedOut
        case .unavailable: .locationUnavailable
        }
    }
}

private enum MapCameraAnimation {
    static let duration: TimeInterval = 0.6
}

private enum MapSymbols {
    static let fitAll = "arrow.up.left.and.arrow.down.right"
}

private enum MapAccessibility {
    static let searchButton = "map.search"
    static let libraryRecovery = "map.libraryRecovery"
    static let libraryRetry = "map.libraryRetry"
}

private struct MapLibraryRecoveryBanner: View {
    let onRetry: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DSSpacing.medium) {
                message
                retryButton
            }
            VStack(alignment: .leading, spacing: DSSpacing.small) {
                message
                retryButton
            }
        }
        .font(.callout)
        .padding(.horizontal, DSSpacing.large)
        .padding(.vertical, DSSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .accessibilityIdentifier(MapAccessibility.libraryRecovery)
    }

    private var message: some View {
        Text(LocationKeys.locationLoadFailed)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var retryButton: some View {
        DSButton(action: onRetry) {
            Text(CommonKeys.retry)
                .frame(minWidth: MapRecoveryLayout.minimumHitSize, minHeight: MapRecoveryLayout.minimumHitSize)
                .contentShape(.rect)
        }
        .buttonStyle(.bordered)
            .accessibilityIdentifier(MapAccessibility.libraryRetry)
    }
}

private enum MapRecoveryLayout {
    static let minimumHitSize: CGFloat = 44
}

#Preview {
    MapLibraryRecoveryBanner(onRetry: {})
        .dynamicTypeSize(.accessibility3)
}

private enum MapKeyboardShortcuts {
    static let search: Character = "f"
}

#Preview {
    NavigationStack {
        MapView(viewModel: MapPreviewFixtures.model(), rendersLiveMap: false)
    }
    .environment(MapPreviewFixtures.coordinator())
    .environment(AppPreferences(store: PreviewPreferenceStore()))
    .environment(DSToastManager())
}

/// The scroll target is transient until settling; passing intermediate cards
/// must not launch routes or steal the camera from a newer pin selection.
struct MapCardCarouselSelection<ID: Hashable> {
    var targetID: ID?

    mutating func synchronize(selectedID: ID?) {
        targetID = selectedID
    }

    func settledTarget(isScrolling: Bool, selectedID: ID?) -> ID? {
        guard !isScrolling, let targetID, targetID != selectedID else { return nil }
        return targetID
    }
}

/// Keep moving cards inside the viewport without fading either edge.
/// Selection emphasis belongs to each whole card, independent of position.
struct MapCarouselViewport: ViewModifier {
    let width: CGFloat
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: height)
            .contentShape(.rect)
            .clipped()
    }
}

#Preview {
    HStack(spacing: MapCarouselMetrics.spacing) {
        Color.blue
            .opacity(MapCarouselMetrics.selectedCardOpacity)
        Color.blue
            .opacity(MapCarouselMetrics.unselectedCardOpacity)
    }
    .frame(width: 600, height: 200)
    .modifier(MapCarouselViewport(width: 400, height: 200))
    .padding()
}
