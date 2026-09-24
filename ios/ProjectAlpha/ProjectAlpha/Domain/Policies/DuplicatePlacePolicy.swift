import Foundation

nonisolated enum BlockingDuplicateReason: Hashable, Sendable {
    case providerIdentity
    case normalizedCoordinateAndName
}

nonisolated struct DuplicateMatchRevision: Hashable, Sendable {
    let locationID: UUID
    let revision: Int64
}

/// A warning acknowledgement is valid only for this draft, destination and exact committed matches.
nonisolated struct DuplicateWarningToken: Hashable, Sendable {
    let draftID: UUID
    let destinationCollectionID: UUID
    let matches: [DuplicateMatchRevision]
}

nonisolated enum DuplicatePlaceEvaluation: Hashable, Sendable {
    case allowed
    case blockingDuplicate(existingLocationID: UUID, reason: BlockingDuplicateReason)
    case possibleDuplicates(candidateIDs: [UUID], evaluationToken: DuplicateWarningToken)
}

/// Pure duplicate policy. Persistence must invoke it again inside its serialized write section.
nonisolated enum DuplicatePlacePolicy {
    static let nearbyWarningThresholdMetres = 20.0

    static func evaluate(
        draftID: UUID,
        destinationCollectionID: UUID,
        candidate: PlaceCandidate,
        against locations: [SavedLocation],
        excluding excludedLocationID: UUID? = nil
    ) -> DuplicatePlaceEvaluation {
        let candidates = locations.filter {
            $0.collectionID == destinationCollectionID && $0.id != excludedLocationID
        }
        let orderedCandidates = candidates.sorted(by: Self.isAscending)

        let hardMatches = orderedCandidates.compactMap { location -> (SavedLocation, BlockingDuplicateReason)? in
            if providerIdentitiesIntersect(candidate.placeIdentity, location.placeIdentity) {
                return (location, .providerIdentity)
            }

            let fallsBackToCoordinateAndName = candidate.placeIdentity == nil || location.placeIdentity == nil
            if fallsBackToCoordinateAndName,
               candidate.coordinate.normalizedMicrodegrees == location.coordinate.normalizedMicrodegrees,
               PlaceNameNormalizer.normalizedIdentityName(candidate.name, source: candidate.source)
                    == PlaceNameNormalizer.normalizedIdentityName(location.name, source: location.source) {
                return (location, .normalizedCoordinateAndName)
            }
            return nil
        }

        if let hardMatch = hardMatches.first {
            return .blockingDuplicate(existingLocationID: hardMatch.0.id, reason: hardMatch.1)
        }

        let possibleMatches = orderedCandidates.filter {
            candidate.coordinate.distance(to: $0.coordinate) <= nearbyWarningThresholdMetres
        }
        guard !possibleMatches.isEmpty else { return .allowed }

        let matchRevisions = possibleMatches.map {
            DuplicateMatchRevision(locationID: $0.id, revision: $0.revision)
        }
        let token = DuplicateWarningToken(
            draftID: draftID,
            destinationCollectionID: destinationCollectionID,
            matches: matchRevisions
        )
        return .possibleDuplicates(
            candidateIDs: possibleMatches.map(\.id),
            evaluationToken: token
        )
    }

    private static func providerIdentitiesIntersect(_ lhs: PlaceIdentity?, _ rhs: PlaceIdentity?) -> Bool {
        guard let lhs, let rhs, lhs.provider == rhs.provider else { return false }
        return !lhs.allIDs.isDisjoint(with: rhs.allIDs)
    }

    private static func isAscending(_ lhs: SavedLocation, _ rhs: SavedLocation) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
