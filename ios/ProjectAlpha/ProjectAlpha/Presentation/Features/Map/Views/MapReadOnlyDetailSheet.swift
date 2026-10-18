//
//  MapReadOnlyDetailSheet.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 11/10/26.
//

import SwiftUI

struct MapReadOnlyDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let place: MapQuickPlace
    let onOpenInMaps: () -> Void
    var route: MapRouteModel? = nil
    var distanceUnit: DistanceUnit = .kilometre

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MapDetailMetrics.sectionSpacing) {
                    MapDetailPlaceHeader(name: place.name, address: place.address)

                    if !place.isCurrentPosition {
                        Divider()
                        MapRouteSummaryView(state: route?.state ?? .noOrigin, distanceUnit: distanceUnit)
                    }

                    Divider()
                    MapDetailCoordinates(coordinate: place.coordinate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MapDetailMetrics.contentPadding)
                .textSelection(.enabled)
            }
            .navigationTitle(Text(MapKeys.viewDetails))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(CommonKeys.openInMaps, action: onOpenInMaps)
                        .accessibilityIdentifier(MapDetailAccessibility.openInMaps)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(CommonKeys.close) { dismiss() }
                }
            }
        }
    }
}

private struct MapDetailPlaceHeader: View {
    let name: String?
    let address: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MapDetailMetrics.rowSpacing) {
            Group {
                if let name { Text(verbatim: name) }
                else { Text(MapKeys.myLocation) }
            }
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)

            Group {
                if let address, !address.isEmpty { Text(verbatim: address) }
                else { Text(MapKeys.addressUnavailable) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MapDetailCoordinates: View {
    let coordinate: Coordinate

    var body: some View {
        VStack(alignment: .leading, spacing: MapDetailMetrics.rowSpacing) {
            Text(MapKeys.coordinates).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MapDetailMetrics.coordinateSpacing) {
                    latitude
                    longitude
                }
                VStack(alignment: .leading, spacing: MapDetailMetrics.rowSpacing) {
                    latitude
                    longitude
                }
            }
        }
        .font(MapPlaceTypography.fact)
        .accessibilityElement(children: .combine)
    }

    private var latitude: some View {
        Text(coordinate.latitude, format: .number.precision(.fractionLength(MapDetailMetrics.coordinateDigits)))
    }

    private var longitude: some View {
        Text(coordinate.longitude, format: .number.precision(.fractionLength(MapDetailMetrics.coordinateDigits)))
    }
}

private enum MapDetailMetrics {
    static let coordinateDigits = 6
    static let rowSpacing: CGFloat = 8
    static let coordinateSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    static let contentPadding: CGFloat = 20
}

private enum MapDetailAccessibility {
    static let openInMaps = "map.detailOpenInMaps"
}

#Preview {
    MapReadOnlyDetailSheet(place: MapQuickPlacePreviewFixtures.searchPlace, onOpenInMaps: {})
}

#Preview {
    MapReadOnlyDetailSheet(place: MapQuickPlacePreviewFixtures.currentPlace, onOpenInMaps: {})
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview {
    MapDetailPlaceHeader(
        name: MapQuickPlacePreviewFixtures.searchPlace.name,
        address: MapQuickPlacePreviewFixtures.searchPlace.address
    )
    .padding()
}

#Preview {
    MapDetailCoordinates(coordinate: MapQuickPlacePreviewFixtures.searchPlace.coordinate)
        .padding()
}
