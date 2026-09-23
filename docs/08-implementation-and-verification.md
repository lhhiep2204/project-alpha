# Implementation plan and verification

Status: planned; no slice below is implemented by this documentation task. The three-tab scaffold predates this design. Implement one coherent slice at a time and update its status with evidence.

## Delivery order

| Slice | Deliverable and likely locations | Depends on | Exit evidence |
|---|---|---|---|
| P-00 | Inspect current working tree; preserve staged/uncommitted work. Verify iOS/iPadOS 27, Swift 6 mode and iPhone/iPad device family `1,2`. Inventory current adaptive gaps without rewriting the tab shell prematurely. | None | Scaffold build with installed SDK; project-setting audit; no unrelated file changes |
| P-01 | Domain values, validation, identity/duplicate policy, repository contracts; `Domain/` | P-00 | Pure unit tests for rules and normalization |
| P-02 | Versioned SwiftData schema, LibraryStore actor, bootstrap, atomic CRUD/moves, query observation; `Data/`, AppContainer | P-01 | In-memory store tests including failure rollback and concurrent duplicate attempts |
| P-03 | Local media staging/finalization/cleanup and async thumbnails; Data media service | P-02 | Temp-directory tests of failed save, cancel, crash reconciliation, referenced-file protection |
| P-04 | SceneCoordinator, typed routes, modal ownership, lifecycle-safe feature model factories and one logical navigation state across stack/split/tab/sidebar adaptation | P-02 | Router/intent tests with mock repository; restoration, resize/state-preservation and dirty-editor tests |
| P-05 | Home, Collection Detail, collection editor and quick capture/location editor with local CRUD/media and native compact/split presentations | P-03, P-04 | Offline library journeys, counts, default guard, quick save, duplicate/move UX and iPhone/iPad adaptive-layout QA |
| P-06 | Shared MapCanvas/search/detail, global retrieval entry, Collection Map and Global Map, camera and provider adapters | P-05 | Both map contracts, POI/manual/offline saves, search ranking/scope, iPad/iPhone Duo adaptation, safe-area/reserved-region and stale-request tests |
| P-07 | URL registration/ingress, deep-link execution and scene restoration | P-04, P-06 | Cold/warm/widget-like URL flows, stale data, modal interruption and intent stability through window/pose changes |
| P-08 | App Group contracts/publisher, two widget kinds, configuration, localization and family/content-margin adaptation | P-02, P-07 | App+extension build, projection tests and installed widget interactions across supported families/appearances |
| P-09 | Settings, local-storage limitation copy, all 20 locales, RTL, accessibility, keyboard/pointer, appearance, adaptive device matrix, performance, formative usability and release configuration | P-05 onward | Full acceptance matrix, participant/device QA and verified support/privacy configuration |

Create skeleton protocols only when their slice needs them. P-00 is not permission to overwrite the owner's existing work. Treat these contracts and acceptance criteria as the implementation authority.

## Acceptance criteria

