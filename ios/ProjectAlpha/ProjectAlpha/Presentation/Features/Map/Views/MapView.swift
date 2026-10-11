//
//  MapView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

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
    @State private var viewModel: MapViewModel
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

    private var searchPresented: Binding<Bool> {
        Binding(
            get: { coordinator.mapPresentation == .search && coordinator.selectedTab == .map },
            set: { presented in
                if !presented, coordinator.selectedTab == .map {
                    closeSearch()
                }
            }
        )
    }

    var body: some View {
        @Bindable var model = viewModel
        let searchTaskID = self.searchTaskID

        mapCanvas
            .overlay(alignment: .bottomTrailing) {
                MapCurrentLocationButton(isLocating: viewModel.isLocating) {
                    viewModel.requestRecenter()
                }
                .padding(MapLayoutMetrics.controlPadding)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openSearch) {
                        Label { Text(CommonKeys.search) } icon: { Image.appSystemIcon(.search) }
                    }
                    .accessibilityIdentifier(MapAccessibility.searchButton)
                    .keyboardShortcut(KeyEquivalent(MapKeyboardShortcuts.search), modifiers: .command)
                }
            }
            .sheet(isPresented: searchPresented, onDismiss: searchDidDismiss) {
                if let search = viewModel.placeSearch {
                    MapPlaceSearchView(model: search, onClose: closeSearch)
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
                }
            }
            .onChange(of: locale.identifier) { _, identifier in
                viewModel.placeSearch?.updateLocale(identifier)
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

    private func openSearch() {
        viewModel.openPlaceSearch()
        coordinator.openMapSearch()
    }

    private func closeSearch() {
        viewModel.dismissPlaceSearch()
        coordinator.closeMapSearch()
    }

    private func searchDidDismiss() {
        // A tab/background pause can remove rendering while the scene still owns Search.
        if coordinator.mapPresentation == .none { viewModel.dismissPlaceSearch() }
    }

    @ViewBuilder
    private var mapCanvas: some View {
        @Bindable var model = viewModel
        if rendersLiveMap {
            GeometryReader { geometry in
                Map(position: $model.cameraPosition) {
                    if isMapActive && viewModel.showsUserLocation {
                        UserAnnotation()
                    }
                    if let candidate = viewModel.selectedCandidate {
                        Annotation(candidate.name, coordinate: CLLocationCoordinate2D(
                            latitude: candidate.coordinate.latitude,
                            longitude: candidate.coordinate.longitude
                        )) {
                            MapSearchCandidatePin(
                                candidate: candidate,
                                maximumWidth: geometry.size.width * MapLayoutMetrics.candidateWidthFraction
                            )
                        }
                        .tag(candidate.id)
                    }
                }
                .mapStyle(preferences.mapType.mapStyle)
                .mapControls { MapCompass() }
                .onMapCameraChange(frequency: .onEnd) { context in
                    viewModel.recordVisibleRegion(context.region)
                    if viewModel.cameraPosition.positionedByUser {
                        viewModel.userDidChangeCamera()
                    }
                }
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

private struct MapCurrentLocationButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let isLocating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(MapKeys.currentLocation)
            } icon: {
                Image(systemName: MapSymbols.currentLocation)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            }
            .labelStyle(.iconOnly)
            .opacity(isLocating ? 0 : 1)
            .overlay {
                if isLocating {
                    ProgressView()
                }
            }
            .frame(width: MapLayoutMetrics.controlSize, height: MapLayoutMetrics.controlSize)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .background(
            reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
            in: Circle()
        )
        .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: Circle())
        .disabled(isLocating)
        .accessibilityLabel(Text(isLocating ? MapKeys.locating : MapKeys.currentLocation))
        .accessibilityIdentifier(MapAccessibility.currentLocationButton)
        .help(Text(MapKeys.currentLocation))
        .keyboardShortcut(KeyEquivalent(MapKeyboardShortcuts.currentLocation), modifiers: [.command, .shift])
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

private enum MapSymbols {
    static let currentLocation = "location.fill"
}

private enum MapAccessibility {
    static let currentLocationButton = "map.currentLocation"
    static let searchButton = "map.search"
}

private enum MapKeyboardShortcuts {
    static let currentLocation: Character = "l"
    static let search: Character = "f"
}

private enum MapLayoutMetrics {
    static let controlSize: CGFloat = 44
    static let controlPadding: CGFloat = 12
    static let candidateWidthFraction = 0.7
}

#Preview {
    NavigationStack {
        MapView(viewModel: MapPreviewFixtures.model(), rendersLiveMap: false)
    }
    .environment(MapPreviewFixtures.coordinator())
    .environment(AppPreferences(store: PreviewPreferenceStore()))
    .environment(DSToastManager())
}

#Preview {
    MapCurrentLocationButton(isLocating: false) {}
        .padding()
        .preferredColorScheme(.light)
}

#Preview {
    MapCurrentLocationButton(isLocating: false) {}
        .padding()
        .preferredColorScheme(.dark)
}

#Preview {
    MapCurrentLocationButton(isLocating: true) {}
        .padding()
}
