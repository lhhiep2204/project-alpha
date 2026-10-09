//
//  ViewOwnershipTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/9/26.
//

import Observation
import SwiftUI
import UIKit
import XCTest
@testable import ProjectAlpha

private enum OwnershipTestValue {
    static let detailReady = "Collection detail rendered ready"
    static let detailRenamed = "Collection detail rendered committed rename"
    static let detailName = "Trips"
    static let renamedDetailName = "Renamed Trips"
    static let localeInvalidated = "Locale dependency invalidated"
    static let featureAppeared = "Feature appeared"
    static let parentReconstructed = "Parent reconstructed"
    static let originalModelLost = "The original model must remain owned by SwiftUI @State"
    static let featureIdentifierPrefix = "feature-"
    static let toastAppeared = "Constrained toast appeared"
    static let toastViewport = CGSize(width: 320, height: 120)
    static let minimumInteractiveSize = 44.0
    static let toastGeometryAttachment = "Toast public UIKit layout diagnostics"
    static let toastGeometryLogPrefix = "TOAST_LAYOUT_DIAGNOSTICS "
    static let viewport = "viewport"
    static let fittedSize = "fittedSize"
    static let windowFrame = "windowFrame"
    static let windowBounds = "windowBounds"
    static let windowSafeAreaInsets = "windowSafeAreaInsets"
    static let hostFrame = "hostFrame"
    static let hostBounds = "hostBounds"
    static let hostSafeAreaInsets = "hostSafeAreaInsets"
    static let scrollViews = "scrollViews"
    static let scrollFrame = "scrollFrame"
    static let scrollBounds = "scrollBounds"
    static let scrollContentSize = "scrollContentSize"
    static let scrollAdjustedContentInset = "scrollAdjustedContentInset"
}

