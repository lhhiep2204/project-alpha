# ProjectAlpha agent instructions

These instructions govern every task in this repository, including work delegated to custom agents under `.codex/agents/`.

## Authority and current state

- Read `README.md` and `docs/README.md` before changing code.
- Treat `docs/01-product-and-decisions.md` through `docs/09-apple-technology-references.md` as the approved target product and architecture contract.
- Treat the checked-out source, `ios/ProjectAlpha/ProjectAlpha.xcodeproj/project.pbxproj`, and `docs/10-scaffold-architecture-verification.md` as the authority for the scaffold's current implementation state.
- The source currently confirms that app and test targets use Swift 6 and target iPhone/iPad device families (`1,2`). Do not regress either setting; recheck source/project settings before changing current-state documentation.
- If documents disagree about user-visible behavior, data identity, feature scope, or an invariant, stop and ask the product owner. Do not silently select a contract.
- `U-*` entries are confirmed product decisions, `D-*` entries are engineering decisions, `INV-*` entries are invariants, `AC-*` entries are acceptance criteria, and `FUTURE` is explicitly out of current scope.

## Clarification gate

- If any question, uncertainty, ambiguity, contradiction, missing requirement, unclear ownership, unsupported or unverified API, or unclear evidence expectation arises at any time, stop before making the affected assumption or change and ask the user.
- Never infer a product/UX choice, silently choose a default, widen scope, or mark work complete while such a question is unresolved. Read-only investigation may continue only when it cannot commit the work to one of the unresolved choices.
- Resume the affected work only after the user answers. Record the answer in the relevant handoff; approved contract changes still belong to `projectalpha_contract_maintainer`.

## Required reading by task

Always read docs 01, 03, 04, 08, and 10 plus the relevant feature document:

- Collection/location CRUD or editors: docs 02 and 04.
- Navigation, restoration, or external intents: docs 05 and 07.
- Maps, search, location detail, position, ETA, directions, or sharing: docs 02, 05, 06, and 09.
- Widgets: docs 04, 05, 07, and 09.
- Persistence, concurrency, or media: docs 03, 04, and 08.
- Settings, localization, accessibility, or release configuration: docs 01, 02, 08, and 09.
- Any app or widget UI, navigation, layout, component, or UX work: docs 01, 02, 05, 08, and 09 plus the current official Apple Human Interface Guidelines for iOS, iPadOS, Layout, and the relevant component. iPhone Duo work must also read Apple's current Designing for iPhone Duo guidance and associated developer documentation.

Before adopting an Apple API, verify the declaration and availability in the installed SDK or current official Apple documentation, then compile a focused use. Do not invent API names from summaries or snippets.

The project-scoped MCP server `xcode` is `xcrun mcpbridge`. Agents that need simulator/Xcode evidence must use it to discover the scheme and installed simulator, build/install/launch when applicable, inspect the accessibility/UI tree, capture screenshots/logs, and re-read state after interactions. Do not guess simulator state from source or coordinates alone. Xcode MCP availability is an environment capability, not a pass condition: if unavailable, report `BLOCKED` with the exact tool/environment error and do not claim UI/device evidence. Store screenshots, logs, result bundles, and traces outside the repository unless the task explicitly owns an artifact path.

## Working-tree safety

- Start and finish with `git status --short --branch --untracked-files=all`.
- The current `ios/` tree may be untracked. Untracked does not mean disposable. Preserve it and all staged, unstaged, generated, or unrelated user work.
- Before any write-capable agent edits an untracked file, the orchestrator must provide an immutable baseline: either a tracked/staged Git baseline explicitly established by the owner, or a task-specific snapshot outside the repository with file inventory and checksums. Record the baseline identity/path in every writer and reviewer assignment. If no such baseline exists, the write task is `BLOCKED`; never run `git add` or commit merely to manufacture one without owner authorization.
- When reviewing untracked work, compare against that recorded snapshot (or an owner-provided patch). A plain `git diff` is not change attribution for untracked files.
- Never reset, replace, delete, or broadly reformat files outside the assigned scope.
- Do not edit a file concurrently with another write-capable agent. Parallelize read-only exploration, test execution, or reviews; serialize overlapping edits.
- Only `projectalpha_composition_integrator` may edit `project.pbxproj`, target membership, generated Info settings, entitlements, bundle identifiers, URL registration, or signing-related project configuration. Other agents must hand those changes off.
- Exact shared ownership: scene navigation owns `Presentation/Features/MainTabs/**`; settings/localization owns `Shared/Preferences/**`, `Data/Preferences/**`, `Presentation/Preferences/**`, `Presentation/DesignSystem/**`, `Presentation/Localization/**`, and `Presentation/Formatting/**`; composition owns app/release assets and `Shared/Utilities/**`. Feature-specific preview fixtures belong to that feature owner.

