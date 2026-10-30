//
//  CollectionDetailView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 26/9/26.
//

import SwiftUI

struct CollectionDetailView: View {
    @Environment(DSToastManager.self) private var toastManager
    @Environment(SceneCoordinator.self) private var coordinator
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: CollectionDetailViewModel
    @State private var observationAttempt = 0
    @State private var pendingSavedID: UUID?
    private let onOpenMap: (UUID?) -> Void

    init(viewModel: CollectionDetailViewModel, onOpenMap: @escaping (UUID?) -> Void = { _ in }) {
        _viewModel = State(initialValue: viewModel)
        self.onOpenMap = onOpenMap
    }

    var body: some View {
        @Bindable var viewModel = viewModel
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
                    DSButton(CollectionKeys.retry) {
                        observationAttempt &+= 1
                    }
                }
            case .ready:
                List {
                    Section {
                        DSButton { onOpenMap(nil) } label: {
                            Label {
                                Text(String(format: LocalizationManager.localizedString(LocationKeys.showAllOnMap, locale: locale),
                                            locale: locale, Int64(viewModel.collection?.locationCount ?? 0)))
                            } icon: { Image.appSystemIcon(.map) }
                        }
                    }
                    if viewModel.locations.isEmpty {
                        ContentUnavailableView(
                            LocalizedStringKey(CollectionKeys.emptyCollectionTitle.rawValue),
                            systemImage: DSSystemIcon.location.rawValue,
                            description: Text(CollectionKeys.emptyCollectionMessage)
                        )
                        .listRowBackground(Color.clear)
                    } else if viewModel.filteredLocations.isEmpty {
                        Text(LocationKeys.noMatches).foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.filteredLocations) { location in
                        DSButton { onOpenMap(location.id) } label: {
                            CollectionLocationRow(location: location)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            deleteButton(for: location)
                            editButton(for: location).tint(.gray)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            shareButton(for: location).tint(.blue)
                        }
                        .contextMenu {
                            shareButton(for: location)
                            editButton(for: location)
                            deleteButton(for: location)
                            DSButton {
                                Task { await viewModel.toggleFavorite(location) }
                            } label: {
                                Label {
                                    Text(location.isFavorite ? LocationKeys.removeFavorite : LocationKeys.addFavorite)
                                } icon: {
                                    Image.appSystemIcon(location.isFavorite ? .favorite : .favoriteEmpty)
                                }
                            }
                        }
                        .accessibilityAction(named: Text(CommonKeys.edit)) {
                            Task { await viewModel.editLocation(location) }
                        }
                        .accessibilityAction(named: Text(CommonKeys.delete)) { viewModel.requestDelete(location) }
                        .accessibilityActions { shareButton(for: location) }
                        .confirmationDialog(
                            Text(CommonKeys.delete),
                            isPresented: deleteConfirmation(for: location.id),
                            presenting: viewModel.deleteTarget
                        ) { _ in
                            DSButton(role: .destructive) { Task { await deleteLocation() } } label: {
                                Text(CommonKeys.delete)
                            }
                            DSButton(role: .cancel) { viewModel.deleteTarget = nil } label: {
                                Text(CommonKeys.cancel)
                            }
                        } message: { target in
                            Text(String(format: LocalizationManager.localizedString(LocationKeys.deleteMessage, locale: locale),
                                        locale: locale, target.displayName ?? target.name))
                        }
                    }
                    if viewModel.favoriteFailed { Text(LocationKeys.saveFailed).foregroundStyle(.red) }
                }
                .searchable(text: $viewModel.query, prompt: Text(LocationKeys.search))
                .animation(reduceMotion ? nil : .default, value: viewModel.filteredLocations.map(\.id))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(displayTitle)
        .toolbar {
            if viewModel.phase == .ready {
                ToolbarItem(placement: .topBarTrailing) {
                    DSButton { viewModel.favoritesOnly.toggle() } label: {
                        Label {
                            Text(LocationKeys.favoritesOnly)
                        } icon: {
                            Image.appSystemIcon(viewModel.favoritesOnly ? .favorite : .favoriteEmpty)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityAddTraits(viewModel.favoritesOnly ? .isSelected : [])
                }
            }
        }
        .task(id: observationAttempt) { await observe() }
        .sheet(isPresented: editorPresented, onDismiss: {
            viewModel.editorDidDismiss()
            if let id = pendingSavedID {
                pendingSavedID = nil
                coordinator.openSavedLocationInGlobalMap(id: id)
            }
        }) {
            if let editor = viewModel.editor {
                LocationDetailsEditor(model: editor, onOpenSaved: { id in
                    pendingSavedID = id
                    viewModel.dismissEditor()
                })
                .onAppear { viewModel.editorDidPresent() }
            }
        }
        .alert(Text(CommonKeys.error), isPresented: actionErrorPresented) {
            if case .editConflict = viewModel.actionError {
                DSButton(CommonKeys.retry) {
                    viewModel.actionError = nil
                    viewModel.deleteNeedsConfirmation = true
                }
            } else if viewModel.deleteTarget != nil, !isMissingError {
                DSButton(CommonKeys.retry) { Task { await deleteLocation() } }
            }
            DSButton(role: .cancel) { viewModel.deleteTarget = nil; viewModel.actionError = nil } label: {
                Text(CommonKeys.cancel)
            }
        } message: { Text(actionErrorMessage) }
    }

    private func deleteLocation() async {
        if await viewModel.deleteLocation() { toastManager.show(LocationKeys.deleteSucceeded) }
    }

    private func deleteConfirmation(for locationID: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.deleteNeedsConfirmation && viewModel.deleteTarget?.id == locationID },
            set: { presented in
                guard viewModel.deleteTarget?.id == locationID else { return }
                // Native dismissal precedes the action; retain the target for deletion or retry.
                viewModel.deleteNeedsConfirmation = presented
            }
        )
    }

    private var editorPresented: Binding<Bool> {
        Binding(get: { viewModel.editor != nil }, set: { presented in
            if !presented {
                viewModel.dismissEditor()
            }
        })
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { presented in
            if !presented { viewModel.actionError = nil }
        })
    }

    private var isMissingError: Bool {
        if case .locationMissing = viewModel.actionError { return true }
        return false
    }

    private var actionErrorMessage: LocationKeys {
        if isMissingError { return .locationMissing }
        if case .editConflict = viewModel.actionError { return .deleteConflict }
        return viewModel.deleteTarget == nil ? .locationLoadFailed : .deleteFailed
    }

    private func editButton(for location: SavedLocation) -> some View {
        DSButton { Task { await viewModel.editLocation(location) } } label: {
            Label { Text(CommonKeys.edit) } icon: { Image.appSystemIcon(.edit) }
        }
        .disabled(viewModel.isPerformingAction)
    }

    private func shareButton(for location: SavedLocation) -> some View {
        let payload = viewModel.sharePayload(for: location)
        return ShareLink(
            item: payload.shareText(includeNotes: false),
            preview: SharePreview(payload.name)
        ) {
            Label { Text(CommonKeys.share) } icon: { Image.appSystemIcon(.share) }
        }
        .disabled(!viewModel.canShareLocation)
    }

    private func deleteButton(for location: SavedLocation) -> some View {
        DSButton { viewModel.requestDelete(location) } label: {
            Label { Text(CommonKeys.delete) } icon: { Image.appSystemIcon(.delete) }
        }
        .tint(.red)
        .disabled(viewModel.isPerformingAction)
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
            router: Router<HomeRoute>(paths: [.collection(id: Collection.mock.id)], root: .root),
            locationRepository: CollectionLocationPreviewRepository(location: LocationEditorPreview.savedLocation)
        ))
    }
    .environment(SceneCoordinator())
    .environment(DSToastManager())
}


