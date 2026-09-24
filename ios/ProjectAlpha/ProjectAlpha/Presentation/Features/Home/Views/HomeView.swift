//
//  HomeView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ContentUnavailableView(
            "Home",
            systemImage: "house.fill",
            description: Text("Home feature content will appear here.")
        )
        .navigationTitle("Home")
    }
}

#Preview {
    HomeView(viewModel: .init(router: .init(root: .root)))
}
