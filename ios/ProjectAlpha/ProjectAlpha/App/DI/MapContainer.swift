//
//  MapContainer.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

@MainActor
final class MapContainer {
    func makeMapView(
        router: Router<MapRoute>
    ) -> MapView {
        MapView(
            viewModel: MapViewModel(
                router: router
            )
        )
    }
}