| ID | Given / When / Then | Verification | Traces to |
|---|---|---|---|
| AC-01 | Given a new store, when bootstrap runs twice or from two scenes, then exactly one protected default collection exists. | Store integration | U-02, U-08 |
| AC-02 | Given the default collection, when any command attempts deletion/demotion, then it fails without changing records. | Domain + store | U-08 |
| AC-03 | Given a populated collection, when deletion fails before commit, then parent, locations and referenced photos remain intact. | Injected store/media failure | INV-04, INV-06 |
| AC-04 | Given a saved location, when notes/photos/favorite change, then its IDs/owner remain unchanged unless explicitly moved. | Unit + store | U-08, U-10 |
| AC-05 | Given Home, when a collection and location are tapped, then Collection Map shows its collection pins, focused location and detail. | UI journey | U-03, U-04 |
| AC-06 | Given a filtered Collection Detail list, when Show All is tapped, then the camera includes all collection locations, including filtered-out ones. | Camera unit + UI | U-05 |
| AC-07 | Given zero/one/coincident/antimeridian locations, when Show All is tapped, then a valid usable camera and correct empty/single state appear. | Camera cases + UI | U-05 |
| AC-08 | Given Collection Map, when Back is used, then its list query/scroll are restored and top-level tab/sidebar navigation is visible again. | UI | U-13 |
| AC-09 | Given Collection Map for A, when a candidate is saved to B, then A's scope/search remain unchanged and the confirmation names B. | Model + UI | U-06 |
| AC-10 | Given multiple collections, when Global Map loads, then all saved locations are available without collection filtering. | Query + UI | U-07 |
| AC-11 | Given the same place saved independently in A and B, when its overlapping pin is selected globally, then the user can select the correct record/collection. | UI | U-08, U-09 |
| AC-12 | Given a candidate with an intersecting primary/alternate ID in its destination, when Save is attempted, then a duplicate is blocked without overwriting the existing record. | Policy + store | U-09 |
| AC-13 | Given the same known place in A, when saved to B, then B receives its own UUID and independent user metadata. | Store | U-09 |
| AC-14 | Given no usable provider ID and same normalized coordinate/name, when saved in the same collection, then it is blocked. | Parameterized unit | U-19 |
| AC-15 | Given a possible duplicate only, when Save Anyway is confirmed, then current data is rechecked and save succeeds unless a hard duplicate/new unacknowledged warning is found. | Policy + store + UI | U-19 |
| AC-16 | Given two competing saves or repeated Save delivery, when writes run, then no hard duplicate is committed and an already committed draft is idempotent. | Concurrent integration | U-09, INV-05 |
| AC-17 | Given a moved location conflicts at its destination, when move is attempted, then its original owner and media remain unchanged. | Store | U-08, U-09 |
| AC-18 | Given Collection Map search, when matching places exist elsewhere, then saved results contain only its scope; Global Map search includes all collections. | Search unit + UI | U-15 |
| AC-19 | Given rapid queries/selection changes, when an older request finishes last, then it cannot replace the current results/detail/ETA. | Controllable fake adapter | D-03 |
| AC-20 | Given no network, when saved filtering or valid-coordinate saving is used, then it works; provider failures do not replace local results with an error screen. | Unit + airplane-mode QA | U-02, U-10 |
| AC-21 | Given an unresolved suggestion, over-limit name/notes or invalid/NaN/out-of-range coordinate, when Save is requested, then nothing persists with useful field feedback; explicit `(0,0)` remains valid. | Domain + store + UI | INV-02 |
| AC-22 | Given photo removal/replacement and a failed database save, then old referenced files survive and the draft can retry/cancel safely. | Failure integration | U-10, INV-06/08 |
| AC-23 | Given a cancelled draft or interrupted cleanup, when reconciliation runs, then only unreferenced abandoned files are removed. | Media integration | INV-08 |
| AC-24 | Given read-only detail, when dismissed, then selection clears but map/camera/scope remain; across compact/wide resize it moves between sheet and adjacent presentation without duplicate detail. | UI/device | U-12 |
| AC-25 | Given a location widget URL and another active tab, when handled, then Global Map opens and focuses the latest saved record. | Coordinator + UI | U-14 |
| AC-26 | Given a cold launch with a widget URL, then bootstrap finishes before resolution and restoration cannot override the URL destination. | Coordinator integration | U-14 |
| AC-27 | Given a dirty editor and external URL, when Keep Editing is chosen, then draft and navigation remain; Discard cleans up then opens the destination. | UI + coordinator | D-04 |
| AC-28 | Given a moved/unfavorited but existing widget location, when tapped, then it still opens globally using latest data. Deleted records show unavailable state. | Coordinator | U-14 |
| AC-29 | Given malformed/unsupported URLs or duplicate query keys, when received, then no mutation/navigation side effect occurs. | Parser unit | D-04 |
| AC-30 | Given a deleted collection/location in restoration state, when restoring, then navigation is pruned to valid content without recreating data. | Unit + UI | D-04 |
| AC-31 | Given writes from any screen, when they commit, then Home counts, both map queries and saved search update; camera is not needlessly reset. | Integration | D-02, D-03 |
| AC-32 | Given an earlier snapshot publication finishing after a later one, then the newer committed data wins; a language-only update also publishes. | Publisher unit | D-05 |
| AC-33 | Given a deleted/unconfigured widget collection, then widget shows Choose a Collection/missing state, never another collection's content. | Widget model | U-16 |
| AC-34 | Given corrupt or inaccessible App Group data, then widget shows last-known-good/unavailable state and app CRUD remains successful. | Widget/publisher failure tests | D-05 |
| AC-35 | Given each supported widget family, when a row is tapped, then the correct saved UUID opens globally; empty/background taps follow document 07. | Installed widget QA | U-14, U-16 |
| AC-36 | Given any supported locale, when using app/widget/settings, then required text is localized, counts pluralize and RTL is correct without losing drafts. | Catalog check + visual QA | U-17 |
| AC-37 | Given denied/restricted/reduced-accuracy permission, then saved library/search works; position/ETA explains limitations without repeated prompts. | Adapter + device | U-10 |
| AC-38 | Given local data and no account/network, when sharing, then a previewable system share payload is created; external Maps can receive the destination. | Payload + device | U-11 |
| AC-39 | Given phone/tablet compact/regular windows, Dynamic Type, VoiceOver, Voice Control and Switch Control, then key actions, map selection and editor validation are accessible. | UI/device | U-12, U-17 |
| AC-40 | Given a fresh v1 installation, then the app uses only ProjectAlpha identifiers and requires no pre-existing data, login/sync/cloud UI, backend SDK or Android runtime. | Configuration/repository audit | U-01, U-02, U-18 |
| AC-41 | Given collection image/icon and five location photos, when edited locally, then they persist/reload; remaining capacity is visible, a sixth photo is rejected before staging, and a per-asset import failure retains the other draft assets. | Store + media UI | U-10, INV-08 |
| AC-42 | Given a stale editor revision from another scene, when it saves, then it cannot overwrite newer changes silently. | Integration | INV-07 |
| AC-43 | Given two no-ID destinations or changed origin/mode, when selection changes, then ETA request identity changes and stale estimates disappear. | Unit | Map route-request contract |
| AC-44 | Given a resolved candidate with a default destination, when detail opens, then one explicit Save to that visible collection can commit without opening another form; all commit-time validation still runs. | Model + UI | U-20, D-13 |
| AC-45 | Given optional fields or staged photos in a quick-capture draft, when Add Details collapses or Save fails, then those values remain intact and the same draft identity is used. | Model + media UI | U-20, INV-08 |
| AC-46 | Given Collection Map A and a candidate saved into B, then A's scope/camera remain, a committed state names B, and Open Saved Place routes to the current record globally only after activation. | Coordinator + UI | U-06, D-08 |
| AC-47 | Given a successful save, then candidate/detail UI never presents the completed operation as still unsaved; repeated Save delivery returns the committed result rather than adding another row. | Model + store + UI | D-13, INV-05 |
| AC-48 | Given hard identity equivalence, when quick capture is used, then it blocks without overwriting metadata exactly as the detailed-editor path does. | Policy + store + UI | U-09, U-20 |
| AC-49 | Given equal normalized names farther than 20 metres apart and no hard equivalence, then no name-only warning appears; candidates within the proximity threshold still use acknowledged warning/recheck. | Parameterized policy unit | U-19, D-15 |
| AC-50 | Given saved notes, when a new share begins, then notes are excluded until explicitly included; the in-app preview and final payload agree and the next share defaults to excluded again. | Payload unit + device | U-11, D-14 |
| AC-51 | Given Home's Find Saved Places entry or offline Global Map search, then `All Saved Places` scope is visible, local results show collection context and open exact UUIDs, while only provider results report unavailability. | Coordinator + search UI | U-07, U-15 |
| AC-52 | Given identically named collections, then collection picker, widget configuration and overlapping-pin chooser expose enough visible and accessible context to select the intended ID. | Model + UI + VoiceOver | U-08 |
| AC-53 | Given a new-location editor opened from a list, when its place search resolves a candidate, then the same draft receives it without stacking an editor or losing optional fields; replacement of dirty fields requires a choice. | Coordinator + UI | D-04, D-13 |
| AC-54 | Given an ETA and a supported route-mode change, then the visible mode changes, stale ETA disappears, the new estimate uses that mode and straight-line distance remains clearly distinguished. | Model + UI | U-10 |
| AC-55 | Given a stale editor conflict, then the local draft and latest committed data remain available; Reload confirms draft loss and Reapply uses current revision/validation instead of a blind overwrite. | Integration + UI | INV-07 |
| AC-56 | Given a filtered Collection Detail list, then its map action names the full collection count and Back restores filter/scroll even though the map included filtered-out records. | Model + UI | U-05, U-13 |
| AC-57 | Given any app destination at compact or wide available space, when its hierarchy is shown or the window is resized, then the same three top-level destinations remain available through native tab/sidebar presentation and stack/split/adjacent navigation exposes the appropriate hierarchy without device-model, idiom, orientation, `UIScreen.main` or fixed-screen-breakpoint branching. | Architecture audit + UI/device | U-03, U-23, D-16 |
| AC-58 | Given active navigation, map selection/camera/search or a dirty draft with staged media, when an iPad window is resized or an iPhone Duo display/pose/layout changes, then route, state, user work and functionality are preserved exactly once while the presentation adapts. | Coordinator/model + UI/device | D-17, INV-09 |
| AC-59 | Given iPhone Duo outer/inner/open/closed/partially folded, side-by-side or Picture-in-Picture-constrained geometry, then foreground content honors asymmetric safe areas and SDK-exposed reserved regions; system bars can move vertically with labeled/prioritized usable overflow, and no important control is obscured or placed in the fold/curve. | Xcode 27.1 Device Hub + device UI | U-23, D-17 |
| AC-60 | Given every app and widget surface, when used with touch, keyboard, trackpad/pointer, VoiceOver, Voice Control, Switch Control, accessibility Dynamic Type, RTL, Reduce Motion or Reduce Transparency, then all functions remain discoverable and operable, native semantics/focus/scanning are preserved and every custom interactive target is at least 44 by 44 points. | Accessibility audit + UI/device/widget QA | U-17, U-23, D-17 |

