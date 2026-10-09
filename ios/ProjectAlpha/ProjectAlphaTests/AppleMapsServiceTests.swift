//
//  AppleMapsServiceTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import CoreLocation
import Foundation
import MapKit
import Testing
@testable import ProjectAlpha

private enum MapsFixture {
    static let query = "Library"
    static let otherQuery = "Museum"
    static let blankQuery = " \n "
    static let locale = "vi"
    static let otherLocale = "en"
    static let suggestionID = "suggestion-one"
    static let name = "Central library"
    static let address = "Example street"
    static let primary = "Opaque:Primary"
    static let alias = "Opaque:Alias"
    static let newPrimary = "New:Primary"
    static let newAlias = "New:Alias"
    static let time = Date(timeIntervalSinceReferenceDate: 1_000)
    static func coordinate(_ latitude: Double = 10) throws -> Coordinate {
        try Coordinate(latitude: latitude, longitude: 20)
    }
    static func search(id: UUID, generation: UInt64 = 1, query: String = query,
                       region: PlaceSearchRegion? = nil, locale: String = locale) -> PlaceSearchRequest {
        PlaceSearchRequest(sessionID: id, generation: generation, query: query, region: region, localeIdentifier: locale)
    }
    static var suggestion: PlaceSuggestion { PlaceSuggestion(id: suggestionID, title: name, subtitle: address) }
    static func candidate(id: UUID) throws -> PlaceCandidate {
        PlaceCandidate(id: id, source: .appleMaps, placeIdentity: try PlaceIdentity(primaryID: primary, alternateIDs: [alias]),
                       name: name, address: address, category: nil, coordinate: try coordinate())
    }
    static func route(mode: RouteMode) throws -> RouteRequest {
        RouteRequest(origin: RouteEndpoint(coordinate: try coordinate(), savedLocationID: nil, placeIdentity: nil),
                     destination: RouteEndpoint(coordinate: try coordinate(11), savedLocationID: nil, placeIdentity: nil),
                     mode: mode, generation: 3)
    }
}

