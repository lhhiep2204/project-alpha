# Scaffold architecture alignment

Scaffold refactor record: 2026-09-23; current-source rechecks: 2026-09-29. Scope: app shell, Collection value, preferences and presentation helpers. Historical build/test results below belong to the scaffold refactor; the current-source rechecks do not establish completion of delivery slices P-01 through P-09.

## Ownership and dependencies

| Owner | Lifetime | Responsibilities |
|---|---|---|
| ProjectAlphaApp | App | Retains AppContainer in State and composes the production UserDefaults adapter |
| AppContainer | App | Owns one observable AppPreferences and the existing feature factories |
| AppRootView | Scene | Retains its own SceneCoordinator; composes tab destinations and injects scene/preferences environment |
| SceneCoordinator | Scene | Owns selected tab and independent Home/Map/Settings routers |
| HomeView / MapView / SettingsView | Destination identity | Retain injected observable MainActor models in State |
| AppPreferences | App | Observable language/map/unit state, with writes serialized on MainActor |
| UserDefaultsPreferenceStore | App | Stores preferences using an explicitly supplied defaults suite |

MainTabView accepts typed destination builders and has no dependency on App containers. RouterView binds a borrowed router. Feature factories are cheap and side-effect-free; SwiftUI may call them more than once. A reconstructed view must not replace its active model. Routers do not own feature models, coordinators, views or callbacks, avoiding an ownership cycle.

## Current adaptive-UI state and gaps

The checked-out `MainTabView` has three SwiftUI `Tab` destinations and applies `.sidebarAdaptable` to its `TabView`. Home uses `HomeNavigationView` with `NavigationSplitView`: its selected route comes from the existing Home router's path and drives a detail column, while the system can collapse the split presentation. Map and Settings still use `RouterView` with `NavigationStack`. This is source-level evidence of tab/sidebar and Home split-view wiring, not device evidence that the adaptive contract works across window sizes.

The inspected tab/routing files have no device-model, interface-idiom, orientation or `UIScreen.main` layout branch. They do not yet establish iPhone Duo safe/reserved-region handling, or preservation of user work through pose/window resizing. Device Hub, iPad resizing, keyboard/pointer and accessibility evidence remains pending as specified in document 08. Subsequent feature slices must keep the coordinator's three destination identities and logical routes without creating a second navigation owner.

Current source recheck on 2026-09-29: Domain's immutable, explicitly nonisolated Sendable `Collection` has an ID, name, protected-default flag, timestamps and revision, with no icon or cover field. `LibrarySchemaV1.CollectionLocal` likewise has no icon or cover column. Account-sharing scaffolding was removed. Deterministic preview fixtures under `Presentation/PreviewSupport` and adjacent `#Preview` declarations have no `#if DEBUG` guard in the checked-out Swift files; this source inspection does not establish a new Release build result. The app and test project settings still specify Swift 6, iOS 27.0 and iPhone/iPad device family `1,2`.

Shared/Preferences is a narrow Foundation/value and preference-port boundary used by Data and Presentation. It is not a general dependency layer, and Domain does not depend on app settings. MapKit style conversion, localization and display formatting belong to Presentation.

## Localization and preferences

One AppPreferences instance is shared across scenes. Update preferences through that instance; do not construct a second live owner over the same store. The adapter preserves existing defaults keys and raw values. Tests and previews use isolated stores rather than changing the user's defaults. The scaffold defines `AppTheme` as System/Light/Dark, persists it through `AppPreferences` and `UserDefaultsPreferenceStore`, and maps it through `ThemeManager` to the root's preferred color scheme. `SettingsView` now contains a language picker and a System/Light/Dark theme menu, bound to the shared preferences; catalog labels for these controls are present for all supported locales. The Xcode MCP build passed on 2026-09-24; device verification is blocked because the required device-interaction skill is unavailable in this environment. AC-61 is not claimed as passed.

AppRootView reads observable language state and supplies locale/layoutDirection through the environment. Typed Text/Button keys use SwiftUI localization, so localized views participate in normal environment updates. There is no mutable static bundle, UIKit appearance mutation or root identity replacement. Date/distance formatting accepts an explicit locale. Actual translation catalogs and device RTL validation remain part of the later localization slice; this refactor does not claim support for translated content in all 20 languages.

## Concurrency and lifecycle rules for subsequent slices

