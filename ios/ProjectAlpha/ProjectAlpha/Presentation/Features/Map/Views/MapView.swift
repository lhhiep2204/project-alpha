//
//  MapView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

struct MapView: View {
    @State private var viewModel: MapViewModel

    init(viewModel: MapViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ContentUnavailableView(
            "Map",
            systemImage: "map.fill",
            description: Text("Map feature content will appear here.")
        )
        .navigationTitle("Map")
    }
}

#Preview {
    MapView(viewModel: .init(router: .init(root: .root)))
}