/// Each operation has a start handshake and manually delivered completions, including late callbacks.
@MainActor
private final class ControlledMapOperation<Value: Sendable> {
    private(set) var cancellations = 0
    private var completion: AppleServiceOperation<Value>.Completion?
    private var startWaiter: CheckedContinuation<Void, Never>?
    func operation() -> AppleServiceOperation<Value> {
        AppleServiceOperation { [self] callback in
            completion = callback
            startWaiter?.resume()
            startWaiter = nil
        } cancel: { [self] in cancellations += 1 }
    }
    func waitForStart() async {
        if completion != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func complete(_ result: Result<Value, PlaceServiceError>) { completion?(result) }
}

@MainActor
private final class SuspendedProviderWork {
    private var continuation: CheckedContinuation<Int, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    func value() async -> Int {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }
    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func complete() {
        continuation?.resume(returning: 7)
        continuation = nil
    }
}

@MainActor
private final class ControlledSearchDriver: ApplePlaceSearchDriver {
    let suggestionsOperation = ControlledMapOperation<PlaceSuggestions>()
    let resolutionOperation = ControlledMapOperation<PlaceSuggestionResolution>()
    private(set) var request: PlaceSearchRequest?
    private(set) var resolutionRequest: PlaceSuggestionResolutionRequest?
    private(set) var cancellations = 0
    func suggestions(_ request: PlaceSearchRequest) -> AppleServiceOperation<PlaceSuggestions> {
        self.request = request
        return suggestionsOperation.operation()
    }
    func resolve(_ request: PlaceSuggestionResolutionRequest) -> AppleServiceOperation<PlaceSuggestionResolution> {
        resolutionRequest = request
        return resolutionOperation.operation()
    }
    func cancel() { cancellations += 1 }
}

@MainActor
private final class ControlledMapsDriver: AppleMapsDriver {
    let reverse = ControlledMapOperation<ReverseGeocodedAddress>()
    let identity = ControlledMapOperation<PlaceIdentityResolution>()
    let route = ControlledMapOperation<RouteEstimate>()
    private(set) var reverseRequest: ReverseGeocodeRequest?
    private(set) var identityRequest: PlaceIdentityResolutionRequest?
    private(set) var routeRequest: RouteRequest?
    func reverseGeocode(_ request: ReverseGeocodeRequest) -> AppleServiceOperation<ReverseGeocodedAddress> {
        reverseRequest = request
        return reverse.operation()
    }
    func resolve(_ request: PlaceIdentityResolutionRequest) -> AppleServiceOperation<PlaceIdentityResolution> {
        identityRequest = request
        return identity.operation()
    }
    func estimateRoute(_ request: RouteRequest) -> AppleServiceOperation<RouteEstimate> {
        routeRequest = request
        return route.operation()
    }
}

@MainActor
private final class CompositionLocationService: DeviceLocationService {
    private(set) var requests = 0
    @MainActor func authorization() async -> LocationAuthorization {
        LocationAuthorization(status: .denied, accuracy: .reduced, servicesEnabled: true)
    }
    @MainActor func currentPosition() async throws(LocationServiceError) -> DevicePosition {
        requests += 1
        throw .permissionDenied
    }
}

@MainActor
struct AppleMapsServiceTests {
    /// D-01/03, AC-19/37: composition retains one supplied broker while sessions stay destination-owned.
    @Test func appCompositionRetainsOverridesWithoutStartingServices() async {
        let location = CompositionLocationService()
        let driver = ControlledMapsDriver()
        var driverCreations = 0
        let maps = AppleMapsService(driver: driver, makeSearchDriver: {
            driverCreations += 1
            return ControlledSearchDriver()
        })
        let app = AppContainer(preferenceStore: PreviewPreferenceStore(),
                               deviceLocationServiceOverride: location,
                               placeSearchServiceOverride: maps,
                               placeIdentityResolutionServiceOverride: maps,
                               reverseGeocodingServiceOverride: maps,
                               routeEstimationServiceOverride: maps)
        let identityMatches1 = (app.deviceLocationService as AnyObject) === location
        #expect(identityMatches1)
        let identityMatches2 = (app.mapContainer.deviceLocationService as AnyObject) === location
        #expect(identityMatches2)
        let identityMatches3 = (app.placeSearchService as AnyObject) === maps
        #expect(identityMatches3)
        let identityMatches4 = (app.placeIdentityResolutionService as AnyObject) === maps
        #expect(identityMatches4)
        let identityMatches5 = (app.reverseGeocodingService as AnyObject) === maps
        #expect(identityMatches5)
        let identityMatches6 = (app.routeEstimationService as AnyObject) === maps
        #expect(identityMatches6)
        let firstID = UUID()
        let secondID = UUID()
        let first = await app.mapContainer.makePlaceSearchSession(id: firstID)
        let second = await app.mapContainer.makePlaceSearchSession(id: secondID)
        #expect(first.id == firstID && second.id == secondID)
        let identityMatches7 = (first as AnyObject) !== (second as AnyObject)
        #expect(identityMatches7)
        #expect(driverCreations == 0 && location.requests == 0)
        #expect(driver.reverseRequest == nil && driver.identityRequest == nil && driver.routeRequest == nil)
        await first.cancel()
        await second.cancel()
    }

