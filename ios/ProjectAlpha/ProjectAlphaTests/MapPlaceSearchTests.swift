//
//  MapPlaceSearchTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 9/10/26.
//

import Foundation
import MapKit
import SwiftUI
import Testing
@testable import ProjectAlpha

private enum SearchFixture {
    static let query = "Library"
    static let otherQuery = "Museum"
    static let paddedOtherQuery = "  Museum  "
    static let blank = " \n "
    static let emptyQuery = ""
    static let locale = "vi"
    static let otherLocale = "en"
    static let suggestionID = "library-suggestion"
    static let otherSuggestionID = "museum-suggestion"
    static let name = "Central Library"
    static let address = "Example Street"
    static let primaryID = "opaque-primary"
    static let alternateID = "opaque-alternate"
    static let suggestion = PlaceSuggestion(id: suggestionID, title: name, subtitle: address)
    static let otherSuggestion = PlaceSuggestion(id: otherSuggestionID, title: otherQuery, subtitle: address)

    static func candidate(id: UUID) throws -> PlaceCandidate {
        PlaceCandidate(id: id, source: .appleMaps,
                       placeIdentity: try PlaceIdentity(primaryID: primaryID, alternateIDs: [alternateID]),
                       name: name, address: address, category: nil,
                       coordinate: try Coordinate(latitude: 10, longitude: 20))
    }
}

/// Deliberately ignores task cancellation: tests release every suspension explicitly.
/// This verifies generation checks even when an underlying provider finishes late.
@MainActor
private final class SearchTestClock: PlaceSearchDebounceClock {
    private(set) var durations: [Duration] = []
    private var sleepers: [Int: CheckedContinuation<Void, Never>] = [:]
    private var waiter: (Int, CheckedContinuation<Void, Never>)?

    @MainActor func sleep(for duration: Duration) async throws {
        let index = durations.count
        durations.append(duration)
        await withCheckedContinuation { continuation in
            sleepers[index] = continuation
            if let (count, waiting) = waiter, durations.count >= count {
                waiter = nil
                waiting.resume()
            }
        }
    }

    func waitForSleeps(_ count: Int) async {
        if durations.count >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }

    func release(_ index: Int) { sleepers.removeValue(forKey: index)?.resume() }
}

@MainActor
private final class SearchTestSession: PlaceSearchSession {
    nonisolated let id: UUID
    private(set) var searches: [PlaceSearchRequest] = []
    private(set) var resolutions: [PlaceSuggestionResolutionRequest] = []
    private(set) var cancellations = 0
    private var searchCompletions: [Int: CheckedContinuation<Result<PlaceSuggestions, PlaceServiceError>, Never>] = [:]
    private var resolutionCompletions: [Int: CheckedContinuation<Result<PlaceSuggestionResolution, PlaceServiceError>, Never>] = [:]
    private var searchWaiter: (Int, CheckedContinuation<Void, Never>)?
    private var resolutionWaiter: (Int, CheckedContinuation<Void, Never>)?
    private var cancellationWaiter: CheckedContinuation<Void, Never>?

    init(id: UUID) { self.id = id }

