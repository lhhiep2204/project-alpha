//
//  AppleMapFeatureResolver.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 15/10/26.
//

import Foundation
import MapKit
import SwiftUI

/// Resolves the exact feature selected on Apple's map. Name/proximity searches
/// cannot reliably identify that feature, so they are never used as a fallback.
@MainActor
enum AppleMapFeatureResolver {
    static func resolve(_ feature: MapFeature, id: UUID = UUID()) async throws(PlaceServiceError) -> PlaceCandidate {
        let request = MKMapItemRequest(feature: feature)
        let operation = AppleServiceOperation<PlaceCandidate> { completion in
            request.getMapItem { item, error in
                if let error {
                    completion(.failure(AppleServiceErrorMapper.map(error)))
                    return
                }
                guard let item else {
                    completion(.failure(.notFound))
                    return
                }
                do {
                    completion(.success(try AppleMapItemMapper.candidate(item, id: id)))
                } catch {
                    completion(.failure(.invalidResponse))
                }
            }
        } cancel: {
            request.cancel()
        }
        return try await operation.value()
    }
}
