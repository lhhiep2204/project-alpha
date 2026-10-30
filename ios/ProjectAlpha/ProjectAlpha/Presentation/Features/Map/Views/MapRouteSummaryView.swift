//
//  MapRouteSummaryView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import SwiftUI

struct MapRouteSummaryView: View {
    @Environment(\.locale) private var locale
    let state: MapRouteState
    let distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: MapRouteSummaryMetrics.spacing) {
            switch state {
            case .idle: EmptyView()
            case .noOrigin:
                Text(MapKeys.routeOriginUnavailable)
                    .foregroundStyle(.secondary)
            case let .distanceOnly(distance):
                straightLine(distance)
                Text(MapKeys.routeDistanceOnly).foregroundStyle(.secondary)
            case let .loading(_, mode):
                routeLine(mode: mode) {
                    Text(MapKeys.routeCalculating)
                }
            case let .unavailable(distance, _):
                straightLine(distance)
            case let .available(_, estimate):
                routeLine(mode: estimate.mode) {
                    Text(verbatim: routeDescription(estimate))
                }
            }
        }
        .font(MapPlaceTypography.fact)
        .accessibilityIdentifier(MapRouteSummaryAccessibility.summary)
    }

    private func routeLine<Content: View>(mode: RouteMode, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MapRouteSummaryMetrics.spacing) {
            Image(systemName: mode == .walking ? MapRouteSummarySymbols.walking : MapRouteSummarySymbols.driving)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(mode == .walking ? MapKeys.walking : MapKeys.driving))
            content()
        }
        .accessibilityElement(children: .combine)
    }

    private func straightLine(_ distance: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MapRouteSummaryMetrics.spacing) {
            Text(MapKeys.straightLineDistance).foregroundStyle(.secondary)
            Text(distanceUnit.formatted(distance, locale: locale))
        }
        .accessibilityElement(children: .combine)
    }

    private func routeDescription(_ estimate: RouteEstimate) -> String {
        let distance = distanceUnit.formatted(estimate.distanceMetres, locale: locale)
        return distance + MapRouteSummaryMetrics.separator + duration(estimate.duration)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < MapRouteSummaryMetrics.secondsPerMinute
            ? [.seconds] : [.hours, .minutes]
        return Duration.seconds(seconds).formatted(.units(
            allowed: units,
            width: .abbreviated
        ).locale(locale))
    }
}

private enum MapRouteSummaryMetrics {
    static let spacing: CGFloat = 4
    static let separator = " · "
    static let secondsPerMinute: TimeInterval = 60
}

/// Shared semantic typography keeps travel and coordinate facts consistent.
enum MapPlaceTypography {
    static let fact: Font = .subheadline
}

private enum MapRouteSummarySymbols {
    static let walking = "figure.walk"
    static let driving = "car.fill"
}

private enum MapRouteSummaryAccessibility {
    static let summary = "map.routeSummary"
}

@MainActor
enum MapRoutePreviewFixtures {
    static let distanceMetres: Double = 720
    static let request = RouteRequest(
        origin: RouteEndpoint(coordinate: MapQuickPlacePreviewFixtures.currentPlace.coordinate, savedLocationID: nil, placeIdentity: nil),
        destination: RouteEndpoint(coordinate: MapQuickPlacePreviewFixtures.searchPlace.coordinate, savedLocationID: nil, placeIdentity: nil),
        mode: .walking, generation: 1
    )
    static let estimate = try! RouteEstimate(
        request: request, distanceMetres: 860, duration: 660,
        computedAt: Date(timeIntervalSince1970: 1_791_792_000)
    )
    static let available = MapRouteState.available(distanceMetres: distanceMetres, estimate: estimate)
    // The labeled fallback reserves space for the longest travel summary.
    static let unavailable = MapRouteState.unavailable(distanceMetres: distanceMetres, mode: .walking)
}

#Preview {
    MapRouteSummaryView(state: MapRoutePreviewFixtures.available, distanceUnit: .kilometre)
        .padding()
}

#Preview {
    MapRouteSummaryView(state: .unavailable(distanceMetres: MapRoutePreviewFixtures.distanceMetres, mode: .walking), distanceUnit: .mile)
        .padding()
        .environment(\.dynamicTypeSize, .accessibility3)
}