    @MainActor func suggestions(for request: PlaceSearchRequest) async throws(PlaceServiceError) -> PlaceSuggestions {
        let index = searches.count
        searches.append(request)
        let result = await withCheckedContinuation { continuation in
            searchCompletions[index] = continuation
            if let (count, waiting) = searchWaiter, searches.count >= count {
                searchWaiter = nil
                waiting.resume()
            }
        }
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    @MainActor func resolve(_ request: PlaceSuggestionResolutionRequest) async throws(PlaceServiceError) -> PlaceSuggestionResolution {
        let index = resolutions.count
        resolutions.append(request)
        let result = await withCheckedContinuation { continuation in
            resolutionCompletions[index] = continuation
            if let (count, waiting) = resolutionWaiter, resolutions.count >= count {
                resolutionWaiter = nil
                waiting.resume()
            }
        }
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    @MainActor func cancel() async {
        cancellations += 1
        cancellationWaiter?.resume()
        cancellationWaiter = nil
    }

    func waitForSearches(_ count: Int) async {
        if searches.count >= count { return }
        await withCheckedContinuation { searchWaiter = (count, $0) }
    }

    func waitForResolutions(_ count: Int) async {
        if resolutions.count >= count { return }
        await withCheckedContinuation { resolutionWaiter = (count, $0) }
    }

    func waitForCancellation() async {
        if cancellations > 0 { return }
        await withCheckedContinuation { cancellationWaiter = $0 }
    }

    func completeSearch(_ index: Int, suggestions: [PlaceSuggestion]) {
        searchCompletions.removeValue(forKey: index)?.resume(returning: .success(
            PlaceSuggestions(request: searches[index], suggestions: suggestions)))
    }

    func failSearch(_ index: Int, error: PlaceServiceError) {
        searchCompletions.removeValue(forKey: index)?.resume(returning: .failure(error))
    }

    func completeResolution(_ index: Int, candidate: PlaceCandidate) {
        resolutionCompletions.removeValue(forKey: index)?.resume(returning: .success(
            PlaceSuggestionResolution(request: resolutions[index], candidate: candidate)))
    }

    func failResolution(_ index: Int, error: PlaceServiceError) {
        resolutionCompletions.removeValue(forKey: index)?.resume(returning: .failure(error))
    }
}

@MainActor
private final class SearchTestService: PlaceSearchService {
    private(set) var sessions: [SearchTestSession] = []
    @MainActor func makeSearchSession(id: UUID) async -> any PlaceSearchSession {
        let session = SearchTestSession(id: id)
        sessions.append(session)
        return session
    }
}

@MainActor
private final class SearchTestLocationService: DeviceLocationService {
    @MainActor func authorization() async -> LocationAuthorization {
        LocationAuthorization(status: .denied, accuracy: .reduced, servicesEnabled: true)
    }
    @MainActor func currentPosition() async throws(LocationServiceError) -> DevicePosition { throw .permissionDenied }
}

@MainActor
private final class SearchPendingLocationService: DeviceLocationService {
    var status: LocationAuthorizationStatus = .denied
    private var pending: CheckedContinuation<DevicePosition, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    @MainActor func authorization() async -> LocationAuthorization {
        LocationAuthorization(status: status, accuracy: .full, servicesEnabled: true)
    }
    @MainActor func currentPosition() async throws(LocationServiceError) -> DevicePosition {
        await withCheckedContinuation { continuation in
            pending = continuation
            waiter?.resume()
            waiter = nil
        }
    }
    func waitForPosition() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func complete(_ position: DevicePosition) {
        pending?.resume(returning: position)
        pending = nil
    }
}

/// AC-18/19, INV-09, D-03/04/17: deterministic Global Map search increment.
/// No live provider, store, timed sleeps or production persistence is used.
@MainActor
struct MapPlaceSearchTests {
    /// AC-19/58, INV-09: obsolete/cancelled lifecycle callbacks cannot pause the newer live session.
    @Test func staleAndCancelledLifecycleActivityCannotStopReopenedActiveSearch() async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let owner = MapViewModel(router: Router<MapRoute>(root: .root),
                                 deviceLocationService: SearchTestLocationService(),
                                 placeSearchService: service, searchDebounceClock: clock)
        _ = owner.openPlaceSearch()
        let oldGeneration = owner.placeSearchGeneration
        await owner.updatePlaceSearchActivity(isActive: true, expectedGeneration: oldGeneration,
                                             localeIdentifier: SearchFixture.locale)
        let oldSession = service.sessions[0]
        owner.dismissPlaceSearch()
        await oldSession.waitForCancellation()
        let current = owner.openPlaceSearch()
        let generation = owner.placeSearchGeneration
        await owner.updatePlaceSearchActivity(isActive: true, expectedGeneration: generation,
                                             localeIdentifier: SearchFixture.locale)
        let session = service.sessions[1]
        current.updateQuery(SearchFixture.query)
        let query = try #require(current.pendingSearchTask)
        await clock.waitForSleeps(1)
        await owner.updatePlaceSearchActivity(isActive: false, expectedGeneration: oldGeneration,
                                             localeIdentifier: SearchFixture.otherLocale)
        await owner.updatePlaceSearchActivity(isActive: true, expectedGeneration: oldGeneration,
                                             localeIdentifier: SearchFixture.otherLocale)
        // The inherited MainActor task cannot begin before this uninterrupted actor turn cancels it.
        let cancelledPause = Task {
            await owner.updatePlaceSearchActivity(isActive: false, expectedGeneration: generation,
                                                 localeIdentifier: SearchFixture.otherLocale)
        }
        cancelledPause.cancel()
        await cancelledPause.value
        #expect(owner.placeSearch === current)
        #expect(current.query == SearchFixture.query)
        #expect(!query.isCancelled)
        #expect(session.cancellations == 0)
        #expect(service.sessions.count == 2)
        clock.release(0)
        await session.waitForSearches(1)
        #expect(session.searches[0].localeIdentifier == SearchFixture.locale)
        session.completeSearch(0, suggestions: [SearchFixture.suggestion])
        await query.value
        #expect(current.phase == .results)
        #expect(current.suggestions == [SearchFixture.suggestion])
        #expect(session.cancellations == 0)
        owner.dismissPlaceSearch()
        await session.waitForCancellation()
    }

    /// AC-19/58, INV-09: task identity belongs to one presentation, independent of released object addresses.
    @Test func presentationGenerationChangesOnlyForFreshOpeningAfterModelRelease() {
        let owner = MapViewModel(router: Router<MapRoute>(root: .root),
                                 deviceLocationService: SearchTestLocationService())
        let initial = owner.placeSearchGeneration
        #expect(owner.placeSearch == nil)
        var first: MapPlaceSearchModel? = owner.openPlaceSearch()
        weak var weakFirst = first
        let opened = owner.placeSearchGeneration
        #expect(opened > initial)
        #expect(owner.openPlaceSearch() === first)
        #expect(owner.placeSearchGeneration == opened)
        owner.deactivate()
        #expect(owner.placeSearch === first)
        #expect(owner.placeSearchGeneration == opened)
        owner.dismissPlaceSearch()
        first = nil
        #expect(weakFirst == nil)
        let second = owner.openPlaceSearch()
        #expect(owner.placeSearchGeneration > opened)
        let reopened = owner.placeSearchGeneration
        #expect(owner.openPlaceSearch() === second)
        #expect(owner.placeSearchGeneration == reopened)
        owner.dismissPlaceSearch()
    }

    /// AC-18/19, INV-09: discard releases the presentation model during debounce, query or resolution.
    /// Late cancellation-ignoring work cannot repopulate the fresh model or move the existing map.
    @Test(arguments: 0..<3)
    func actualDismissalReleasesModelAndRejectsLateWorkOnFreshReopening(boundary: Int) async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let owner = MapViewModel(router: Router<MapRoute>(root: .root),
                                 deviceLocationService: SearchTestLocationService(),
                                 placeSearchService: service, searchDebounceClock: clock)
        #expect(owner.placeSearch == nil)
        var discarded: MapPlaceSearchModel? = owner.openPlaceSearch()
        weak var weakDiscarded = discarded
        #expect(owner.openPlaceSearch() === discarded)
        await discarded?.start(localeIdentifier: SearchFixture.locale, region: nil)
        let session = try #require(service.sessions.first)
        discarded?.updateQuery(SearchFixture.query)
        let searchTask = try #require(discarded?.pendingSearchTask)
        await clock.waitForSleeps(1)
        var resolutionTask: Task<Void, Never>?
        if boundary > 0 {
            clock.release(0)
            await session.waitForSearches(1)
        }
        if boundary == 2 {
            session.completeSearch(0, suggestions: [SearchFixture.suggestion])
            await searchTask.value
            discarded?.select(SearchFixture.suggestion)
            resolutionTask = try #require(discarded?.pendingResolutionTask)
            await session.waitForResolutions(1)
        }
        let retainedCandidate = try SearchFixture.candidate(id: UUID())
        owner.selectSearchCandidate(retainedCandidate)
        owner.dismissPlaceSearch()
        #expect(owner.placeSearch == nil)
        #expect(discarded?.query == SearchFixture.emptyQuery)
        #expect(discarded?.suggestions.isEmpty == true)
        #expect(discarded?.phase == .idle)
        #expect(discarded?.resolvedCandidate == nil)
        discarded = nil
        #expect(weakDiscarded == nil)
        await session.waitForCancellation()

        let reopened = owner.openPlaceSearch()
        await reopened.start(localeIdentifier: SearchFixture.locale, region: nil)
        let freshSession = service.sessions[1]
        #expect(freshSession.id != session.id)
        #expect(reopened.query == SearchFixture.emptyQuery)
        #expect(reopened.suggestions.isEmpty)
        #expect(reopened.phase == .idle)
        switch boundary {
        case 0: clock.release(0)
        case 1: session.completeSearch(0, suggestions: [SearchFixture.suggestion])
        default:
            session.completeResolution(0, candidate: try SearchFixture.candidate(id: session.resolutions[0].candidateID))
        }
        await searchTask.value
        await resolutionTask?.value
        #expect(reopened.query == SearchFixture.emptyQuery)
        #expect(reopened.resolvedCandidate == nil)
        #expect(reopened.suggestions.isEmpty)
        #expect(owner.placeSearch === reopened)
        #expect(owner.selectedCandidate == retainedCandidate)
        #expect(owner.cameraPosition.region?.center.latitude == retainedCandidate.coordinate.latitude)
        #expect(owner.cameraPosition.region?.center.longitude == retainedCandidate.coordinate.longitude)
        #expect(freshSession.searches.isEmpty && freshSession.resolutions.isEmpty)
        owner.dismissPlaceSearch()
        await freshSession.waitForCancellation()
    }

