//
//  CollectionDetailView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 26/9/26.
//

import SwiftUI

struct CollectionDetailView: View {
    @Environment(SceneCoordinator.self) private var coordinator
    @Environment(\.locale) private var locale
    @State private var viewModel: CollectionDetailViewModel
    @State private var observationAttempt = 0

    init(viewModel: CollectionDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            switch viewModel.phase {
            case .loading:
                ProgressView()
            case .unavailable:
                ContentUnavailableView(
                    LocalizedStringKey(CollectionKeys.collectionUnavailable.rawValue),
                    systemImage: DSSystemIcon.folder.rawValue
                )
            case .failed:
                ContentUnavailableView {
                    Label {
                        Text(CollectionKeys.storageUnavailable)
                    } icon: {
                        Image.appSystemIcon(.folder)
                    }
                } actions: {
                    Button(CollectionKeys.retry) {
                        observationAttempt &+= 1
                    }
                }
            case .ready:
                List {
                    ContentUnavailableView(
                        LocalizedStringKey(CollectionKeys.emptyCollectionTitle.rawValue),
                        systemImage: DSSystemIcon.location.rawValue,
                        description: Text(CollectionKeys.emptyCollectionMessage)
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(displayTitle)
        .task(id: observationAttempt) { await observe() }
    }

    private func observe() async {
        await viewModel.observe {
            coordinator.clearCollectionTitleHint(for: viewModel.collectionID)
        }
    }

    private var displayTitle: String {
        if viewModel.collection?.collection.isDefault == true {
            return LocalizationManager.localizedString(CollectionKeys.defaultCollectionName, locale: locale)
        }
        return viewModel.displayTitle(hint: coordinator.collectionTitleHint(for: viewModel.collectionID))
    }
}

#Preview {
    NavigationStack {
        CollectionDetailView(viewModel: CollectionDetailViewModel(
            collectionID: Collection.mock.id,
            repository: PreviewCollectionRepository(),
            router: Router<HomeRoute>(paths: [.collection(id: Collection.mock.id)], root: .root)
        ))
    }
    .environment(SceneCoordinator())
}