private struct CollectionLocationRow: View {
    @Environment(\.locale) private var locale
    let location: SavedLocation
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(location.displayName ?? location.name).font(.headline)
                if location.displayName != nil { Text(location.name).font(.subheadline) }
                if let address = location.address { Text(address).font(.subheadline).foregroundStyle(.secondary) }
                Text(location.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
                    .font(.caption)
            }
            Spacer()
            if location.isFavorite {
                Image.appSystemIcon(.favorite).accessibilityLabel(Text(LocationKeys.favoritesOnly))
            }
        }
        .foregroundStyle(.primary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

#Preview { CollectionLocationRow(location: LocationEditorPreview.savedLocation) }

/// Finite, deterministic list data; previews never open the user's library.
private actor CollectionLocationPreviewRepository: LocationRepository {
    let sample: SavedLocation

    init(location: SavedLocation) { sample = location }

    func locationSnapshot(collectionID: UUID?) async throws -> LocationLibrarySnapshot {
        LocationLibrarySnapshot(collections: [CollectionSummary(collection: .mock, locationCount: 1)],
                                locations: [sample], libraryRevision: 1)
    }

    func observeLocations(collectionID: UUID?) async -> AsyncThrowingStream<LocationLibrarySnapshot, any Error> {
        let snapshot = try? await locationSnapshot(collectionID: collectionID)
        return AsyncThrowingStream { continuation in
            if let snapshot { continuation.yield(snapshot) }
            continuation.finish()
        }
    }

    func location(id: UUID) async throws -> SavedLocation? { id == sample.id ? sample : nil }
    func createLocation(_ command: CreateLocationCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageUnavailable
    }
    func setLocationFavorite(_ command: SetLocationFavoriteCommand) async throws -> LocationCommit {
        throw LocationWriteError.storageUnavailable
    }
}
