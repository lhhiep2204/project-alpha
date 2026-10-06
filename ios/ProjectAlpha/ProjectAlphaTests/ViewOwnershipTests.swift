import Observation
import SwiftUI
import UIKit
import XCTest
@testable import ProjectAlpha

private enum OwnershipTestValue {
    static let localeInvalidated = "Locale dependency invalidated"
    static let featureAppeared = "Feature appeared"
    static let parentReconstructed = "Parent reconstructed"
    static let originalModelLost = "The original model must remain owned by SwiftUI @State"
    static let featureIdentifierPrefix = "feature-"
}

/// Exercises actual SwiftUI state storage, not just references created in a unit test.
@MainActor
final class ViewOwnershipTests: XCTestCase {
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
        try await assertRetained(factory: { MapViewModel(router: .init(root: .root)) }, content: MapView.init)
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