    /// AC-19: separate sessions retain their own requests/results even when completion order reverses.
    @Test func concurrentSearchSessionsRemainIndependent() async throws {
        let firstDriver = ControlledSearchDriver()
        let secondDriver = ControlledSearchDriver()
        var drivers = [firstDriver, secondDriver]
        let service = AppleMapsService(driver: ControlledMapsDriver(), makeSearchDriver: { drivers.removeFirst() })
        let first = await service.makeSearchSession(id: UUID())
        let second = await service.makeSearchSession(id: UUID())
        #expect(first.id != second.id)
        #expect(drivers.count == 2) // Session creation starts no provider work.
        let firstRequest = MapsFixture.search(id: first.id)
        let secondRequest = MapsFixture.search(id: second.id, query: MapsFixture.otherQuery)
        let firstTask = Task { try await first.suggestions(for: firstRequest) }
        await firstDriver.suggestionsOperation.waitForStart()
        let secondTask = Task { try await second.suggestions(for: secondRequest) }
        await secondDriver.suggestionsOperation.waitForStart()
        let secondResult = PlaceSuggestions(request: secondRequest, suggestions: [])
        secondDriver.suggestionsOperation.complete(.success(secondResult))
        #expect(try await secondTask.value == secondResult)
        let firstResult = PlaceSuggestions(request: firstRequest, suggestions: [MapsFixture.suggestion])
        firstDriver.suggestionsOperation.complete(.success(firstResult))
        #expect(try await firstTask.value == firstResult)
        await first.cancel()
        #expect(secondDriver.cancellations == 0)
        await second.cancel()
    }

    /// AC-19: changes in query, region, locale or generation invalidate old work, including late callbacks.
    @Test func changedRequestRejectsOldCompletion() async throws {
        for variant in 0..<4 {
            let oldDriver = ControlledSearchDriver()
            let newDriver = ControlledSearchDriver()
            var drivers = [oldDriver, newDriver]
            let session = ApplePlaceSearchSession(id: UUID(), makeDriver: { drivers.removeFirst() })
            let oldRequest = MapsFixture.search(id: session.id)
            let region = try PlaceSearchRegion(center: MapsFixture.coordinate(), latitudeDelta: 1, longitudeDelta: 1)
            let newRequest = MapsFixture.search(id: session.id, generation: variant == 3 ? 2 : 1,
                                               query: variant == 0 ? MapsFixture.otherQuery : MapsFixture.query,
                                               region: variant == 1 ? region : nil,
                                               locale: variant == 2 ? MapsFixture.otherLocale : MapsFixture.locale)
            let oldTask = Task { try await session.suggestions(for: oldRequest) }
            await oldDriver.suggestionsOperation.waitForStart()
            let newTask = Task { try await session.suggestions(for: newRequest) }
            await newDriver.suggestionsOperation.waitForStart()
            await #expect(throws: PlaceServiceError.superseded) { try await oldTask.value }
            oldDriver.suggestionsOperation.complete(.success(PlaceSuggestions(request: oldRequest, suggestions: [MapsFixture.suggestion])))
            let current = PlaceSuggestions(request: newRequest, suggestions: [])
            newDriver.suggestionsOperation.complete(.success(current))
            #expect(try await newTask.value == current)
            #expect(newDriver.request == newRequest)
            #expect(oldDriver.suggestionsOperation.cancellations == 1)
            await session.cancel()
        }
    }

    /// AC-19: empty query clears active work; old suggestions cannot resolve in a newer request.
    @Test func emptyQueryClearsAndStaleSuggestionCannotResolve() async throws {
        let driver = ControlledSearchDriver()
        let session = ApplePlaceSearchSession(id: UUID(), makeDriver: { driver })
        let request = MapsFixture.search(id: session.id)
        let pending = Task { try await session.suggestions(for: request) }
        await driver.suggestionsOperation.waitForStart()
        let empty = MapsFixture.search(id: session.id, generation: 2, query: MapsFixture.blankQuery)
        let result = try await session.suggestions(for: empty)
        #expect(result.request == empty && result.suggestions.isEmpty)
        await #expect(throws: PlaceServiceError.superseded) { try await pending.value }
        let resolution = PlaceSuggestionResolutionRequest(searchRequest: request, generation: 1,
                                                          suggestion: MapsFixture.suggestion, candidateID: UUID())
        await #expect(throws: PlaceServiceError.superseded) { try await session.resolve(resolution) }
        #expect(driver.resolutionRequest == nil)
        await session.cancel()
    }

