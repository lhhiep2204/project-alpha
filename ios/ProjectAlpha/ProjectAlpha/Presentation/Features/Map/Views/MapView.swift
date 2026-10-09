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
    @State private var viewModel: MapViewModel
    private let rendersLiveMap: Bool

    init(viewModel: MapViewModel, rendersLiveMap: Bool = true) {
        _viewModel = State(initialValue: viewModel)
        self.rendersLiveMap = rendersLiveMap
    }

    private var isMapActive: Bool {
        rendersLiveMap && coordinator.selectedTab == .map && scenePhase == .active
    }

    var body: some View {
        @Bindable var model = viewModel

        mapCanvas
            .overlay(alignment: .bottomTrailing) {
                MapCurrentLocationButton(isLocating: viewModel.isLocating) {
                    viewModel.requestRecenter()
                }
                .padding(MapLayoutMetrics.controlPadding)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: MapLocationTaskID(active: isMapActive, recenterID: viewModel.recenterRequestID)) {
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

    @ViewBuilder
    private var mapCanvas: some View {
        @Bindable var model = viewModel
        if rendersLiveMap {
            Map(position: $model.cameraPosition) {
                if isMapActive && viewModel.showsUserLocation {
                    UserAnnotation()
                }
            }
            .mapStyle(preferences.mapType.mapStyle)
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .onEnd) { _ in
                if viewModel.cameraPosition.positionedByUser {
                    viewModel.userDidChangeCamera()
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
    let isLocating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isLocating {
                ProgressView()
                    .frame(width: MapLayoutMetrics.controlSize, height: MapLayoutMetrics.controlSize)
            } else {
                Label {
                    Text(MapKeys.currentLocation)
                } icon: {
                    Image(systemName: MapSymbols.currentLocation)
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
                .labelStyle(.iconOnly)
                .frame(width: MapLayoutMetrics.controlSize, height: MapLayoutMetrics.controlSize)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
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
}

private enum MapKeyboardShortcuts {
    static let currentLocation: Character = "l"
}

private enum MapLayoutMetrics {
    static let controlSize: CGFloat = 44
    static let controlPadding: CGFloat = 12
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