- Async alone does not move CPU-intensive work off the UI actor. Choose and verify an execution boundary when image processing or other expensive work is introduced.
- Keep presentation state and preferences on MainActor. Pass copied Sendable values to background work; do not pass UI owners, contexts or mutable SDK objects across actors.
- Keep Domain nonisolated as new types are added. Swift 6 compiler checking must remain enabled; do not add unchecked Sendable or unsafe isolation to silence diagnostics.
- Start observation/loading from structured view lifecycle tasks or explicit start/stop methods, never from view/model initializers. Check cancellation, unregister streams on termination and reject stale completions when query/selection changes.
- Do not store a long-running Task that strongly captures its model indefinitely. Define who cancels each task when its screen/session ends. Weak references alone do not cancel work.
- Add the single LibraryStore actor and immutable query results when implementing persistence. Keep database validation and commit in one non-suspending critical section, as specified in document 03.
- Add modal/external-intent handling to the existing scene coordinator as those features arrive. Preserve per-scene ownership; do not move navigation to AppContainer.
- Extend lifecycle/race tests with each asynchronous service and use Instruments on real workloads when maps/media/persistence arrive. The scaffold tests cannot guarantee that future code has no races or leaks.

## Verification scope

Tests cover independent scene paths, preservation of paths across tab selection, preference persistence/fallback, actor transfer of Domain values, and release of scene/model/router/preference owners. A UIKit-hosted SwiftUI test rebuilds each of the three feature views and checks that its original model remains alive in State. The hosted test uses XCTest lifecycle expectations; value/architecture tests use Swift Testing.

The project targets iPhone/iPad on iOS/iPadOS 27, with Swift 6 for app and test targets. Mac Catalyst, Designed for Mac and Designed for Apple Vision availability are disabled. There are no new external packages.

No complete product acceptance criterion is claimed by this refactor. Storage, data validation, default-collection protection, map sessions, external intents, restoration, widget snapshots, translation catalogs and the adaptive iPad/iPhone Duo contract are not implemented here.

## Validation results

Verified with Xcode 27.0 (27A266a), iPhone 17 simulator running iOS 27.0.

1. Debug app/test build and all 8 focused tests passed (6 Swift Testing tests, 2 XCTest tests). Tests include actual SwiftUI model retention for all three feature views and observable locale invalidation.
2. Release simulator build passed (arm64 and x86_64).
3. `git diff --check` passed. Because the existing `ios/` tree is untracked, a separate source scan also checked Swift whitespace, Foundation-only Domain imports, absence of concrete App/Data dependencies in Presentation, and absence of unsafe isolation bypasses; all passed.
4. No Swift source/test compiler warnings remain in the final run. Xcode emits its standard metadata-extraction warning because the targets do not use AppIntents.

Commands, run from repository root:

```sh
xcodebuild test -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha -destination 'platform=iOS Simulator,id=EE0F5C38-82FD-4A27-BC67-0990EE69EC16' -derivedDataPath /tmp/project-alpha-review/DerivedData -parallel-testing-enabled NO -only-testing:ProjectAlphaTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -configuration Release -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/project-alpha-review/ReleaseData CODE_SIGNING_ALLOWED=NO
git diff --check
```

Final test result: `/tmp/project-alpha-review/DerivedData/Logs/Test/Test-ProjectAlpha-2026.09.21_19-09-12-+0700.xcresult`. Build/test logs are `/tmp/project-alpha-review/release.log` and `/tmp/project-alpha-review/verified-tests.log` (temporary local artifacts).

Manual device/RTL journeys, full product UI tests, Instruments leak profiling and Thread Sanitizer were not run. Weak-reference tests verify release of the current ownership graph; they are not a proof that future features cannot introduce leaks or races. No complete AC ID is marked implemented. No new backend, database, widgets or external-intent behavior was added.

The 2026-09-23 adaptive-contract documentation update re-read `MainTabView`, `RouterView`, `AppRootView` and `project.pbxproj`, then ran documentation link/ID/fence/whitespace checks only. It did not rerun the app build, tests, Device Hub, simulator, accessibility or iPhone Duo validation, and it does not extend the evidence above.

## Location and Apple Maps service foundation — 2026-10-07

Product-owner approval: 2026-10-06, as recorded in documents 01, 06 and 08. This is an implementation/evidence record for the early service portion of P-06; it does not declare full P-06 or any complete acceptance criterion passed. Change attribution uses HEAD `fe0ec3bc737787899d4d1b7a04a6be9652ff3d4b` and the task snapshot `/tmp/projectalpha-location-map-20261006-baseline/manifest.json` with its file copies; untracked files are compared against that baseline rather than attributed through Git diff alone.

Current-source inspection confirms six new Domain files for position/permission/accuracy values, freshness policy, provider requests/results, route estimates and typed service ports; four Data service files for the CoreLocation broker, Apple Maps adapter, independent search sessions and cancellable operations; AppContainer/MapContainer injection; and three deterministic Swift Testing files. AppContainer retains one device-location broker and one Maps adapter exposed through Domain ports. SDK location/search objects and provider work begin on demand, not during container initialization. A destination creates and owns its search session; each query replaces request state so an older SDK callback cannot become a newer query's result. Cancellation terminates the operation and its queued worker, with stale completions rejected.

