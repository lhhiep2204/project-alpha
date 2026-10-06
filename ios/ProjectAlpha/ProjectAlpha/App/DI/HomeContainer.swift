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
        router: Router<HomeRoute>,
        repository: any CollectionRepository,
        selection: Binding<HomeRoute?>
    ) -> HomeView {
        HomeView(
            viewModel: HomeViewModel(
                router: router,
                repository: repository,
                useCases: CollectionUseCases(repository: repository)
            ),
            selection: selection
        )
    }

    func makeCollectionDetailView(
        id: UUID,
        repository: any CollectionRepository,
        router: Router<HomeRoute>
    ) -> CollectionDetailView {
        CollectionDetailView(viewModel: CollectionDetailViewModel(
            collectionID: id,
            repository: repository,
            router: router
        ))
    }
}
