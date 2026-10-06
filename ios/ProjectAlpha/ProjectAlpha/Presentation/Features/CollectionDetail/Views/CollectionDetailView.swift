import SwiftUI

struct CollectionDetailView: View {
    @Environment(SceneCoordinator.self) private var coordinator
    @State private var viewModel: CollectionDetailViewModel

    init(viewModel: CollectionDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
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
                        Task { await observe() }
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
        .navigationTitle(viewModel.displayTitle(
            hint: coordinator.collectionTitleHint(for: viewModel.collectionID)
        ))
        .task { await observe() }
    }

    private func observe() async {
        await viewModel.observe {
            coordinator.clearCollectionTitleHint(for: viewModel.collectionID)
        }
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
