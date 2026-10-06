import Foundation

@MainActor
@Observable
final class CollectionDetailViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case unavailable
        case failed
    }

    let collectionID: UUID
    private let repository: any CollectionRepository
    private let router: Router<HomeRoute>
    private(set) var collection: CollectionSummary?
    private(set) var phase: Phase = .loading
    private var libraryRevision: Int64 = -1

    init(collectionID: UUID, repository: any CollectionRepository, router: Router<HomeRoute>) {
        self.collectionID = collectionID
        self.repository = repository
        self.router = router
    }

    func displayTitle(hint: String?) -> String {
        guard phase != .unavailable else { return String() }
        return collection?.collection.name ?? hint ?? String()
    }

    func observe(onUnavailable: @MainActor () -> Void = {}) async {
        phase = .loading
        do {
            let stream = await repository.observeSnapshots()
            for try await snapshot in stream {
                guard !Task.isCancelled else { return }
                guard snapshot.libraryRevision >= libraryRevision else { continue }
                libraryRevision = snapshot.libraryRevision
                collection = snapshot.collections.first { $0.id == collectionID }
                phase = collection == nil ? .unavailable : .ready
                if collection == nil {
                    onUnavailable()
                    router.paths.removeAll { route in
                        if case .collection(let id) = route { return id == collectionID }
                        return false
                    }
                    return
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }
}