    /// AC-18/19: dismissal clears failure/retry state and a retained old callback cannot restart Search.
    @Test(arguments: [false, true])
    func dismissedRetainedModelClearsErrorsAndCannotResume(resolutionFailure: Bool) async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let model = MapPlaceSearchModel(service: service, clock: clock)
        await model.start(localeIdentifier: nil, region: nil)
        let session = try #require(service.sessions.first)
        model.updateQuery(SearchFixture.query)
        let search = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(1)
        clock.release(0)
        await session.waitForSearches(1)
        if resolutionFailure {
            session.completeSearch(0, suggestions: [SearchFixture.suggestion])
            await search.value
            model.select(SearchFixture.suggestion)
            let resolution = try #require(model.pendingResolutionTask)
            await session.waitForResolutions(1)
            session.failResolution(0, error: .notFound)
            await resolution.value
            #expect(model.resolutionError == .notFound)
        } else {
            session.failSearch(0, error: .networkUnavailable)
            await search.value
            #expect(model.phase == .failed(.networkUnavailable))
        }
        model.dismiss()
        model.dismiss()
        await session.waitForCancellation()
        model.updateQuery(SearchFixture.otherQuery)
        model.updateLocale(SearchFixture.otherLocale)
        model.select(SearchFixture.suggestion)
        model.retry()
        await model.start(localeIdentifier: SearchFixture.otherLocale, region: nil)
        #expect(model.query == SearchFixture.emptyQuery)
        #expect(model.phase == .idle)
        #expect(model.suggestions.isEmpty)
        #expect(model.resolutionError == nil)
        #expect(model.resolvingSuggestionID == nil)
        #expect(model.resolvedCandidate == nil)
        #expect(model.pendingSearchTask == nil && model.pendingResolutionTask == nil)
        #expect(service.sessions.count == 1)
        #expect(session.cancellations == 1)
    }

    /// AC-19/58, INV-09: a scene/tab pause keeps the open model/input, unlike actual dismissal.
    @Test func mapDeactivationPausesOwnedSearchWithoutDiscardingQuery() async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let owner = MapViewModel(router: Router<MapRoute>(root: .root),
                                 deviceLocationService: SearchTestLocationService(),
                                 placeSearchService: service, searchDebounceClock: clock)
        let search = owner.openPlaceSearch()
        await search.start(localeIdentifier: nil, region: nil)
        let session = service.sessions[0]
        search.updateQuery(SearchFixture.query)
        let task = try #require(search.pendingSearchTask)
        await clock.waitForSleeps(1)
        owner.deactivate()
        await session.waitForCancellation()
        clock.release(0)
        await task.value
        #expect(owner.placeSearch === search)
        #expect(owner.openPlaceSearch() === search)
        #expect(search.query == SearchFixture.query)
        owner.dismissPlaceSearch()
        #expect(owner.placeSearch == nil)
    }

    /// AC-18/19, INV-09: later candidate selection supersedes an already pending explicit recenter.
    @Test func pendingExplicitRecenterCannotReplaceSelectedCandidateCamera() async throws {
        let service = SearchPendingLocationService()
        let model = MapViewModel(router: Router<MapRoute>(root: .root), deviceLocationService: service)
        _ = await model.activate()
        service.status = .authorizedWhenInUse
        let recenter = Task { await model.recenter() }
        await service.waitForPosition()
        #expect(model.isLocating)
        let candidate = try SearchFixture.candidate(id: UUID())
        model.selectSearchCandidate(candidate)
        let selectedFocus = model.locationFocus
        let position = try DevicePosition(coordinate: Coordinate(latitude: 40, longitude: 80),
                                          timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
                                          horizontalAccuracyMetres: 5,
                                          authorization: await service.authorization())
        service.complete(position)
        #expect(await recenter.value == nil)
        #expect(model.selectedCandidate == candidate)
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(model.visiblePlace?.coordinate == candidate.coordinate)
        #expect(model.cameraPosition.region?.center.latitude == candidate.coordinate.latitude)
        #expect(model.cameraPosition.region?.center.longitude == candidate.coordinate.longitude)
        #expect(model.locationFocus == selectedFocus)
        #expect(!model.isLocating)
    }

    /// AC-19: exactly one second of injected time, restarting on each input edit.
    @Test func debounceRestartsAndOnlyLatestTrimmedQueryStarts() async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let model = MapPlaceSearchModel(service: service, clock: clock)
        #expect(service.sessions.isEmpty)
        await model.start(localeIdentifier: SearchFixture.locale, region: nil)
        let session = try #require(service.sessions.first)
        model.updateQuery(SearchFixture.query)
        let oldTask = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(1)
        #expect(clock.durations == [.seconds(1)])
        #expect(session.searches.isEmpty)
        #expect(model.phase == .debouncing)
        model.updateQuery(SearchFixture.paddedOtherQuery)
        let task = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(2)
        #expect(oldTask.isCancelled)
        clock.release(0)
        await oldTask.value
        #expect(session.searches.isEmpty)
        clock.release(1)
        await session.waitForSearches(1)
        #expect(clock.durations == [.seconds(1), .seconds(1)])
        #expect(session.searches.first?.query == SearchFixture.otherQuery)
        #expect(model.phase == .loading)
        session.completeSearch(0, suggestions: [SearchFixture.otherSuggestion])
        await task.value
        #expect(model.suggestions == [SearchFixture.otherSuggestion])
        #expect(model.phase == .results)
        model.stop()
        await session.waitForCancellation()
    }

    /// AC-19: whitespace clears immediately and cancels pending debounce without a provider call.
    @Test func clearingInputCancelsPendingDebounceAndClearsResultsImmediately() async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let model = MapPlaceSearchModel(service: service, clock: clock)
        await model.start(localeIdentifier: nil, region: nil)
        let session = try #require(service.sessions.first)
        model.updateQuery(SearchFixture.query)
        let task = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(1)
        model.updateQuery(SearchFixture.blank)
        #expect(task.isCancelled)
        #expect(model.phase == .idle)
        #expect(model.suggestions.isEmpty)
        #expect(model.resolvedCandidate == nil)
        clock.release(0)
        await task.value
        #expect(session.searches.isEmpty)
        model.stop()
        await session.waitForCancellation()
    }

    /// AC-19, D-03: stale query or locale responses cannot replace current results even ignoring cancellation.
    @Test(arguments: [false, true])
    func olderQueryOrLocaleCompletionCannotReplaceCurrentResults(changeLocale: Bool) async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let model = MapPlaceSearchModel(service: service, clock: clock)
        await model.start(localeIdentifier: SearchFixture.locale, region: nil)
        let session = try #require(service.sessions.first)
        model.updateQuery(SearchFixture.query)
        let oldTask = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(1)
        clock.release(0)
        await session.waitForSearches(1)
        if changeLocale { model.updateLocale(SearchFixture.otherLocale) }
        else { model.updateQuery(SearchFixture.otherQuery) }
        let currentTask = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(2)
        clock.release(1)
        await session.waitForSearches(2)
        #expect(session.searches[1].localeIdentifier == (changeLocale ? SearchFixture.otherLocale : SearchFixture.locale))
        session.completeSearch(1, suggestions: [SearchFixture.otherSuggestion])
        await currentTask.value
        session.completeSearch(0, suggestions: [SearchFixture.suggestion])
        await oldTask.value
        #expect(model.suggestions == [SearchFixture.otherSuggestion])
        #expect(model.phase == .results)
        model.stop()
        await session.waitForCancellation()
    }

    /// AC-18/19: loading, failure, retry and no-result states retain the user's query.
    @Test func providerFailureRetryAndEmptyResultsKeepQuery() async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let model = MapPlaceSearchModel(service: service, clock: clock)
        await model.start(localeIdentifier: nil, region: nil)
        let session = try #require(service.sessions.first)
        model.updateQuery(SearchFixture.query)
        let first = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(1)
        clock.release(0)
        await session.waitForSearches(1)
        session.failSearch(0, error: .networkUnavailable)
        await first.value
        #expect(model.phase == .failed(.networkUnavailable))
        #expect(model.query == SearchFixture.query)
        model.retry()
        let retry = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(2)
        clock.release(1)
        await session.waitForSearches(2)
        session.completeSearch(1, suggestions: [])
        await retry.value
        #expect(model.phase == .empty)
        #expect(model.query == SearchFixture.query)
        #expect(model.suggestions.isEmpty)
        model.stop()
        await session.waitForCancellation()
    }

    /// AC-18/19: resolve exactly the selected row; failures remain retryable and successful identity is stable.
    @Test func exactSuggestionResolutionCanRetryWithoutLosingQuery() async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let model = MapPlaceSearchModel(service: service, clock: clock)
        await model.start(localeIdentifier: nil, region: nil)
        let session = try #require(service.sessions.first)
        model.updateQuery(SearchFixture.query)
        let search = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(1)
        clock.release(0)
        await session.waitForSearches(1)
        session.completeSearch(0, suggestions: [SearchFixture.otherSuggestion, SearchFixture.suggestion])
        await search.value
        model.select(SearchFixture.suggestion)
        let resolution = try #require(model.pendingResolutionTask)
        await session.waitForResolutions(1)
        #expect(session.resolutions[0].suggestion == SearchFixture.suggestion)
        #expect(session.resolutions[0].searchRequest == session.searches[0])
        session.failResolution(0, error: .notFound)
        await resolution.value
        #expect(model.resolutionError == .notFound)
        #expect(model.resolvedCandidate == nil)
        #expect(model.query == SearchFixture.query)
        #expect(model.suggestions.count == 2)
        model.retry()
        let retry = try #require(model.pendingResolutionTask)
        await session.waitForResolutions(2)
        let candidate = try SearchFixture.candidate(id: session.resolutions[1].candidateID)
        session.completeResolution(1, candidate: candidate)
        await retry.value
        #expect(model.resolutionError == nil)
        #expect(model.resolvingSuggestionID == nil)
        #expect(model.resolvedCandidate == candidate)
        #expect(session.searches.count == 1)
        model.stop()
        await session.waitForCancellation()
    }

    /// AC-19: query change, locale change, clearing or dismissal rejects a late selected result.
    @Test(arguments: 0..<4)
    func obsoleteResolutionCannotPublishCandidate(change: Int) async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let model = MapPlaceSearchModel(service: service, clock: clock)
        await model.start(localeIdentifier: SearchFixture.locale, region: nil)
        let session = try #require(service.sessions.first)
        model.updateQuery(SearchFixture.query)
        let search = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(1)
        clock.release(0)
        await session.waitForSearches(1)
        session.completeSearch(0, suggestions: [SearchFixture.suggestion])
        await search.value
        model.select(SearchFixture.suggestion)
        let oldResolution = try #require(model.pendingResolutionTask)
        await session.waitForResolutions(1)
        switch change {
        case 0: model.updateQuery(SearchFixture.otherQuery)
        case 1: model.updateLocale(SearchFixture.otherLocale)
        case 2: model.updateQuery(SearchFixture.blank)
        default: model.stop()
        }
        let replacement = model.pendingSearchTask
        session.completeResolution(0, candidate: try SearchFixture.candidate(id: session.resolutions[0].candidateID))
        await oldResolution.value
        #expect(model.resolvedCandidate == nil)
        #expect(model.resolutionError == nil)
        #expect(model.resolvingSuggestionID == nil)
        if let replacement {
            await clock.waitForSleeps(2)
            model.stop()
            clock.release(1)
            await replacement.value
        } else { model.stop() }
        await session.waitForCancellation()
    }

    /// AC-19/58, INV-09: lifecycle restart retains input but uses a new session, ignoring old completion.
    @Test func stopAndRestartRetainsQueryAndRejectsPreviousSession() async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let model = MapPlaceSearchModel(service: service, clock: clock)
        await model.start(localeIdentifier: nil, region: nil)
        let oldSession = try #require(service.sessions.first)
        model.updateQuery(SearchFixture.query)
        let oldTask = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(1)
        clock.release(0)
        await oldSession.waitForSearches(1)
        model.stop()
        await oldSession.waitForCancellation()
        #expect(model.query == SearchFixture.query)
        await model.start(localeIdentifier: nil, region: nil)
        let current = try #require(model.pendingSearchTask)
        let currentSession = service.sessions[1]
        #expect(currentSession.id != oldSession.id)
        await clock.waitForSleeps(2)
        clock.release(1)
        await currentSession.waitForSearches(1)
        currentSession.completeSearch(0, suggestions: [SearchFixture.otherSuggestion])
        await current.value
        oldSession.completeSearch(0, suggestions: [SearchFixture.suggestion])
        await oldTask.value
        #expect(model.suggestions == [SearchFixture.otherSuggestion])
        #expect(currentSession.cancellations == 0)
        model.stop()
        await currentSession.waitForCancellation()
    }

    /// AC-19, INV-09, D-03: two scene-owned models never exchange results or cancellation.
    @Test func simultaneousModelsHaveIndependentSessionsAndResults() async throws {
        let service = SearchTestService()
        let firstClock = SearchTestClock()
        let secondClock = SearchTestClock()
        let first = MapPlaceSearchModel(service: service, clock: firstClock)
        let second = MapPlaceSearchModel(service: service, clock: secondClock)
        await first.start(localeIdentifier: nil, region: nil)
        await second.start(localeIdentifier: nil, region: nil)
        let firstSession = service.sessions[0]
        let secondSession = service.sessions[1]
        #expect(firstSession.id != secondSession.id)
        first.updateQuery(SearchFixture.query)
        second.updateQuery(SearchFixture.otherQuery)
        let firstTask = try #require(first.pendingSearchTask)
        let secondTask = try #require(second.pendingSearchTask)
        await firstClock.waitForSleeps(1)
        await secondClock.waitForSleeps(1)
        firstClock.release(0)
        secondClock.release(0)
        await firstSession.waitForSearches(1)
        await secondSession.waitForSearches(1)
        secondSession.completeSearch(0, suggestions: [SearchFixture.otherSuggestion])
        await secondTask.value
        firstSession.completeSearch(0, suggestions: [SearchFixture.suggestion])
        await firstTask.value
        #expect(first.suggestions == [SearchFixture.suggestion])
        #expect(second.suggestions == [SearchFixture.otherSuggestion])
        first.stop()
        await firstSession.waitForCancellation()
        #expect(secondSession.cancellations == 0)
        #expect(second.suggestions == [SearchFixture.otherSuggestion])
        second.stop()
        await secondSession.waitForCancellation()
    }

    /// AC-19, D-03: bias is captured when debounce ends; map movement alone starts no new search.
    @Test func regionIsCapturedAfterDebounceWithoutRepeatingSearchOnPan() async throws {
        let service = SearchTestService()
        let clock = SearchTestClock()
        let model = MapPlaceSearchModel(service: service, clock: clock)
        let firstRegion = try PlaceSearchRegion(center: Coordinate(latitude: 10, longitude: 20),
                                              latitudeDelta: 0.2, longitudeDelta: 0.3)
        let secondRegion = try PlaceSearchRegion(center: Coordinate(latitude: 40, longitude: 80),
                                               latitudeDelta: 0.4, longitudeDelta: 0.5)
        await model.start(localeIdentifier: nil, region: firstRegion)
        let session = try #require(service.sessions.first)
        model.updateQuery(SearchFixture.query)
        let task = try #require(model.pendingSearchTask)
        await clock.waitForSleeps(1)
        model.updateRegion(secondRegion)
        #expect(clock.durations.count == 1)
        clock.release(0)
        await session.waitForSearches(1)
        #expect(session.searches[0].region == secondRegion)
        session.completeSearch(0, suggestions: [SearchFixture.suggestion])
        await task.value
        model.updateRegion(firstRegion)
        #expect(session.searches.count == 1)
        #expect(model.phase == .results)
        #expect(model.suggestions == [SearchFixture.suggestion])
        model.stop()
        await session.waitForCancellation()
    }

    /// AC-18, INV-09: exact candidate metadata/identity and useful map zoom survive focus.
    @Test func selectedCandidatePreservesIdentityMetadataAndCameraZoom() throws {
        let model = MapViewModel(router: Router<MapRoute>(root: .root),
                                 deviceLocationService: SearchTestLocationService())
        #expect(model.placeSearch == nil)
        let retainedSearch = model.openPlaceSearch()
        model.cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: 80),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.3)))
        let candidate = try SearchFixture.candidate(id: UUID())
        model.selectSearchCandidate(candidate)

        #expect(model.selectedCandidate == candidate)
        #expect(model.selectedCandidate?.name == SearchFixture.name)
        #expect(model.selectedCandidate?.address == SearchFixture.address)
        #expect(model.selectedCandidate?.placeIdentity?.allIDs == [SearchFixture.primaryID, SearchFixture.alternateID])
        #expect(model.cameraPosition.region?.center.latitude == candidate.coordinate.latitude)
        #expect(model.cameraPosition.region?.center.longitude == candidate.coordinate.longitude)
        #expect(model.cameraPosition.region?.span.latitudeDelta == 0.2)
        #expect(model.cameraPosition.region?.span.longitudeDelta == 0.3)
        #expect(model.placeSearch === retainedSearch)
        model.dismissPlaceSearch()
        #expect(model.placeSearch == nil)
        let reopened = model.openPlaceSearch()
        #expect(reopened !== retainedSearch)
        #expect(reopened.query == SearchFixture.emptyQuery)
        #expect(model.selectedCandidate == candidate)
        #expect(model.cameraPosition.region?.center.latitude == candidate.coordinate.latitude)
        #expect(model.cameraPosition.region?.center.longitude == candidate.coordinate.longitude)
    }

    /// AC-58, INV-09, D-04/17: repeated presentation actions use one scene owner and preserve routes.
    /// Actual compact/regular rendering, input and resize evidence belongs to UI/device QA.
    @Test func searchPresentationIsIdempotentAndSceneLocalWithoutChangingPaths() {
        let first = SceneCoordinator()
        let second = SceneCoordinator()
        let collectionID = UUID()
        first.homeRouter.push(.collection(id: collectionID))
        let homePaths = first.homeRouter.paths
        let mapPaths = first.mapRouter.paths
        for _ in 0..<4 {
            first.openMapSearch()
            first.openMapSearch()
            #expect(first.mapPresentation == .search)
            #expect(second.mapPresentation == .none)
            #expect(first.homeRouter.paths == homePaths)
            #expect(first.mapRouter.paths == mapPaths)
        }
        first.closeMapSearch()
        first.closeMapSearch()
        #expect(first.mapPresentation == .none)
        #expect(first.homeRouter.paths == homePaths)
        #expect(first.selectedTab == .home)
        #expect(second.homeRouter.paths.isEmpty)
    }

    /// AC-18/24/57-60, D-04, INV-09: the one scene-owned sheet slot is empty
    /// during a detail-to-Search transition and advances only on dismissal ack.
    @Test func searchFromDetailWaitsForDismissalAcknowledgement() {
        let scene = SceneCoordinator()
        scene.selectedTab = .map
        scene.openMapDetail()
        #expect(scene.presentedMapSheet == .detail)

        scene.openMapSearch()
        scene.openMapSearch()
        #expect(scene.presentedMapSheet == nil)
        #expect(scene.mapPresentation == .none)
        scene.mapPresentationDidDismiss()
        #expect(scene.presentedMapSheet == .search)
        scene.mapPresentationDidDismiss()
        #expect(scene.presentedMapSheet == .search)
    }

    /// AC-18/24/58, D-04: cancelling a queued Search leaves the selected card
    /// and camera intact and cannot reopen a sheet after a late dismissal ack.
    @Test func cancellingQueuedSearchPreservesCandidateSelection() throws {
        let scene = SceneCoordinator()
        scene.selectedTab = .map
        let model = MapViewModel(router: scene.mapRouter,
                                 deviceLocationService: SearchTestLocationService())
        let candidate = try SearchFixture.candidate(id: UUID())
        model.selectSearchCandidate(candidate)
        model.showDetails()
        let camera = model.cameraPosition.region
        scene.openMapDetail()
        scene.openMapSearch()
        #expect(scene.presentedMapSheet == nil)
        scene.closeMapSearch()
        scene.mapPresentationDidDismiss()
        scene.mapPresentationDidDismiss()

        #expect(scene.presentedMapSheet == nil)
        #expect(model.selectedCandidate == candidate)
        #expect(model.visiblePlace?.id == .searchCandidate(candidate.id))
        #expect(model.selectedDetail?.id == .searchCandidate(candidate.id))
        #expect(model.cameraPosition.region?.center.latitude == camera?.center.latitude)
        #expect(model.cameraPosition.region?.center.longitude == camera?.center.longitude)
    }

    /// AC-18/19/24, D-04: a resolved Search candidate replaces the prior
    /// detail selection, and repeated close/ack cannot resurrect Search.
    @Test func successfulCandidateReplacementClosesOneSearchSheet() throws {
        let scene = SceneCoordinator()
        scene.selectedTab = .map
        let model = MapViewModel(router: scene.mapRouter,
                                 deviceLocationService: SearchTestLocationService())
        let previous = try SearchFixture.candidate(id: UUID())
        model.selectSearchCandidate(previous)
        model.showDetails()
        scene.openMapDetail()
        scene.openMapSearch()
        scene.mapPresentationDidDismiss()
        #expect(scene.presentedMapSheet == .search)

        let replacement = try SearchFixture.candidate(id: UUID())
        model.selectSearchCandidate(replacement)
        scene.closeMapSearch()
        scene.closeMapSearch()
        scene.mapPresentationDidDismiss()
        scene.mapPresentationDidDismiss()

        #expect(scene.presentedMapSheet == nil)
        #expect(model.selectedDetail == nil)
        #expect(model.selectedCandidate?.id == replacement.id)
        #expect(model.visiblePlace?.id == .searchCandidate(replacement.id))
        #expect(model.cameraPosition.region?.center.latitude == replacement.coordinate.latitude)
        #expect(model.cameraPosition.region?.center.longitude == replacement.coordinate.longitude)
    }
}
