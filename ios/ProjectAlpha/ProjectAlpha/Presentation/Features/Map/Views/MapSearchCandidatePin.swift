//
//  MapSearchCandidatePin.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 9/10/26.
//

import SwiftUI

struct MapSearchCandidatePin: View {
    let candidate: PlaceCandidate
    let maximumWidth: CGFloat

    var body: some View {
        VStack(spacing: MapCandidatePinMetrics.spacing) {
            VStack(spacing: MapCandidatePinMetrics.spacing) {
                Text(candidate.name)
                    .font(.headline)
                if let address = candidate.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                } else {
                    Text(MapKeys.addressUnavailable)
                        .font(.caption)
                }
            }
            .multilineTextAlignment(.center)
            .padding(MapCandidatePinMetrics.padding)
            .frame(maxWidth: maximumWidth)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MapCandidatePinMetrics.cornerRadius))
            Image.appIcon(.marker)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(MapCandidatePinAccessibility.selectedPlace)
    }
}

private enum MapCandidatePinMetrics {
    static let spacing: CGFloat = 4
    static let padding: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    static let previewWidth: CGFloat = 280
}

private enum MapCandidatePinAccessibility {
    static let selectedPlace = "map.selectedSearchPlace"
}

#Preview {
    MapSearchCandidatePin(candidate: MapSearchPreviewFixtures.candidate, maximumWidth: MapCandidatePinMetrics.previewWidth)
        .padding()
}
