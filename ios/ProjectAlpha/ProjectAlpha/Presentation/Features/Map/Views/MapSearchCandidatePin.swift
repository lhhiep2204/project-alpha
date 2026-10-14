//
//  MapSearchCandidatePin.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 9/10/26.
//

import SwiftUI

struct MapSearchCandidatePin: View {
    let candidate: PlaceCandidate

    var body: some View {
        Image.appIcon(.marker)
            .accessibilityLabel(Text(candidate.name))
            .accessibilityIdentifier(MapCandidatePinAccessibility.selectedPlace)
    }
}

private enum MapCandidatePinAccessibility {
    static let selectedPlace = "map.selectedSearchPlace"
}

#Preview {
    MapSearchCandidatePin(candidate: MapSearchPreviewFixtures.candidate)
        .padding()
}