    /// AC-19, INV-02: resolution yields a stable candidate only for this session's active suggestion request.
    @Test func resolutionPreservesCandidateAndSessionCancellationIsTerminal() async throws {
        let driver = ControlledSearchDriver()
        let session = ApplePlaceSearchSession(id: UUID(), makeDriver: { driver })
        let request = MapsFixture.search(id: session.id)
        let suggestions = Task { try await session.suggestions(for: request) }
        await driver.suggestionsOperation.waitForStart()
        driver.suggestionsOperation.complete(.success(PlaceSuggestions(request: request, suggestions: [MapsFixture.suggestion])))
        _ = try await suggestions.value
        let resolutionRequest = PlaceSuggestionResolutionRequest(searchRequest: request, generation: 2,
                                                                 suggestion: MapsFixture.suggestion, candidateID: UUID())
        let resolution = Task { try await session.resolve(resolutionRequest) }
        await driver.resolutionOperation.waitForStart()
        let result = PlaceSuggestionResolution(request: resolutionRequest,
                                              candidate: try MapsFixture.candidate(id: resolutionRequest.candidateID))
        driver.resolutionOperation.complete(.success(result))
        #expect(try await resolution.value == result)
        #expect(result.candidate.id == resolutionRequest.candidateID)
        await session.cancel()
        await session.cancel()
        #expect(driver.cancellations == 1)
        await #expect(throws: PlaceServiceError.sessionEnded) { try await session.suggestions(for: request) }
        await #expect(throws: PlaceServiceError.sessionEnded) { try await session.resolve(resolutionRequest) }
    }

    /// AC-19: a late older selection request cannot cancel or replace an active newer resolution.
    @Test func olderResolutionGenerationCannotSupersedeNewSelection() async throws {
        let driver = ControlledSearchDriver()
        let session = ApplePlaceSearchSession(id: UUID(), makeDriver: { driver })
        let search = MapsFixture.search(id: session.id)
        let task = Task { try await session.suggestions(for: search) }
        await driver.suggestionsOperation.waitForStart()
        driver.suggestionsOperation.complete(.success(PlaceSuggestions(request: search, suggestions: [MapsFixture.suggestion])))
        _ = try await task.value
        let newer = PlaceSuggestionResolutionRequest(searchRequest: search, generation: 2,
                                                    suggestion: MapsFixture.suggestion, candidateID: UUID())
        let older = PlaceSuggestionResolutionRequest(searchRequest: search, generation: 1,
                                                    suggestion: MapsFixture.suggestion, candidateID: UUID())
        let pending = Task { try await session.resolve(newer) }
        await driver.resolutionOperation.waitForStart()
        await #expect(throws: PlaceServiceError.superseded) { try await session.resolve(older) }
        #expect(driver.resolutionOperation.cancellations == 0)
        let result = PlaceSuggestionResolution(request: newer, candidate: try MapsFixture.candidate(id: newer.candidateID))
        driver.resolutionOperation.complete(.success(result))
        #expect(try await pending.value == result)
        await session.cancel()
    }

    /// AC-19/54: cancelled asynchronous provider work must never start or publish a value.
    @Test func asynchronousOperationCancelledBeforeStartDoesNoProviderWork() async {
        var starts = 0
        var cancellations = 0
        let operation = AppleServiceOperation<Int>(asyncRequest: { starts += 1; return 7 },
                                                  cancel: { cancellations += 1 })
        operation.cancel()
        operation.cancel()
        await #expect(throws: PlaceServiceError.cancelled) { try await operation.value() }
        #expect(starts == 0 && cancellations == 1)
    }

    /// AC-19/54: cancelling after enqueue, before the worker runs, prevents SDK startup.
    /// Await the owned worker's termination so the assertion also detects an uncancelled late start.
    @Test func queuedAsynchronousOperationCancellationPreventsProviderStart() async throws {
        var starts = 0
        var cancellations = 0
        var worker: Task<Void, Never>?
        weak var queued: AppleServiceOperation<Int>?
        let operation = AppleServiceOperation<Int>(asyncRequest: { starts += 1; return 7 },
                                                  onRequestEnqueued: { task in
                                                      worker = task
                                                      queued?.cancel()
                                                  },
                                                  cancel: { cancellations += 1 })
        queued = operation
        await #expect(throws: PlaceServiceError.cancelled) { try await operation.value() }
        let ownedWorker = try #require(worker)
        await ownedWorker.value
        #expect(starts == 0 && cancellations == 1)
    }

