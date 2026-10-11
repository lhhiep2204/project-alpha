//
//  MapPlaceSearchModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 9/10/26.
//

import Foundation
import Observation

nonisolated protocol PlaceSearchDebounceClock: Sendable {
    func sleep(for duration: Duration) async throws
}

nonisolated struct ContinuousPlaceSearchDebounceClock: PlaceSearchDebounceClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

enum MapPlaceSearchPhase: Equatable {
    case idle
    case debouncing
    case loading
    case results
    case empty
    case failed(PlaceServiceError)
}

/// One presentation owns one provider session. UI reconstruction never owns provider state.
@Observable
@MainActor
final class MapPlaceSearchModel {
    private let service: (any PlaceSearchService)?
    private let clock: any PlaceSearchDebounceClock
    private let makeID: () -> UUID
    @ObservationIgnored private var session: (any PlaceSearchSession)?
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var resolutionTask: Task<Void, Never>?
    private var lifecycleGeneration: UInt64 = 0
    private var queryGeneration: UInt64 = 0
    private var resolutionGeneration: UInt64 = 0
    private var active = false
    private var dismissed = false
    private var localeIdentifier: String?
    private var region: PlaceSearchRegion?
    private var resultRequest: PlaceSearchRequest?
    private var failedSuggestion: PlaceSuggestion?

    private(set) var query = MapSearchConstants.emptyQuery
    private(set) var suggestions: [PlaceSuggestion] = []
    private(set) var phase: MapPlaceSearchPhase = .idle
    private(set) var resolvingSuggestionID: String?
    private(set) var resolutionError: PlaceServiceError?
    private(set) var resolvedCandidate: PlaceCandidate?

    /// Deterministic cancellation/race evidence can await the actual owned operation.
    var pendingSearchTask: Task<Void, Never>? { queryTask }
    var pendingResolutionTask: Task<Void, Never>? { resolutionTask }

    init(
        service: (any PlaceSearchService)?,
        clock: any PlaceSearchDebounceClock = ContinuousPlaceSearchDebounceClock(),
        makeID: @escaping () -> UUID = UUID.init
    ) {
        self.service = service
        self.clock = clock
        self.makeID = makeID
    }

    func start(localeIdentifier: String?, region: PlaceSearchRegion?) async {
        guard !active, !dismissed else { return }
        active = true
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        self.localeIdentifier = localeIdentifier
        self.region = region
        guard let service else {
            phase = .failed(.providerUnavailable)
            return
        }
        let created = await service.makeSearchSession(id: makeID())
        guard active, lifecycleGeneration == generation, !Task.isCancelled else {
            await created.cancel()
            return
        }
        session = created
        scheduleSearch()
    }

    /// Stop work immediately but retain the user's query across background/tab changes.
    func stop() {
        active = false
        lifecycleGeneration += 1
        invalidateOperations()
        resultRequest = nil
        if let session {
            self.session = nil
            Task { await session.cancel() }
        }
    }

