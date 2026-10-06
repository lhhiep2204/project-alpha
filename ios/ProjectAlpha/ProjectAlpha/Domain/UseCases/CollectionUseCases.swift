import Foundation

/// Validates a collection draft before the repository rechecks and commits it.
nonisolated struct CreateCollectionUseCase: Sendable {
    private let repository: any CollectionRepository

    init(repository: any CollectionRepository) {
        self.repository = repository
    }

    func execute(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        let name: String
        do {
            name = try CollectionNamePolicy.validated(command.name)
        } catch let error as DomainValidationError {
            throw CollectionWriteError.validation(error)
        }

        return try await repository.create(
            CreateCollectionCommand(id: command.id, name: name, createdAt: command.createdAt)
        )
    }
}

/// Preserves the editor's expected revision while normalizing its name.
nonisolated struct UpdateCollectionUseCase: Sendable {
    private let repository: any CollectionRepository

    init(repository: any CollectionRepository) {
        self.repository = repository
    }

    func execute(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        let name: String
        do {
            name = try CollectionNamePolicy.validated(command.name)
        } catch let error as DomainValidationError {
            throw CollectionWriteError.validation(error)
        }

        return try await repository.update(
            UpdateCollectionCommand(
                id: command.id,
                expectedRevision: command.expectedRevision,
                name: name,
                updatedAt: command.updatedAt
            )
        )
    }
}

/// Uses the confirmed row's revision and count as optimistic delete expectations.
nonisolated struct DeleteCollectionUseCase: Sendable {
    private let repository: any CollectionRepository

    init(repository: any CollectionRepository) {
        self.repository = repository
    }

    func execute(_ summary: CollectionSummary) async throws -> DeleteCollectionCommit {
        try CollectionMutationPolicy.requireDeletable(summary.collection)
        return try await repository.delete(
            DeleteCollectionCommand(
                id: summary.id,
                expectedRevision: summary.collection.revision,
                expectedLocationCount: summary.locationCount
            )
        )
    }
}

/// One injection point for the three collection mutations.
nonisolated struct CollectionUseCases: Sendable {
    let create: CreateCollectionUseCase
    let update: UpdateCollectionUseCase
    let delete: DeleteCollectionUseCase

    init(repository: any CollectionRepository) {
        create = CreateCollectionUseCase(repository: repository)
        update = UpdateCollectionUseCase(repository: repository)
        delete = DeleteCollectionUseCase(repository: repository)
    }
}
