//
//  ApplePlaceSearchSession.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import Foundation
import MapKit

@MainActor
protocol ApplePlaceSearchDriver: AnyObject {
    @MainActor func suggestions(_ request: PlaceSearchRequest) -> AppleServiceOperation<PlaceSuggestions>
    @MainActor func resolve(_ request: PlaceSuggestionResolutionRequest) -> AppleServiceOperation<PlaceSuggestionResolution>
    @MainActor func cancel()
}

@MainActor
final class ApplePlaceSearchSession: PlaceSearchSession {
    nonisolated let id: UUID
    private let makeDriver: @MainActor () -> any ApplePlaceSearchDriver
    private var driver: (any ApplePlaceSearchDriver)?
    private var currentRequest: PlaceSearchRequest?
    private var suggestionOperation: AppleServiceOperation<PlaceSuggestions>?
    private var resolutionOperation: AppleServiceOperation<PlaceSuggestionResolution>?
    private var suggestionToken: UUID?
    private var resolutionToken: UUID?
    private var latestResolutionGeneration: UInt64?
    private var ended = false

    init(id: UUID, makeDriver: @escaping @MainActor () -> any ApplePlaceSearchDriver) {
        self.id = id
        self.makeDriver = makeDriver
    }

    @MainActor func suggestions(for request: PlaceSearchRequest) async throws(PlaceServiceError) -> PlaceSuggestions {
        guard !Task.isCancelled else { throw .cancelled }
        guard !ended else { throw .sessionEnded }
        guard request.sessionID == id else { throw .invalidRequest }
        if let currentRequest, request.generation < currentRequest.generation { throw .superseded }
        invalidate(reason: .superseded)
        currentRequest = request
        guard !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PlaceSuggestions(request: request, suggestions: [])
        }
        let token = UUID()
        suggestionToken = token
        let newDriver = makeDriver()
        driver = newDriver
        let operation = newDriver.suggestions(request)
        suggestionOperation = operation
        let result = try await operation.value()
        guard !ended, suggestionToken == token, currentRequest == request else { throw .superseded }
        suggestionOperation = nil
        return result
    }

    @MainActor func resolve(_ request: PlaceSuggestionResolutionRequest) async throws(PlaceServiceError) -> PlaceSuggestionResolution {
        guard !Task.isCancelled else { throw .cancelled }
        guard !ended else { throw .sessionEnded }
        guard request.searchRequest.sessionID == id else { throw .invalidRequest }
        guard currentRequest == request.searchRequest, let driver else { throw .superseded }
        if let latestResolutionGeneration, request.generation < latestResolutionGeneration { throw .superseded }
        latestResolutionGeneration = request.generation
        resolutionOperation?.cancel(reason: .superseded)
        let token = UUID()
        resolutionToken = token
        let operation = driver.resolve(request)
        resolutionOperation = operation
        let result = try await operation.value()
        guard !ended, resolutionToken == token, currentRequest == request.searchRequest else { throw .superseded }
        resolutionOperation = nil
        return result
    }

    @MainActor func cancel() async {
        guard !ended else { return }
        ended = true
        invalidate(reason: .sessionEnded)
        currentRequest = nil
    }

    private func invalidate(reason: PlaceServiceError) {
        suggestionToken = nil
        resolutionToken = nil
        latestResolutionGeneration = nil
        suggestionOperation?.cancel(reason: reason)
        resolutionOperation?.cancel(reason: reason)
        suggestionOperation = nil
        resolutionOperation = nil
        driver?.cancel()
        driver = nil
    }
}

/// A completer is used for exactly one query. A later query receives a new instance/delegate,
/// preventing an old callback from being attributed to a new query fragment.
@MainActor
final class MapKitPlaceSearchDriver: NSObject, ApplePlaceSearchDriver, @MainActor MKLocalSearchCompleterDelegate {
    private var completer: MKLocalSearchCompleter?
    private var suggestionCompletion: AppleServiceOperation<PlaceSuggestions>.Completion?
    private var request: PlaceSearchRequest?
    private var completions: [String: MKLocalSearchCompletion] = [:]
    private var suggestionsByID: [String: PlaceSuggestion] = [:]

    @MainActor func suggestions(_ request: PlaceSearchRequest) -> AppleServiceOperation<PlaceSuggestions> {
        AppleServiceOperation { [self] completion in
            self.request = request
            suggestionCompletion = completion
            let completer = MKLocalSearchCompleter()
            self.completer = completer
            completer.delegate = self
            completer.resultTypes = [.address, .pointOfInterest, .physicalFeature]
            if let region = request.region {
                completer.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
                    span: MKCoordinateSpan(latitudeDelta: region.latitudeDelta, longitudeDelta: region.longitudeDelta)
                )
            }
            completer.queryFragment = request.query
        } cancel: { [weak self] in self?.cancel() }
    }

    @MainActor func resolve(_ request: PlaceSuggestionResolutionRequest) -> AppleServiceOperation<PlaceSuggestionResolution> {
        let completion = completions[request.suggestion.id]
        let matches = self.request == request.searchRequest && suggestionsByID[request.suggestion.id] == request.suggestion
        let sdkRequest = completion.map { MKLocalSearch.Request(completion: $0) }
        let search = sdkRequest.map { MKLocalSearch(request: $0) }
        return AppleServiceOperation(asyncRequest: {
            try Task.checkCancellation()
            guard matches, let search else { throw PlaceServiceError.superseded }
            let response = try await search.start()
            guard let item = response.mapItems.first else { throw PlaceServiceError.notFound }
            do {
                return PlaceSuggestionResolution(
                    request: request,
                    candidate: try AppleMapItemMapper.candidate(item, id: request.candidateID)
                )
            } catch { throw PlaceServiceError.invalidResponse }
        }, cancel: { search?.cancel() })
    }

    @MainActor func cancel() {
        suggestionCompletion = nil
        completer?.delegate = nil
        completer?.cancel()
        completer = nil
        request = nil
        completions.removeAll()
        suggestionsByID.removeAll()
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard self.completer === completer, let request, let callback = suggestionCompletion else { return }
        suggestionCompletion = nil
        completions.removeAll()
        suggestionsByID.removeAll()
        let suggestions = completer.results.map { completion in
            let id = UUID().uuidString
            let suggestion = PlaceSuggestion(id: id, title: completion.title, subtitle: completion.subtitle)
            completions[id] = completion
            suggestionsByID[id] = suggestion
            return suggestion
        }
        callback(.success(PlaceSuggestions(request: request, suggestions: suggestions)))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        guard self.completer === completer, let callback = suggestionCompletion else { return }
        suggestionCompletion = nil
        callback(.failure(AppleServiceErrorMapper.map(error)))
    }
}