    /// A dismissed model cannot resume, even if an old lifecycle callback retains it.
    func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        stop()
        query = MapSearchConstants.emptyQuery
        suggestions = []
        phase = .idle
        localeIdentifier = nil
        region = nil
    }

    func updateQuery(_ query: String) {
        guard !dismissed, self.query != query else { return }
        self.query = query
        scheduleSearch()
    }

    /// Map movement updates the next request's bias without silently repeating a query.
    func updateRegion(_ region: PlaceSearchRegion?) {
        guard !dismissed else { return }
        self.region = region
    }

    func updateLocale(_ localeIdentifier: String?) {
        guard !dismissed, self.localeIdentifier != localeIdentifier else { return }
        self.localeIdentifier = localeIdentifier
        scheduleSearch()
    }

    func retry() {
        if let failedSuggestion {
            select(failedSuggestion)
        } else {
            scheduleSearch()
        }
    }

    func select(_ suggestion: PlaceSuggestion) {
        guard active, let session, let searchRequest = resultRequest,
              suggestions.contains(suggestion), resolvingSuggestionID == nil else { return }
        resolutionGeneration += 1
        let generation = resolutionGeneration
        let lifecycle = lifecycleGeneration
        let request = PlaceSuggestionResolutionRequest(
            searchRequest: searchRequest,
            generation: generation,
            suggestion: suggestion,
            candidateID: makeID()
        )
        resolvingSuggestionID = suggestion.id
        resolutionError = nil
        failedSuggestion = nil
        resolutionTask?.cancel()
        resolutionTask = Task { [weak self] in
            do {
                let result = try await session.resolve(request)
                guard let self, self.accepts(lifecycle: lifecycle, request: searchRequest),
                      self.resolutionGeneration == generation, result.request == request else { return }
                self.resolvingSuggestionID = nil
                self.resolvedCandidate = result.candidate
            } catch {
                guard let self, self.accepts(lifecycle: lifecycle, request: searchRequest),
                      self.resolutionGeneration == generation else { return }
                self.resolvingSuggestionID = nil
                let error = Self.providerError(error)
                if !Self.isCancellation(error) {
                    self.resolutionError = error
                    self.failedSuggestion = suggestion
                }
            }
        }
    }

    private func scheduleSearch() {
        guard !dismissed else { return }
        invalidateOperations()
        resultRequest = nil
        suggestions = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .idle
            return
        }
        guard active else { return }
        guard let session else {
            phase = service == nil ? .failed(.providerUnavailable) : .loading
            return
        }
        let generation = queryGeneration
        let lifecycle = lifecycleGeneration
        let clock = clock
        phase = .debouncing
        queryTask = Task { [weak self] in
            do {
                try await clock.sleep(for: MapSearchConstants.debounceDuration)
            } catch { return }
            guard let request = self?.beginRequest(
                sessionID: session.id, generation: generation, lifecycle: lifecycle, query: trimmed
            ) else { return }
            do {
                let result = try await session.suggestions(for: request)
                guard let self, self.accepts(lifecycle: lifecycle, request: request),
                      result.request == request else { return }
                self.resultRequest = request
                self.suggestions = result.suggestions
                self.phase = result.suggestions.isEmpty ? .empty : .results
            } catch {
                guard let self, self.accepts(lifecycle: lifecycle, request: request) else { return }
                let error = Self.providerError(error)
                if !Self.isCancellation(error) { self.phase = .failed(error) }
            }
        }
    }

    private func beginRequest(sessionID: UUID, generation: UInt64, lifecycle: UInt64, query: String) -> PlaceSearchRequest? {
        guard active, lifecycleGeneration == lifecycle, queryGeneration == generation, !Task.isCancelled else { return nil }
        phase = .loading
        return PlaceSearchRequest(
            sessionID: sessionID,
            generation: generation,
            query: query,
            region: region,
            localeIdentifier: localeIdentifier
        )
    }

    private func invalidateOperations() {
        queryGeneration += 1
        resolutionGeneration += 1
        queryTask?.cancel()
        resolutionTask?.cancel()
        queryTask = nil
        resolutionTask = nil
        resolvingSuggestionID = nil
        resolutionError = nil
        failedSuggestion = nil
        resolvedCandidate = nil
    }

    private func accepts(lifecycle: UInt64, request: PlaceSearchRequest) -> Bool {
        active && lifecycleGeneration == lifecycle && queryGeneration == request.generation
            && localeIdentifier == request.localeIdentifier && !Task.isCancelled
    }

    private static func isCancellation(_ error: PlaceServiceError) -> Bool {
        switch error {
        case .cancelled, .superseded, .sessionEnded: true
        default: false
        }
    }

    /// Task closures erase the provider's typed throws at a do/catch boundary.
    private static func providerError(_ error: any Error) -> PlaceServiceError {
        if let error = error as? PlaceServiceError { return error }
        if error is CancellationError { return .cancelled }
        return .providerUnavailable
    }
}

private enum MapSearchConstants {
    static let emptyQuery = ""
    static let debounceDuration: Duration = .seconds(1)
}