    /// AC-19/54: cancellation releases a consumer while suspended async SDK work finishes late.
    @Test func asynchronousOperationCancellationIgnoresLateCompletion() async {
        let provider = SuspendedProviderWork()
        var cancellations = 0
        let operation = AppleServiceOperation<Int>(asyncRequest: { await provider.value() },
                                                  cancel: { cancellations += 1 })
        let task = Task { try await operation.value() }
        await provider.waitForStart()
        task.cancel()
        await #expect(throws: PlaceServiceError.cancelled) { try await task.value }
        provider.complete()
        operation.cancel()
        #expect(cancellations == 1)
    }

    /// AC-19: session shutdown releases pending provider operations and ignores callbacks afterward.
    @Test func sessionEndAndTaskCancellationReleasePendingSearch() async throws {
        for endSession in [true, false] {
            let driver = ControlledSearchDriver()
            let session = ApplePlaceSearchSession(id: UUID(), makeDriver: { driver })
            let request = MapsFixture.search(id: session.id)
            let task = Task { try await session.suggestions(for: request) }
            await driver.suggestionsOperation.waitForStart()
            if endSession { await session.cancel() } else { task.cancel() }
            await #expect(throws: endSession ? PlaceServiceError.sessionEnded : .cancelled) { try await task.value }
            #expect(driver.suggestionsOperation.cancellations == 1)
            driver.suggestionsOperation.complete(.success(PlaceSuggestions(request: request, suggestions: [MapsFixture.suggestion])))
            await session.cancel()
        }
    }

    /// AC-20/21: reverse address is optional enrichment of the precise original point; errors remain typed.
    @Test func reverseGeocodingPreservesCoordinateAndAllowsMissingAddress() async throws {
        for address in [MapsFixture.address, nil] {
            let driver = ControlledMapsDriver()
            let service = AppleMapsService(driver: driver)
            let request = ReverseGeocodeRequest(coordinate: try MapsFixture.coordinate(), generation: 3, localeIdentifier: MapsFixture.locale)
            let task = Task { try await service.reverseGeocode(request) }
            await driver.reverse.waitForStart()
            let result = ReverseGeocodedAddress(request: request, address: address)
            driver.reverse.complete(.success(result))
            let returned = try await task.value
            #expect(returned.coordinate == request.coordinate)
            #expect(returned.address == address && returned.request == request)
            #expect(driver.reverseRequest == request)
        }
        let driver = ControlledMapsDriver()
        let service = AppleMapsService(driver: driver)
        let request = ReverseGeocodeRequest(coordinate: try MapsFixture.coordinate(), generation: 1, localeIdentifier: nil)
        let task = Task { try await service.reverseGeocode(request) }
        await driver.reverse.waitForStart()
        driver.reverse.complete(.failure(.networkUnavailable))
        await #expect(throws: PlaceServiceError.networkUnavailable) { try await task.value }
    }

    /// AC-12: authoritative direct resolution carries known aliases and candidate identity through its boundary.
    @Test func directResolutionPreservesAliasesAndReportsMissingPlace() async throws {
        for succeeds in [true, false] {
            let driver = ControlledMapsDriver()
            let service = AppleMapsService(driver: driver)
            let identity = try PlaceIdentity(primaryID: MapsFixture.primary, alternateIDs: [MapsFixture.alias])
            let request = PlaceIdentityResolutionRequest(identity: identity, candidateID: UUID(), generation: 4, localeIdentifier: MapsFixture.locale)
            let task = Task { try await service.resolve(request) }
            await driver.identity.waitForStart()
            #expect(driver.identityRequest == request)
            if succeeds {
                let candidate = try MapsFixture.candidate(id: request.candidateID)
                driver.identity.complete(.success(PlaceIdentityResolution(request: request, candidate: candidate)))
                let result = try await task.value
                #expect(result.candidate.id == request.candidateID)
                #expect(result.candidate.placeIdentity?.allIDs == identity.allIDs)
            } else {
                driver.identity.complete(.failure(.notFound))
                await #expect(throws: PlaceServiceError.notFound) { try await task.value }
            }
        }
    }

