//
//  LocationMediaService.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation

nonisolated enum LocationMediaError: Error, Equatable, Sendable {
    case invalidImage
    case storageFailure
    case photoLimit
}

/// Preparation finishes off the UI actor before the location database transaction.
nonisolated protocol LocationMediaService: Sendable {
    func preparePhoto(data: Data, draftID: UUID) async throws -> LocalAssetReference
    func photoData(for asset: LocalAssetReference, thumbnail: Bool) async throws -> Data
    func discardPhoto(_ asset: LocalAssetReference, draftID: UUID) async
    func cancelDraft(id: UUID) async
    func finishDraft(id: UUID) async
}