The position service implements one-shot acquisition, fix age at most 30 seconds, a 30-second acquisition timeout after authorization, accepted Reduced Accuracy with timestamp/horizontal accuracy metadata, typed denial/restriction/service errors and terminal cleanup. Maps operations provide coordinate-preserving address enrichment without a nearby business identity, suggestions/resolution, direct opaque Place ID resolution preserving known aliases, and Walking/Driving route distance and duration. No route produces a typed failure rather than fabricated ETA. These service portions trace to AC-12/19/20/21/37/43/54, D-01/03/06/11/12/15/20 and INV-02/03/09; store, presentation and device outcomes in those criteria remain separate gates.

The project-setting diff adds only `NSLocationWhenInUseUsageDescription` to the app's Debug and Release generated Info configuration. Source/project settings and the gate's generated Info checks preserve Swift 6, minimum iOS 27.0 and device families `1,2`, with no Always usage description or background location mode. No production View is changed by this service foundation. The denied-permission Settings/Cancel dialog and Settings handoff remain deferred to UI integration; localization of the system permission-purpose copy remains a release gate.

### Independent service verification

The independent build gate used Xcode 27.0 (27A266a), Apple Swift 6.4 and an installed iPhone 17 Pro Max simulator on iOS 27.0. Xcode MCP discovery was used; its BuildProject operation did not expose the required isolated DerivedData/signing overrides, so the gate executed explicit CLI commands with `/tmp` DerivedData and `CODE_SIGNING_ALLOWED=NO`. This is simulator compilation/automated-test evidence, not manual UI/device evidence.

The initial affected run passed 38 tests with zero failures or skips: 28 new Domain/location/Maps tests, eight existing architecture tests and two existing view-ownership tests. It compiled the Debug app and test targets. The final incremental universal-simulator Release build passed with no Swift compiler warnings/errors. The final affected Maps run passed all 16 tests with zero failures, skips or runtime warnings, including the strengthened queued-cancellation regression that awaits worker termination. The independent architecture/concurrency reviewer reported zero unresolved P0–P3 findings after current-source and queued-worker termination regression re-review.

Gate artifacts are in `/tmp/projectalpha-location-map-finalgate-1XLO5r`: `focused-tests.xcresult`, `test-summary.json`, `maps-summary.json`, `maps-final.xcresult`, `release-final.xcresult`, their logs, `source-comparison-final.json` and `build-config-size.json`. Commands below were run by the gate from repository root; this documentation update does not rerun them.

```sh
xcodebuild -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha -configuration Debug -destination 'platform=iOS Simulator,id=508F78CB-9B01-42A4-9B2D-F5DE3C120FDD' -derivedDataPath /tmp/projectalpha-location-map-finalgate-1XLO5r/DerivedData -resultBundlePath /tmp/projectalpha-location-map-finalgate-1XLO5r/focused-tests.xcresult -only-testing:ProjectAlphaTests/LocationMapDomainTests -only-testing:ProjectAlphaTests/DeviceLocationServiceTests -only-testing:ProjectAlphaTests/AppleMapsServiceTests -only-testing:ProjectAlphaTests/ArchitectureTests -only-testing:ProjectAlphaTests/ViewOwnershipTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha -configuration Debug -destination 'platform=iOS Simulator,id=508F78CB-9B01-42A4-9B2D-F5DE3C120FDD' -derivedDataPath /tmp/projectalpha-location-map-finalgate-1XLO5r/DerivedData -resultBundlePath /tmp/projectalpha-location-map-finalgate-1XLO5r/maps-final.xcresult -only-testing:ProjectAlphaTests/AppleMapsServiceTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/projectalpha-location-map-finalgate-1XLO5r/ReleaseDerivedData -resultBundlePath /tmp/projectalpha-location-map-finalgate-1XLO5r/release-final.xcresult CODE_SIGNING_ALLOWED=NO build
```

No new dependencies, bundled assets or persistent caches were added. Lazy service initialization avoids starting location/provider requests at launch, and cancelled/superseded requests stop unnecessary work; responsiveness and physical-device performance remain unmeasured. The gate observed the current universal-simulator Release app at 9,501,542 logical bytes, including a 4,116,560-byte executable. These are current build-artifact observations, not a comparable size delta, installed footprint or proof of AC-65/66.

No live provider requests, permission-prompt interaction, manual UI, physical-device, adaptive/Duo, accessibility, localization, participant, installed-size or performance checks were run for this service foundation. The SDK adapters compiled; deterministic tests use injected location/provider/clock seams rather than live Apple search. The broader map UI, saved-library integration and deferred denial dialog still require their specified verification.