    /// AC-12 / INV-03: newly resolved provider IDs preserve every previously known opaque alias.
    @Test func authoritativeIdentityMergeRetainsOldPrimaryAndAliases() throws {
        let known = try PlaceIdentity(primaryID: MapsFixture.primary, alternateIDs: [MapsFixture.alias])
        let merged = try #require(try AppleMapItemMapper.resolvedIdentity(
            primaryID: MapsFixture.newPrimary, alternateIDs: [MapsFixture.newAlias], knownIdentity: known
        ))
        #expect(merged.primaryID == MapsFixture.newPrimary)
        #expect(merged.allIDs == [MapsFixture.primary, MapsFixture.alias, MapsFixture.newPrimary, MapsFixture.newAlias])
        #expect(try AppleMapItemMapper.resolvedIdentity(primaryID: nil, alternateIDs: [], knownIdentity: known) == known)
        #expect(try AppleMapItemMapper.resolvedIdentity(primaryID: nil, alternateIDs: [], knownIdentity: nil) == nil)
    }

    /// AC-12: concrete local SDK mapping retains known primary/aliases when an item lacks identifiers.
    @Test func mapItemWithoutProviderIdentifierRetainsKnownIdentity() throws {
        let known = try PlaceIdentity(primaryID: MapsFixture.primary, alternateIDs: [MapsFixture.alias])
        let point = try MapsFixture.coordinate()
        let item = MKMapItem(location: CLLocation(latitude: point.latitude, longitude: point.longitude), address: nil)
        item.name = MapsFixture.name
        let id = UUID()
        let mapped = try AppleMapItemMapper.candidate(item, id: id, knownIdentity: known)
        #expect(mapped.id == id && mapped.coordinate == point)
        #expect(mapped.placeIdentity == known)
        #expect(try AppleMapItemMapper.candidate(item, id: id).placeIdentity == nil)
    }

    /// AC-43/54: route distance/time are provider metrics for the complete Walking/Driving request.
    @Test func walkingAndDrivingMetricsAndNoRouteRemainDistinct() async throws {
        for mode in [RouteMode.walking, .driving] {
            let driver = ControlledMapsDriver()
            let service = AppleMapsService(driver: driver)
            let request = try MapsFixture.route(mode: mode)
            let task = Task { try await service.estimateRoute(request) }
            await driver.route.waitForStart()
            let result = try RouteEstimate(request: request, distanceMetres: 1_234, duration: 456, computedAt: MapsFixture.time)
            driver.route.complete(.success(result))
            #expect(try await task.value == result)
            #expect(driver.routeRequest == request)
            #expect(result.mode == mode && result.distanceMetres == 1_234 && result.duration == 456)
        }
        let driver = ControlledMapsDriver()
        let service = AppleMapsService(driver: driver)
        let request = try MapsFixture.route(mode: .walking)
        let task = Task { try await service.estimateRoute(request) }
        await driver.route.waitForStart()
        driver.route.complete(.failure(.noRoute))
        await #expect(throws: PlaceServiceError.noRoute) { try await task.value }
    }

    /// AC-19/54: cancellation and duplicate callbacks never publish a second route result.
    @Test func routeCancellationRejectsLateSuccessExactlyOnce() async throws {
        let driver = ControlledMapsDriver()
        let service = AppleMapsService(driver: driver)
        let request = try MapsFixture.route(mode: .driving)
        let task = Task { try await service.estimateRoute(request) }
        await driver.route.waitForStart()
        task.cancel()
        await #expect(throws: PlaceServiceError.cancelled) { try await task.value }
        #expect(driver.route.cancellations == 1)
        let late = try RouteEstimate(request: request, distanceMetres: 1, duration: 1, computedAt: MapsFixture.time)
        driver.route.complete(.success(late))
        driver.route.complete(.failure(.noRoute))
        #expect(driver.route.cancellations == 1)
    }
}
