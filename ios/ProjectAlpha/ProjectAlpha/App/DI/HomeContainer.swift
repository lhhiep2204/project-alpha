//
//  HomeContainer.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

@MainActor
final class HomeContainer {
    func makeHomeView(
        router: Router<HomeRoute>
    ) -> HomeView {
        HomeView(
            viewModel: HomeViewModel(
                router: router
            )
        )
    }
}
