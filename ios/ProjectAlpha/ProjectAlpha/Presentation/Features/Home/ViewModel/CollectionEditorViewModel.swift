//
//  CollectionEditorViewModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 25/9/26.
//

import Foundation

enum CollectionEditorTarget: Identifiable {
    case create(id: UUID, createdAt: Date)
    case edit(Collection)

    var id: UUID {
        switch self {
        case .create(let id, _): id
        case .edit(let collection): collection.id
        }
    }
}

@MainActor
@Observable
final class CollectionEditorViewModel {
    enum SaveError: Equatable {
        case nameRequired
        case nameTooLong
        case missing
        case failed
    }

    private let useCases: CollectionUseCases
    private let target: CollectionEditorTarget
    private var expectedRevision: Int64?
    private var originalName: String
    private(set) var latestConflict: Collection?
    private(set) var saveError: SaveError?
    private(set) var isSaving = false
    var name: String

    var isCreating: Bool {
        if case .create = target { return true }
        return false
    }

    var isDirty: Bool {
        name != originalName
    }

    var isNameValid: Bool { (try? CollectionNamePolicy.validated(name)) != nil }

    init(
        useCases: CollectionUseCases,
        target: CollectionEditorTarget
    ) {
        self.useCases = useCases
        self.target = target
        switch target {
        case .create:
            name = String()
            originalName = String()
        case .edit(let collection):
            name = collection.name
            originalName = collection.name
            expectedRevision = collection.revision
        }
    }

    func save(now: Date = .now) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        do {
            switch target {
            case .create(let id, let createdAt):
                _ = try await useCases.create.execute(
                    CreateCollectionCommand(id: id, name: name, createdAt: createdAt)
                )
            case .edit(let collection):
                _ = try await useCases.update.execute(
                    UpdateCollectionCommand(
                        id: collection.id,
                        expectedRevision: expectedRevision ?? collection.revision,
                        name: name,
                        updatedAt: now
                    )
                )
            }
            return true
        } catch CollectionWriteError.editConflict(let latest, _) {
            latestConflict = latest
        } catch CollectionWriteError.collectionMissing {
            saveError = .missing
        } catch CollectionWriteError.validation(let validation) {
            switch validation {
            case .collectionNameRequired: saveError = .nameRequired
            case .collectionNameTooLong: saveError = .nameTooLong
            default: saveError = .failed
            }
        } catch {
            saveError = .failed
        }
        return false
    }

    func reloadFromConflict() {
        guard let latestConflict else { return }
        name = latestConflict.name
        originalName = latestConflict.name
        expectedRevision = latestConflict.revision
        self.latestConflict = nil
        saveError = nil
    }

    func reapply(now: Date = .now) async -> Bool {
        guard let latestConflict else { return false }
        expectedRevision = latestConflict.revision
        self.latestConflict = nil
        return await save(now: now)
    }

    func clearSaveError() { saveError = nil }
}
