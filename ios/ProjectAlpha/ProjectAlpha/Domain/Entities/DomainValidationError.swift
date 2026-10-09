//
//  DomainValidationError.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/9/26.
//

import Foundation

/// Typed validation failures. Presentation supplies localized user-facing copy.
nonisolated enum DomainValidationError: Error, Equatable, Sendable {
    case collectionNameRequired
    case collectionNameTooLong(maximum: Int)
    case invalidCoordinate
    case invalidPlaceIdentity
    case invalidAssetReference
}