## Architecture boundaries

- Domain owns immutable Foundation values, validation, policies, use cases, and ports. It must not import SwiftUI, MapKit, CoreLocation, SwiftData, contain localized UI strings, or depend on app preferences.
- Data owns SwiftData models/mappers/store, repository implementations, Apple service adapters, and media persistence. It must not own routes, tabs, sheets, or UI copy.
- Presentation owns `@MainActor` observable state, drafts, routing requests, SwiftUI, map rendering, formatting, and localization. It must not mutate SwiftData or files directly or reimplement business identity rules.
- App owns manual dependency injection, shared service lifetime, bootstrap, scene lifecycle, and integration wiring. It must not hide business validation in factories.
- Shared extension contracts contain only versioned Foundation DTOs and URL/snapshot encoding. Widgets must not import the app container or open the live SwiftData store.
- Keep one app-owned persistence writer, one app-owned preferences owner, a `SceneCoordinator` per scene, and state per map session. Collection Map scope and save destination are independent concepts.
- Factories and initializers must be cheap and side-effect-free. Start and cancel observation through structured lifecycle tasks or explicit start/stop methods.
- Preserve Swift 6 isolation. Do not use `@unchecked Sendable`, `nonisolated(unsafe)`, detached work, or global mutable state to hide an ownership or concurrency error.

## Adaptive Apple UI/UX contract

- Treat current Apple Human Interface Guidelines as the platform design authority. Prefer standard SwiftUI containers and controls so navigation, presentation, safe areas, bar placement, input, accessibility, and appearance inherit system behavior. A custom component needs a documented task-specific reason and equivalent accessibility/input behavior.
- Adapt from the space available to the current scene using size classes, container geometry, safe areas, layout margins, and verified platform APIs. Do not branch layout from device model, `userInterfaceIdiom`, interface orientation, `UIScreen.main`, or fixed screen-width assumptions.
- Preserve Home, Map, and Settings as the same three top-level destinations. Use the system tab/sidebar presentation appropriate to the available space. Use `NavigationSplitView` for hierarchical content when adjacent columns materially improve a regular-width experience, and let it collapse to one recognizable stack at compact widths; do not create a second route or presentation-state owner for the wide layout.
- On iPad, support fluid window resizing and multitasking across compact, intermediate, and regular widths. Use additional space to keep related navigation/content or map/detail visible, minimize unnecessary full-screen/modal transitions, and keep every action usable with touch, hardware keyboard, trackpad/pointer, VoiceOver, Voice Control, Switch Control, Dynamic Type, and RTL.
- On iPhone Duo, keep the same task hierarchy, state, and functionality across outer/inner displays, open/closed/partially folded poses, Split View, and vertically constrained/Picture-in-Picture layouts. Respect asymmetric safe areas and reserved regions. Let system toolbars, tab bars, sheets, menus, and split views adapt to the fold and vertical bar axis; group and label toolbar items, prioritize important actions, and use the system overflow menu.
- Interactive and legible foreground content stays inside the applicable safe/reserved regions even when decorative backgrounds extend edge to edge. Provide a button, menu, keyboard, and accessibility alternative for gesture-only actions. Custom hit regions are at least 44 by 44 points.
- Resizing, a size-class change, a display/pose change, or a bar-axis change is presentation-only. It must not discard or duplicate a route, selected ID, map scope/camera, search session, active draft/staged media, pending intent, or committed data.
- Before naming or adopting a new Apple symbol, verify its declaration and availability in the installed SDK and compile a focused use. At the 2026-09-23 baseline, local Xcode 27.0 does not expose every API described in the iPhone Duo/Xcode 27.1 documentation; recheck the active toolchain, report the exact limitation, and ask the user instead of inventing an API, silently changing the deployment target, or claiming Duo evidence.

## Product invariants and exclusions

- Preserve INV-01 through INV-09 and the exact duplicate policy in docs 04. Provider identity intersection blocks; the approved normalized coordinate/name fallback blocks; proximity at or below 20 metres warns; a same name at a remote coordinate does not warn by itself.
- Exactly one protected default collection exists after bootstrap. A saved location has exactly one existing owner. Cross-collection copies are independent records.
- A write validates against current data and commits atomically. Do not suspend between read/check/mutate/save in the store's critical section. Emit success only after persistence succeeds.
- Never delete committed media before the database removes its reference. Prefer recoverable orphan files over lost user files.
- Quick capture, detailed editing, and retry use one stable draft identity and the same commit-time validation.
- Collection Map and Global Map retain separate scope, camera, search, selection, and presentation state.
- Do not add backend, authentication, CloudKit/sync, analytics, ads, billing, Android runtime, speculative DTOs, Share Extension, universal links, or third-party routing/DI/state/maps frameworks without a new approved specification.

## Feature and bug workflow

