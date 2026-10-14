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

    private var isMapActive: Bool {
        rendersLiveMap && coordinator.selectedTab == .map && scenePhase == .active
    }

    private var isSearchActive: Bool {
        isMapActive && coordinator.mapPresentation == .search
    }

    private var searchTaskID: MapSearchTaskID {
        MapSearchTaskID(active: isSearchActive, presentationGeneration: viewModel.placeSearchGeneration)
    }

    private var mapSheet: Binding<MapPresentation?> {
        Binding(
            get: { coordinator.selectedTab == .map ? coordinator.presentedMapSheet : nil },
            set: { presentation in
                guard presentation == nil, coordinator.selectedTab == .map else { return }
                switch coordinator.mapPresentation {
                case .search: closeSearch()
                case .detail: closeDetails()
                case .none: break
                }
            }
        )
    }

    var body: some View {
        @Bindable var model = viewModel
        let searchTaskID = self.searchTaskID

        mapSurface
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openSearch) {
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
                    if let place = viewModel.selectedDetail {
                        MapReadOnlyDetailSheet(place: place) {
                            openInAppleMaps(place)
                        }
                    }
                case .none:
                    EmptyView()
                }
            }
            .task(id: searchTaskID) {
                guard !searchTaskID.active
                        || (coordinator.mapPresentation == .search && coordinator.selectedTab == .map) else { return }
                await viewModel.updatePlaceSearchActivity(
                    isActive: searchTaskID.active,
                    expectedGeneration: searchTaskID.presentationGeneration,
                    localeIdentifier: locale.identifier
                )
            }
            .onChange(of: isSearchActive) { _, active in
                if !active { viewModel.placeSearch?.stop() }
            }
            .onChange(of: coordinator.mapPresentation, initial: true) { _, presentation in
                switch presentation {
                case .search: _ = viewModel.openPlaceSearch()
                case .none: viewModel.dismissPlaceSearch()
                case .detail: break
                }
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
            .onChange(of: viewModel.selectedDetail) { _, detail in
                if detail == nil, coordinator.mapPresentation == .detail {
                    closeDetails()
                }
            }
            .alert(Text(MapKeys.locationPermissionTitle), isPresented: $model.permissionAlertPresented) {
                Button(action: openSettings) {
                    Text(CommonKeys.settings)
                }
                Button(role: .cancel, action: {}) {
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
            let measurementKey = MapCardReferenceMeasurementKey(
                cardWidth: initialLayout.cardWidth,
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
                        MapQuickPlaceCard(
                            place: place,
                            width: layout.cardWidth,
                            height: layout.cardHeight,
                            onClose: { viewModel.dismissSearchCandidate() },
                            onOpenInMaps: { openInAppleMaps(place) },
                            onViewDetails: openDetails,
                            onReferenceHeightChange: { height in
                                recordReferenceCardHeight(height, for: measurementKey)
                            }
                        )
                        .frame(width: layout.cardWidth)
                        .padding(.horizontal, MapCardLayout.edgePadding)
                        .padding(.bottom, layout.cardBottomInset)
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
        coordinator.openMapSearch()
        if coordinator.mapPresentation == .search {
            viewModel.openPlaceSearch()
        }
    }

    private func closeSearch() {
        viewModel.dismissPlaceSearch()
        coordinator.closeMapSearch()
    }

    private func openDetails() {
        viewModel.showDetails()
        guard viewModel.selectedDetail != nil else { return }
        coordinator.openMapDetail()
    }

    private func closeDetails() {
        coordinator.closeMapDetail()
    }

    private func mapSheetDidDismiss() {
        coordinator.mapPresentationDidDismiss()
        // A queued sheet now owns its content; a tab/background pause can also
        // remove rendering while the scene still owns the current presentation.
        if coordinator.mapPresentation == .none {
            viewModel.dismissPlaceSearch()
            viewModel.selectedDetail = nil
        }
    }

    private func openInAppleMaps(_ place: MapQuickPlace) {
        let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = place.name ?? LocalizationManager.localizedString(MapKeys.myLocation, locale: locale)
        item.openInMaps(launchOptions: nil)
    }

    @ViewBuilder
    private func mapCanvas(compassAtTrailing: Bool, showsCompass: Bool) -> some View {
        @Bindable var model = viewModel
        if rendersLiveMap {
            Map(position: $model.cameraPosition, scope: mapScope) {
                if isMapActive && viewModel.showsUserLocation {
                    UserAnnotation()
                }
                if let candidate = viewModel.selectedCandidate {
                    Annotation(MapAnnotationTitle.hidden, coordinate: CLLocationCoordinate2D(
                        latitude: candidate.coordinate.latitude,
                        longitude: candidate.coordinate.longitude
                    )) {
                        MapSearchCandidatePin(candidate: candidate)
                    }
                    .tag(candidate.id)
                }
            }
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

private enum MapAnnotationTitle {
    static let hidden = ""
}

private enum MapAccessibility {
    static let searchButton = "map.search"
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
