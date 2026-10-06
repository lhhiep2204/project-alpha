//
//  HomeViewModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation

@MainActor
@Observable
final class HomeViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed
    }

    private let router: Router<HomeRoute>
    let repository: any CollectionRepository
    let useCases: CollectionUseCases
    private(set) var phase: Phase = .loading
    private(set) var collections: [CollectionSummary] = []
    private(set) var visibleCollections: [CollectionSummary] = []
    private(set) var libraryRevision: Int64 = -1
    private(set) var deletionError = false
    private(set) var changedCollection: CollectionSummary?
    private(set) var deletingID: UUID?
    var observationID = 0
    var searchText = String() {
        didSet { updateVisibleCollections() }
    }

    init(
        router: Router<HomeRoute>,
        repository: any CollectionRepository,
        useCases: CollectionUseCases
    ) {
        self.router = router
        self.repository = repository
        self.useCases = useCases
    }

    func observe() async {
        phase = .loading
        do {
            let stream = await repository.observeSnapshots()
            for try await snapshot in stream {
                guard !Task.isCancelled else { return }
                apply(snapshot)
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    func retry() {
        observationID &+= 1
    }

    func reload() async {
        do {
            apply(try await repository.snapshot())
        } catch {
            if collections.isEmpty { phase = .failed }
        }
    }

    func open(_ summary: CollectionSummary) {
        router.push(.collection(id: summary.id))
    }

    func delete(_ summary: CollectionSummary) async {
        guard !summary.collection.isDefault, deletingID == nil else { return }
        deletingID = summary.id
        defer { deletingID = nil }
        do {
            _ = try await useCases.delete.execute(summary)
            await reload()
        } catch CollectionWriteError.editConflict(let latest, let count) {
            changedCollection = CollectionSummary(collection: latest, locationCount: count)
        } catch {
            deletionError = true
        }
    }

    func clearDeletionError() { deletionError = false }
    func clearChangedCollection() { changedCollection = nil }

    private func apply(_ snapshot: CollectionListSnapshot) {
        guard snapshot.libraryRevision >= libraryRevision else { return }
        libraryRevision = snapshot.libraryRevision
        // CollectionListSnapshot already carries the store's stable Home order.
        collections = snapshot.collections
        updateVisibleCollections()
        phase = .ready
    }

    private func updateVisibleCollections() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleCollections = query.isEmpty
            ? collections
            : collections.filter { $0.collection.name.localizedCaseInsensitiveContains(query) }
    }
}
