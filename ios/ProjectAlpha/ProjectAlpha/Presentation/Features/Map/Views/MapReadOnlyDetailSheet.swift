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

    private var title: Text {
        if let name = place.name { return Text(name) }
        return Text(MapKeys.myLocation)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MapDetailMetrics.rowSpacing) {
                    LabeledContent {
                        if let name = place.name {
                            Text(name)
                        } else {
                            Text(MapKeys.myLocation)
                        }
                    } label: {
                        Text(MapKeys.name)
                    }

                    LabeledContent {
                        if let address = place.address, !address.isEmpty {
                            Text(address)
                        } else {
                            Text(MapKeys.addressUnavailable)
                        }
                    } label: {
                        Text(MapKeys.address)
                    }

                    LabeledContent {
                        VStack(alignment: .trailing) {
                            Text(place.coordinate.latitude, format: .number.precision(.fractionLength(MapDetailMetrics.coordinateDigits)))
                            Text(place.coordinate.longitude, format: .number.precision(.fractionLength(MapDetailMetrics.coordinateDigits)))
                        }
                    } label: {
                        Text(MapKeys.coordinates)
                    }

                    if let accuracy = place.horizontalAccuracyMetres,
                       let timestamp = place.timestamp {
                        LabeledContent {
                            Text(Measurement(value: accuracy, unit: UnitLength.meters), format: .measurement(width: .abbreviated))
                        } label: {
                            Text(MapKeys.horizontalAccuracy)
                        }
                        LabeledContent {
                            Text(timestamp, format: .dateTime.day().month().year().hour().minute())
                        } label: {
                            Text(MapKeys.positionTimestamp)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(title)
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

private enum MapDetailMetrics {
    static let coordinateDigits = 6
    static let rowSpacing: CGFloat = 16
}

private enum MapDetailAccessibility {
    static let openInMaps = "map.detailOpenInMaps"
}

#Preview {
    MapReadOnlyDetailSheet(place: MapQuickPlacePreviewFixtures.searchPlace, onOpenInMaps: {})
}

#Preview {
    MapReadOnlyDetailSheet(place: MapQuickPlacePreviewFixtures.currentPlace, onOpenInMaps: {})
}
