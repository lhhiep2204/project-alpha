# Scaffold architecture alignment

Updated: 2026-09-23. Scope: existing app shell, Collection value, preferences and presentation helpers. This is a completion record for the scaffold refactor, not completion of delivery slices P-01 through P-09.

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

## Current adaptive-UI gap

The checked-out scaffold currently uses a plain three-item SwiftUI `TabView`; each destination is wrapped in a `NavigationStack`. It does not yet use `NavigationSplitView`, tab/sidebar adaptation, size-class or scene-geometry layout policy, iPhone Duo safe/reserved-region handling, or pose/resize preservation tests. A source scan also found no `UIScreen.main`, interface-idiom or orientation branching to remove. This is a current-state record, not evidence that the new adaptive product decision, engineering decisions, invariant or acceptance criteria are implemented.

Subsequent feature slices must evolve this shell without creating a second navigation owner: keep the coordinator's three destination identities and logical routes while letting native containers adapt their presentation. Device Hub, iPad resizing, keyboard/pointer and accessibility evidence remains pending as specified in document 08.

Domain contains immutable, explicitly nonisolated Sendable Collection and CollectionIcon values. Collection includes a required revision and typed symbol/local-asset icon. Account-sharing scaffolding was removed. Preview fixtures live under Presentation/PreviewSupport and are compiled only in Debug.

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