## Test strategy

Use Swift Testing for Domain, ViewModel/coordinator and integration tests. Use XCTest UI tests for the small set of critical end-to-end journeys. Use fakes for provider requests and permission state; do not depend on live Apple search results in deterministic tests.

Store tests cover actual persistence boundaries and reload after commit/rollback. Media tests use temporary directories and injected failures, not production files. Use a controllable clock/continuations for debounce and race tests; do not rely on wall-clock sleeps as correctness assertions. Feature UI tests should focus on contract outcomes, not private implementation details.

Required device matrix: current supported iPhones in portrait/landscape; iPad full-screen, half, third, quadrant and floating/narrow resized windows; iPhone Duo outer and inner displays, open, closed and partially folded poses, side-by-side multitasking and relevant Picture-in-Picture-constrained resizing. Cross these with light/dark, default and accessibility text sizes, VoiceOver, Voice Control, Switch Control, keyboard, trackpad/pointer, Reduce Motion/Transparency, English, Vietnamese and RTL samples, plus offline, denied location and missing camera where relevant. Check all catalog locales mechanically even when visual sampling is smaller. Use Xcode 27.1 Device Hub for iPhone Duo evidence when available; if unavailable, record the exact toolchain limitation and do not claim the iPhone Duo acceptance criterion or Duo device coverage.