/// Exercises actual SwiftUI state storage, not just references created in a unit test.
@MainActor
final class ViewOwnershipTests: XCTestCase {
    /// AC-05/63, D-01/03/19: the real detail view keeps observing after loading changes content.
    /// This is UIKit/SwiftUI lifecycle coverage, not manual first-frame or modal-interaction evidence.
    func testCollectionDetailKeepsReadyContentAndReceivesLaterCommit() async throws {
        let id = UUID()
        let collection = Collection(id: id, name: OwnershipTestValue.detailName, isDefault: false,
                                    createdAt: Date(timeIntervalSince1970: 1),
                                    updatedAt: Date(timeIntervalSince1970: 1), revision: 1)
        let initial = CollectionListSnapshot(
            collections: [CollectionSummary(collection: collection, locationCount: 0)], libraryRevision: 1
        )
        let repository = DetailLifecycleRepository(initial: initial)
        let router = Router<HomeRoute>(paths: [.collection(id: id)], root: .root)
        let model = CollectionDetailViewModel(collectionID: id, repository: repository, router: router)
        let ready = expectation(description: OwnershipTestValue.detailReady)
        ready.assertForOverFulfill = false
        let renamed = expectation(description: OwnershipTestValue.detailRenamed)
        renamed.assertForOverFulfill = false
        let host = UIHostingController(rootView: DetailLifecycleHarness(
            model: model,
            ready: { ready.fulfill() },
            renamed: { renamed.fulfill() }
        ).environment(SceneCoordinator()))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        // Expectations acknowledge rendered state transitions; no sleep orders the stream.
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(model.phase, .ready)
        let updated = Collection(id: id, name: OwnershipTestValue.renamedDetailName, isDefault: false,
                                 createdAt: collection.createdAt,
                                 updatedAt: Date(timeIntervalSince1970: 2), revision: 2)
        await repository.publish(CollectionListSnapshot(
            collections: [CollectionSummary(collection: updated, locationCount: 0)], libraryRevision: 2
        ))
        await fulfillment(of: [renamed], timeout: 5)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.collection?.collection, updated)
        XCTAssertEqual(model.displayTitle(hint: nil), OwnershipTestValue.renamedDetailName)
        XCTAssertEqual(router.paths, [.collection(id: id)])
        let subscriptions = await repository.subscriptionCount
        XCTAssertEqual(subscriptions, 1)
        await repository.finish()
    }

    /// AC-37 / AC-60: the real SwiftUI toast keeps long AX text scrollable in a short scene.
    /// This hosted lifecycle check supplements, rather than replaces, assistive/device QA.
    func testToastLongAccessibilityTextFitsShortViewportAndScrolls() async throws {
        let appeared = expectation(description: OwnershipTestValue.toastAppeared)
        let host = UIHostingController(rootView:
            DSToastView(
                presentation: DSToastPreviewFixtures.longPresentation,
                maximumHeight: OwnershipTestValue.toastViewport.height,
                onDismiss: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .onAppear { appeared.fulfill() }
        )
        // This fixture's viewport is the toast component's content area, rather than
        // a scene including system chrome. The modifier integration below owns safe areas.
        host.safeAreaRegions = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame.size = OwnershipTestValue.toastViewport
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        await fulfillment(of: [appeared], timeout: 5)
        host.view.frame = CGRect(origin: .zero, size: OwnershipTestValue.toastViewport)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let fitted = host.sizeThatFits(in: OwnershipTestValue.toastViewport)
        let diagnostics: [String: Any] = [
            OwnershipTestValue.viewport: String(describing: OwnershipTestValue.toastViewport),
            OwnershipTestValue.fittedSize: String(describing: fitted),
            OwnershipTestValue.windowFrame: String(describing: window.frame),
            OwnershipTestValue.windowBounds: String(describing: window.bounds),
            OwnershipTestValue.windowSafeAreaInsets: String(describing: window.safeAreaInsets),
            OwnershipTestValue.hostFrame: String(describing: host.view.frame),
            OwnershipTestValue.hostBounds: String(describing: host.view.bounds),
            OwnershipTestValue.hostSafeAreaInsets: String(describing: host.view.safeAreaInsets),
            OwnershipTestValue.scrollViews: descendantScrollViews(in: host.view).map { scroll in
                [
                    OwnershipTestValue.scrollFrame: String(describing: scroll.convert(scroll.bounds, to: host.view)),
                    OwnershipTestValue.scrollBounds: String(describing: scroll.bounds),
                    OwnershipTestValue.scrollContentSize: String(describing: scroll.contentSize),
                    OwnershipTestValue.scrollAdjustedContentInset: String(describing: scroll.adjustedContentInset)
                ]
            }
        ]
        let diagnosticsData = try JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys])
        let diagnosticsText = String(decoding: diagnosticsData, as: UTF8.self)
        let attachment = XCTAttachment(string: diagnosticsText)
        attachment.name = OwnershipTestValue.toastGeometryAttachment
        attachment.lifetime = .keepAlways
        add(attachment)
        print(OwnershipTestValue.toastGeometryLogPrefix + diagnosticsText)
        XCTAssertLessThanOrEqual(fitted.height, OwnershipTestValue.toastViewport.height)
        XCTAssertGreaterThanOrEqual(fitted.height, OwnershipTestValue.minimumInteractiveSize)
        let scroll = try XCTUnwrap(descendantScrollViews(in: host.view).first)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertGreaterThan(scroll.bounds.height, 0)
        XCTAssertTrue(host.view.bounds.contains(scroll.convert(scroll.bounds, to: host.view)))
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
        XCTAssertGreaterThan(scroll.contentOffset.y, 0)
    }

    /// AC-37 / AC-60: scene-level toast uses the real safe-area proposal at AX text sizes.
    /// Swipe dismissal and assistive operability require the separate UI/device gate.
    func testToastModifierKeepsScrollableTextInsideSceneSafeArea() async throws {
        let appeared = expectation(description: OwnershipTestValue.toastAppeared)
        let manager = DSToastManager(currentPresentation: DSToastPresentation(
            id: DSToastPreviewFixtures.identifier,
            message: DSToastPreviewFixtures.longMessage,
            duration: .seconds(3_600)
        ))
        let host = UIHostingController(rootView:
            Color.clear
                .dsToast(manager: manager)
                .environment(\.dynamicTypeSize, .accessibility5)
                .onAppear { appeared.fulfill() }
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame.size = OwnershipTestValue.toastViewport
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            manager.dismiss()
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        await fulfillment(of: [appeared], timeout: 5)
        host.view.frame = CGRect(origin: .zero, size: OwnershipTestValue.toastViewport)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let safeViewport = host.view.safeAreaLayoutGuide.layoutFrame
        let scroll = try XCTUnwrap(descendantScrollViews(in: host.view).first)
        XCTAssertTrue(safeViewport.contains(scroll.convert(scroll.bounds, to: host.view)))
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertGreaterThan(scroll.bounds.height, 0)
    }

    private func descendantScrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { descendantScrollViews(in: $0) }
    }

    func testFeatureModelsSurviveParentReconstruction() async throws {
        let repository = SwiftDataCollectionRepository(store: LibraryStore(
            container: try LibraryStoreConfiguration.makeContainer(isStoredInMemoryOnly: true)
        ))
        try await assertRetained(factory: {
            HomeViewModel(
                router: .init(root: .root),
                repository: repository,
                useCases: CollectionUseCases(repository: repository)
            )
        }, content: { HomeView(viewModel: $0, selection: .constant(nil)) })
        try await assertRetained(factory: {
            MapViewModel(router: .init(root: .root), deviceLocationService: MapPresentationLocationService())
        }, content: { MapView(viewModel: $0, rendersLiveMap: false) })
        try await assertRetained(factory: { SettingsViewModel(router: .init(root: .root)) }, content: SettingsView.init)
    }

    func testLanguageChangesInvalidateObservedLocale() async {
        let preferences = AppPreferences(store: MemoryPreferences())
        let changed = expectation(description: OwnershipTestValue.localeInvalidated)
        withObservationTracking {
            _ = preferences.language.locale
        } onChange: {
            changed.fulfill()
        }
        preferences.language = .vietnamese
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(preferences.language.locale.identifier, LanguageCode.vietnamese)
    }

    private func assertRetained<Model: AnyObject, Content: View>(
        factory: @escaping @MainActor () -> Model,
        content: @escaping @MainActor (Model) -> Content
    ) async throws {
        let signal = RenderSignal()
        let probe = ModelProbe()
        let appeared = expectation(description: OwnershipTestValue.featureAppeared)
        let updated = expectation(description: OwnershipTestValue.parentReconstructed)
        let host = UIHostingController(rootView: OwnershipHarness(
            signal: signal, probe: probe, factory: factory, content: content,
            appeared: { appeared.fulfill() }, updated: { updated.fulfill() }
        )
            .environment(AppPreferences(store: MemoryPreferences()))
            .environment(DSToastManager())
            .environment(SceneCoordinator()))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        await fulfillment(of: [appeared], timeout: 5)
        XCTAssertNotNil(probe.first)
        let previousCount = probe.constructions
        signal.revision += 1
        await fulfillment(of: [updated], timeout: 5)
        XCTAssertGreaterThan(probe.constructions, previousCount)
        XCTAssertNotNil(probe.first, OwnershipTestValue.originalModelLost)
    }
}