1. Classify the request against P-00 through P-09 and list affected U/D/INV/AC identifiers.
2. Inspect the real execution path and surrounding tests before editing.
3. For a bug, reproduce or establish the failure from evidence, identify the owning layer, and define a regression test at the lowest meaningful boundary.
4. Make the smallest coherent change inside the assigned agent's ownership. Request a handoff for cross-owner files instead of expanding scope silently.
5. Keep deterministic seams for clocks, IDs, provider requests, permission states, media files, and failures. Never depend on live Apple search in automated tests or wall-clock sleeps for correctness.
6. Run focused verification, then the relevant broader build/test gate. A successful build alone does not satisfy an acceptance criterion.
7. Update product decisions and acceptance criteria together only when the product owner approved a behavior/scope change. A normal bug fix should not rewrite the specification.

## Verification and reporting

- Use Swift Testing for Domain, presentation-model/coordinator, and integration tests. Use XCTest UI only for critical end-to-end or UIKit lifecycle behavior.
- Store tests use in-memory SwiftData but verify real save/reload/rollback/concurrency behavior. Media tests use isolated temporary directories. Provider and permission tests use deterministic fakes.
- Select an actually installed iOS 27 simulator; do not hard-code an old simulator UUID. Use an isolated DerivedData path under `/tmp` and `CODE_SIGNING_ALLOWED=NO` for simulator verification.
- Adaptive UI verification must exercise iPhone portrait/landscape, iPad full/half/third/quadrant/floating minimum-to-maximum widths, keyboard and pointer input, accessibility configurations, and iPhone Duo outer/inner/open/closed/partially folded and multitasking configurations when the required Xcode 27.1 Device Hub/runtime is available. If it is unavailable, report `BLOCKED` for those cases and do not substitute source inspection or an ordinary iPhone/iPad simulator as Duo evidence.
- Distinguish product failures from simulator service, sandbox, signing, or environment failures.
- Run `git diff --check`; when source is untracked, also inspect those files because Git diff does not cover them.
- Never claim device, accessibility, RTL, widget, performance, or participant testing unless it was actually run in the required environment.
- Every completion report must state: assigned scope, affected AC/INV/D identifiers, changed files, exact commands and results, manual checks, remaining limitations, and any approved deviation.
- Implementers may report `implementation complete; independent verification pending`. Only the primary orchestrator may declare an AC or slice `READY`/`PASSED`, and only after every applicable independent test, review, build, and device gate has reported current evidence.

## Project skill routing

- Project skills live under `.agents/skills/`. Load the relevant `SKILL.md` and its referenced material when the task matches; all agents working in this repository can use these skills.
- For SwiftUI implementation or review, use `swiftui-specialist`.
- For every production SwiftUI `View` a task creates or materially changes—including screens, subviews, reusable components, and generic view wrappers—add at least one `#Preview` next to the view. Give it representative deterministic inputs and preview-only fixtures; do not connect previews to live services or persistent user data. If a production view cannot be previewed without violating an architecture boundary, document the specific blocker in the handoff. Test-only view harnesses do not need previews.
- For new or changed iOS 27 SwiftUI APIs, or related SDK 27 compiler errors, use `swiftui-whats-new-27`. Follow this repository's SDK declaration, availability, and focused-compile checks before adopting an API.
- For simulator or device UI evidence, use ProjectAlpha's `.agents/skills/device-interaction` workflow and the Xcode MCP requirements above.
- Use `modernize-tests` when the user requests test modernization or a test task explicitly calls for migrating legacy tests. Do not migrate tests opportunistically; preserve the Swift Testing and critical XCTest UI boundaries above.
- Use `audit-xcode-security-settings` for an explicit Xcode security/build-settings audit. Project configuration changes remain owned by `projectalpha_composition_integrator`; this skill does not expand that ownership.
- `uikit-app-modernization` and `adopt-c-bounds-safety` are not installed because the current iOS implementation is SwiftUI/Swift and contains no UIKit app or C source to modernize. Reassess if that scope changes.

## Agent coordination

- `projectalpha_spec_tracer` maps work to contracts and dependencies; it does not implement.
- `projectalpha_contract_maintainer` updates approved product/architecture contracts and traceability in `README.md`/`docs/**`; no other custom agent edits those files.
- `projectalpha_bug_investigator` establishes reproduction and root cause; it does not fix.
- Production implementers modify only their declared ownership area and do not edit test-target files.
- `projectalpha_acceptance_test_engineer` owns automated test-target changes and does not modify production code.
- `projectalpha_architecture_concurrency_reviewer`, `projectalpha_build_verification_gatekeeper`, and `projectalpha_device_ux_qa` are independent read-only gates.
- The recommended sequence is: spec trace or bug investigation -> owning implementer(s) -> acceptance tests -> architecture/concurrency review -> build gate -> device/UX QA when applicable.