Before declaring user-facing v1 UX ready, run formative task testing with at least two representative participants from each intended context: everyday saving, travel collections and field work (six total). Test quick capture/retrieval/directions, same-named records/offline retrieval, and saving a manual point with notes/photos/private-note sharing. This sample discovers repeatable failures; it is not statistical evidence of a population success rate above 90%. Record unassisted completion, wrong destination/record, lost work, unintended payload content and save-to-feedback time. No critical task may have repeatable data loss, unintended note sharing or incorrect destination at release.

Profile the 100-collection/5,000-location dataset on a supported physical iPhone and iPad. Initial engineering targets: local interactive filtering within 150 ms after query processing, local lists usable within 1 second after store readiness, and no repeatable main-thread stall above 100 ms during local scrolling/pin selection on the measured devices. These are proposed release targets to measure and record, not verified performance claims or limits on user data. Provider response time is measured separately.

## Implementation-time commands

Run from repository root. Select an actually installed iOS 27 simulator from `xcodebuild -showdestinations`. iPhone Duo pose verification requires Xcode 27.1 Device Hub; the local Xcode 27.0 toolchain cannot supply that evidence.

```sh
xcodebuild -list -project ios/ProjectAlpha/ProjectAlpha.xcodeproj
xcodebuild -showdestinations -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha
xcodebuild build -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>'
xcodebuild test -project ios/ProjectAlpha/ProjectAlpha.xcodeproj -scheme ProjectAlpha -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -only-testing:ProjectAlphaTests
```

`<SIMULATOR_ID>` is intentionally a substitution value. Add focused UI tests to the run once their slice exists. Ensure the app scheme builds the embedded widget extension and shared contracts under Swift 6 mode. No app build/test result is asserted by this document.

## Release configuration gates

Resolve ProjectAlpha bundle IDs, developer team, App Group and URL scheme registration. App and widget deployment targets must be iOS/iPadOS 27. The current app and test targets already use device-family value `1,2` for iPhone/iPad and Swift 6 language mode; preserve those settings and review Mac-designed/visionOS availability settings instead of enabling extra platforms unintentionally.

Configure feedback email, privacy/support URLs, usage descriptions and app/widget localization resources. Verify the Settings local-storage/no-in-app-backup copy without claiming untested OS backup behavior. Review privacy declarations against the implemented binary and actual SDK use. Do not add analytics, ads, billing or publication work to this scope.

## Agent completion record

For each slice record: implemented AC IDs, changed files, exact validation commands/results, manual cases checked, unresolved limitations and any design deviations. If an SDK/runtime limitation blocks an AC, document the concrete limitation; do not silently mark it passed or substitute a different product flow.