@Observable @MainActor
private final class RenderSignal {
    var revision = 0
}

@MainActor
private final class ModelProbe {
    weak var first: AnyObject?
    var constructions = 0

    func record(_ model: AnyObject) {
        if constructions == 0 { first = model }
        constructions += 1
    }
}

@MainActor
private struct OwnershipHarness<Model: AnyObject, Content: View>: View {
    let signal: RenderSignal
    let probe: ModelProbe
    let factory: @MainActor () -> Model
    let content: @MainActor (Model) -> Content
    let appeared: () -> Void
    let updated: () -> Void

    var body: some View {
        let revision = signal.revision
        let model = factory()
        let _ = probe.record(model)
        content(model)
            .accessibilityIdentifier(OwnershipTestValue.featureIdentifierPrefix + String(revision))
            .onAppear(perform: appeared)
            .onChange(of: revision) { updated() }
    }
}

@MainActor
private final class MemoryPreferences: PreferenceStore {
    var language: Language = .system
    var theme: AppTheme = .system
    var mapType: MapType = .standard
    var distanceUnit: DistanceUnit = .kilometre
}

@MainActor
private struct DetailLifecycleHarness: View {
    let model: CollectionDetailViewModel
    let ready: () -> Void
    let renamed: () -> Void

    var body: some View {
        NavigationStack {
            CollectionDetailView(viewModel: model)
        }
        .onChange(of: model.phase) {
            if model.phase == .ready { ready() }
        }
        .onChange(of: model.collection?.collection.name) {
            if model.collection?.collection.name == OwnershipTestValue.renamedDetailName { renamed() }
        }
    }
}

private enum DetailLifecycleFailure: Error { case unusedOperation }

/// Every subscription receives its own initial result, matching the Domain observation port.
private actor DetailLifecycleRepository: CollectionRepository {
    let initial: CollectionListSnapshot
    private(set) var subscriptionCount = 0
    private var continuations: [AsyncThrowingStream<CollectionListSnapshot, any Error>.Continuation] = []

    init(initial: CollectionListSnapshot) { self.initial = initial }

    func observeSnapshots() async -> AsyncThrowingStream<CollectionListSnapshot, any Error> {
        let (stream, continuation) = AsyncThrowingStream<CollectionListSnapshot, any Error>.makeStream()
        subscriptionCount += 1
        continuations.append(continuation)
        continuation.yield(initial)
        return stream
    }

    func publish(_ snapshot: CollectionListSnapshot) {
        continuations.forEach { $0.yield(snapshot) }
    }

    func finish() {
        continuations.forEach { $0.finish() }
        continuations.removeAll()
    }

    func bootstrap(_ command: BootstrapCollectionCommand) async throws -> CollectionListSnapshot {
        throw DetailLifecycleFailure.unusedOperation
    }
    func snapshot() async throws -> CollectionListSnapshot { initial }
    func collection(id: UUID) async throws -> CollectionSummary? {
        initial.collections.first { $0.id == id }
    }
    func create(_ command: CreateCollectionCommand) async throws -> CollectionCommit {
        throw DetailLifecycleFailure.unusedOperation
    }
    func update(_ command: UpdateCollectionCommand) async throws -> CollectionCommit {
        throw DetailLifecycleFailure.unusedOperation
    }
    func delete(_ command: DeleteCollectionCommand) async throws -> DeleteCollectionCommit {
        throw DetailLifecycleFailure.unusedOperation
    }
}
