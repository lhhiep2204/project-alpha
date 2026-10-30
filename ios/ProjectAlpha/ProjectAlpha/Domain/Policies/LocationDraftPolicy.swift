//
//  LocationDraftPolicy.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation

nonisolated enum LocationDraftPolicy {
    static let maximumDisplayNameLength = 50
    static let maximumManualNameLength = 80
    static let maximumNotesLength = 10_000
    static let maximumPhotoCount = 5

    static func validate(_ draft: LocationDraft) throws(LocationValidationError) {
        let name = draft.candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .nameRequired }
        if draft.candidate.source.isManual, name.count > maximumManualNameLength {
            throw .manualNameTooLong
        }
        guard (draft.displayName?.count ?? 0) <= maximumDisplayNameLength else { throw .displayNameTooLong }
        guard (draft.notes?.count ?? 0) <= maximumNotesLength else { throw .notesTooLong }
        guard draft.assets.count <= maximumPhotoCount else { throw .tooManyPhotos }
        guard draft.createdAt.timeIntervalSinceReferenceDate.isFinite else { throw .invalidDate }
    }

    static func optionalText(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