## Current-position timeout contract and source-state note — 2026-10-08

The product owner approved a 5-second acquisition timeout measured only after authorization, excluding system permission-prompt time; at that time the maximum fix age remained 30 seconds. The 2026-10-07 service-foundation implementation record above documents the then-current 30-second acquisition timeout and its associated gate results; it is a dated historical record and does not verify the revised 5-second contract. Source/test inspection for the 2026-10-08 handoff found 5-second timeout expectations and the then-current 30-second freshness limit. That documentation update did not run those tests or a build and did not establish AC-37.

## Past-fix acceptance and 5-second verification record — 2026-10-09

The product owner approved accepting the first geographically/metadata-valid fix with a finite nonfuture timestamp regardless of past age. At the time of this source inspection, the post-authorization timeout was 5 seconds; timestamp/accuracy metadata validation and authorization checks were present in `CurrentPositionPolicy`/`DevicePosition`, with no maximum-age cutoff. The position tests contained cases for fixes older than 30 seconds and much older past fixes, future timestamps, and timeout after 5 seconds. This is source/test inspection only. When this note was drafted, no build or tests had been run for the revised behavior; the 2026-10-07 service gate and 2026-10-08 source-state note above are historical. The focused verification below adds limited current deterministic evidence, but full AC-37 remains unpassed.

### Focused independent verification — 2026-10-09

Xcode MCP `BuildProject({workspaceIdentifier:"workspace-9h38OWdW1K",buildForTesting:true})` succeeded. `RunSomeTests` passed 13 tests: all 8 `DeviceLocationServiceTests` and 5 `LocationMapDomainTests`, on iPhone 18 Pro Max / iOS 27.0. Because Xcode MCP did not expose a DerivedData override, the gate also ran the required isolated CLI rerun below. With Xcode 27.0 (27A266a) and Swift 6.4, it exited 0 with `TEST SUCCEEDED`, 13 passed and 0 errors; the only three warnings were AppIntents metadata skips. Log: `/tmp/projectalpha-cached-position-20261009-focused.log`; result bundle: `/tmp/projectalpha-cached-position-20261009-focused.xcresult`.

```sh
xcodebuild test -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha -destination 'platform=iOS Simulator,id=5932A560-C3AF-4C8C-8AE9-344E3C51ACF8' -derivedDataPath /tmp/projectalpha-cached-position-20261009-derived CODE_SIGNING_ALLOWED=NO -only-testing:ProjectAlphaTests/DeviceLocationServiceTests -only-testing:ProjectAlphaTests/LocationMapDomainTests -resultBundlePath /tmp/projectalpha-cached-position-20261009-focused.xcresult
```

This is focused build and deterministic service/domain test evidence for the revised one-shot past-fix acceptance and 5-second timeout contract then in force. It does not pass full AC-37: no manual map UI, live GPS/provider, permission UI/device, performance, or size validation was performed.

### Updated timeout contract and current source state — 2026-10-09

The product owner later approved increasing the post-authorization acquisition timeout from 5 to 10 seconds, still excluding permission-prompt time; past-fix acceptance and no-fallback semantics remain unchanged. Current-source inspection shows `CurrentPositionPolicy.acquisitionTimeout` and the test deadline assertions set to 10 seconds. The focused verification below provides deterministic evidence for this revised timeout; the earlier 5-second gate above remains historical. Full AC-37 is not marked passed.

### Focused verification of 10-second acquisition — 2026-10-09

The isolated final gate ran on the iPhone 18 Pro Max / iOS 27.0 simulator with signing disabled and isolated DerivedData. It passed all 13 focused tests: 8 `DeviceLocationServiceTests` and 5 `LocationMapDomainTests`. The command exited 0 with `TEST SUCCEEDED`, 13 passed and 0 errors; the only three notices were skipped AppIntents metadata. Log: `/tmp/projectalpha-location-timeout-10s-focused.log`; result bundle: `/tmp/projectalpha-location-timeout-10s-focused.xcresult`.

```sh
xcodebuild test -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha -destination 'platform=iOS Simulator,id=5932A560-C3AF-4C8C-8AE9-344E3C51ACF8' -derivedDataPath /tmp/projectalpha-location-timeout-10s-derived CODE_SIGNING_ALLOWED=NO -only-testing:ProjectAlphaTests/DeviceLocationServiceTests -only-testing:ProjectAlphaTests/LocationMapDomainTests -resultBundlePath /tmp/projectalpha-location-timeout-10s-focused.xcresult
```

This records focused deterministic service/domain coverage for the updated timeout and past-fix acceptance. Full AC-37 remains unpassed: no manual map UI, live GPS/provider, permission UI/device matrix, performance or size validation was performed.
