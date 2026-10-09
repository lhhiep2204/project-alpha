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

For every implementation slice, read `docs/README.md`, docs 01, 03, 04, 08, and the exact feature documents needed for the requested slice. Do not read unrelated feature documents or the full specification set for every task.

- Ambiguous, cross-cutting, or new product work: `projectalpha_spec_tracer` reads docs 01, 03, 04, 08, and 10 plus relevant feature documents, then gives downstream agents the exact contract IDs and reading set.
- Collection/location CRUD: docs 02 and 04.
- Navigation, restoration, or external intents: docs 05 and 07.
- Maps, search, location detail, position, ETA, directions, or sharing: docs 02, 05, 06, and 09.
- Widgets: docs 04, 05, 07, and 09.
- Persistence, concurrency, or media: docs 03, 04, and 08.
- Settings, localization, accessibility, or release configuration: docs 01, 02, 08, and 09.
- Current scaffold or project-setting claims: docs 10 plus the relevant source/project settings.
- UI/API adoption: read current Apple guidance and verify the declaration/availability only when the task uses that API or acceptance evidence.

Build iOS Apps supplies `xcodebuildmcp`; use its skills and exposed MCP tools first for supported build, run, test, simulator UI, logs, and debugging. Custom agents coordinate ownership, sequencing, and evidence. The separate project-scoped Apple `xcode` server is `xcrun mcpbridge`; use it for required capabilities the plugin tools do not support, recording the gap and backend handoff. Follow `.codex/agents/README.md` and project `device-interaction` for UI/device evidence. If the required operation/evidence is unavailable, report `BLOCKED`; do not claim UI/device evidence. Keep screenshots, logs, result bundles, and traces outside the repository.

## Working-tree safety

- Start and finish with `git status --short --branch --untracked-files=all`.
- The current `ios/` tree may be untracked. Untracked does not mean disposable. Preserve it and all staged, unstaged, generated, or unrelated user work.
- Before any write-capable agent edits an untracked file, the orchestrator must provide an immutable baseline: either a tracked/staged Git baseline explicitly established by the owner, or a task-specific snapshot outside the repository with file inventory and checksums. Record the baseline identity/path in every writer and reviewer assignment. If no such baseline exists, the write task is `BLOCKED`; never run `git add` or commit merely to manufacture one without owner authorization.
- When reviewing untracked work, compare against that recorded snapshot (or an owner-provided patch). A plain `git diff` is not change attribution for untracked files.
- Never reset, replace, delete, or broadly reformat files outside the assigned scope.
- Do not edit a file concurrently with another write-capable agent. Parallelize read-only exploration, test execution, or reviews; serialize overlapping edits.
- Only `projectalpha_composition_integrator` may edit `project.pbxproj`, target membership, generated Info settings, entitlements, bundle identifiers, URL registration, or signing-related project configuration. Other agents must hand those changes off.
- Exact shared ownership: scene navigation owns `Presentation/Features/MainTabs/**`; settings/localization owns `Shared/Preferences/**`, `Data/Preferences/**`, `Presentation/Preferences/**`, `Presentation/DesignSystem/**`, `Presentation/Localization/**`, and `Presentation/Formatting/**`; composition owns app/release assets and `Shared/Utilities/**`. Feature-specific preview fixtures belong to that feature owner.

## Swift file headers

- Every `.swift` file created or edited in this repository must have the standard file header at the top, before imports or declarations. Use this format and substitute the file name and its original creation date:
  ```swift
  //
  //  <FileName>.swift
  //  ProjectAlpha
  //
  //  Created by Hoàng Hiệp Lê on <d/M/yy>.
  //
  ```
- For a new `.swift` file, use the date it is created. When editing an existing `.swift` file, preserve its existing header and creation date. If it has no header, add one using the file's original creation date, verifying that date from reliable history or metadata; if the date cannot be verified, stop and ask the owner rather than guessing.
- This header requirement applies only to `.swift` files. Do not add comment headers to other file formats.

## Architecture boundaries

- Put every source-code string value behind a descriptively named constant or typed enum case before using it. This includes localized UI copy, accessibility identifiers, SF Symbol/asset names, UserDefaults and Info.plist keys, locale IDs, file/path tokens, URL components, log text, format strings, previews, and test fixtures. A literal belongs at its constant or enum-case declaration; do not pass or compare an unexplained string literal directly at a call site. Keep constants in the owning layer/feature, preserve persisted keys and raw values exactly, and keep user-visible localized keys in the appropriate `CommonKeys`, feature keys, or `SettingsKeys` group. Ensure catalog coverage for keys used by shipping views. Compose dynamic strings from named constants or formats. Do not move Domain strings into Presentation or add a cross-layer global string bucket.
- Domain owns immutable Foundation values, validation, policies, use cases, and ports. It must not import SwiftUI, MapKit, CoreLocation, SwiftData, contain localized UI strings, or depend on app preferences.
- Data owns SwiftData models/mappers/store, repository implementations, Apple service adapters, and media persistence. It must not own routes, tabs, sheets, or UI copy.
- Presentation owns `@MainActor` observable state, drafts, routing requests, SwiftUI, map rendering, formatting, and localization. It must not mutate SwiftData or files directly or reimplement business identity rules.
- App owns manual dependency injection, shared service lifetime, bootstrap, scene lifecycle, and integration wiring. It must not hide business validation in factories.
- Shared extension contracts contain only versioned Foundation DTOs and URL/snapshot encoding. Widgets must not import the app container or open the live SwiftData store.
- Keep one app-owned persistence writer, one app-owned preferences owner, a `SceneCoordinator` per scene, and state per map session. Collection Map scope and save destination are independent concepts.
- Factories and initializers must be cheap and side-effect-free. Start and cancel observation through structured lifecycle tasks or explicit start/stop methods.
- Preserve Swift 6 isolation. Do not use `@unchecked Sendable`, `nonisolated(unsafe)`, detached work, or global mutable state to hide an ownership or concurrency error.

## Performance and app size priority (U-31, D-20, AC-65/66)

- Fast response, smooth interaction, and a small app footprint are first-order product requirements for every slice, including app, widget, and supporting assets. Each agent must consider startup, main-thread work, scrolling/map interaction, memory, disk use, and binary/resource size within its ownership before declaring its work complete.
- Keep expensive persistence queries, image decoding/downsampling, snapshot generation, and other heavy work away from the UI actor where the owning API permits. Load only data and media needed for the visible task, bound caches and concurrent work, cancel work that is no longer needed, and avoid duplicate observations or repeated computation during view updates. Preserve correctness, accessibility, and the approved behavior while optimizing.
- Add dependencies, bundled assets, persisted copies, caches, or background work only when justified by a concrete feature need and their size/runtime cost. Prefer existing Apple frameworks and shared assets. Do not add an optimization that creates stale data, lost work, or a hidden correctness tradeoff.
- For a change likely to affect responsiveness, memory, launch, or footprint, state the expected impact and the measurement needed in the handoff. Record device, OS, build configuration, dataset, metric, baseline, and result when measured; report an unmeasured target as unverified. AC-65/66 and the physical-device workload and provisional latency targets are in document 08. Record app/archive and installed-size changes at release gates; no numeric size budget has been approved.

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
- Every collection uses the Folder symbol. Collection icon selection and collection cover photos are outside the product and data model; location photos remain in scope.
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
6. Run the smallest affected verification, then let the final build gate run the applicable broader checks once. A successful build alone does not satisfy an acceptance criterion.
7. Update product decisions and acceptance criteria together only when the product owner approved a behavior/scope change. A normal bug fix should not rewrite the specification.

## Verification and reporting

- Use Swift Testing for Domain, presentation-model/coordinator, and integration tests. Use XCTest UI only for critical end-to-end or UIKit lifecycle behavior.
- Store tests use in-memory SwiftData but verify real save/reload/rollback/concurrency behavior. Media tests use isolated temporary directories. Provider and permission tests use deterministic fakes.
- Select an actually installed iOS 27 simulator; do not hard-code an old simulator UUID. Use an isolated DerivedData path under `/tmp` and `CODE_SIGNING_ALLOWED=NO` for simulator verification.
- Adaptive UI verification must exercise iPhone portrait/landscape, iPad full/half/third/quadrant/floating minimum-to-maximum widths, keyboard and pointer input, accessibility configurations, and iPhone Duo outer/inner/open/closed/partially folded and multitasking configurations when the required Xcode 27.1 Device Hub/runtime is available. If it is unavailable, report `BLOCKED` for those cases and do not substitute source inspection or an ordinary iPhone/iPad simulator as Duo evidence.
- Distinguish product failures from simulator service, sandbox, signing, or environment failures.
- Run `git diff --check`; when source is untracked, also inspect those files because Git diff does not cover them.
- Never claim device, accessibility, RTL, widget, performance, or participant testing unless it was actually run in the required environment.
- Include performance and size impact in each implementation handoff, even when the impact is expected to be negligible. Reviewers and gates check for avoidable main-thread stalls, unbounded work/caches, unnecessary resources, and measured regressions within their assigned evidence scope.
- Every completion report must state: assigned scope, affected AC/INV/D identifiers, changed files, exact commands and results, manual checks, remaining limitations, and any approved deviation.
- Implementers may report `implementation complete; independent verification pending`. Only the primary orchestrator may declare an AC or slice `READY`/`PASSED`, and only after every applicable independent test, review, build, and device gate has reported current evidence.
- The acceptance-test engineer authors/updates tests and may run only newly affected tests for fast feedback; it does not run the full suite or final UI matrix. The build-verification gatekeeper is the single authoritative final test/build runner.
- Run the full test suite, Release build, widget build, adaptive source audit, or device QA only when the changed slice or assigned AC requires it. Architecture review owns semantic adaptive/concurrency review; the build gate owns final execution and mechanical checks.

## Project skill routing

- Project skills live under `.agents/skills/`. Load the relevant `SKILL.md` and its referenced material when the task matches; all agents working in this repository can use these skills.
- Build iOS Apps complements these skills within existing agent ownership. Before using it, read the shared skill-routing, tools/evidence, and session/handoff protocol in `.codex/agents/README.md`; load only task-relevant plugin skills. Plugin examples do not authorize architecture/product changes, cross-owner edits, new system surfaces, instrumentation dependencies, or a competing final gate.
- For SwiftUI implementation or review, use `swiftui-specialist`.
- For every production SwiftUI `View` a task creates or materially changes—including screens, subviews, reusable components, and generic view wrappers—add at least one `#Preview` next to the view. Give it representative deterministic inputs and preview-only fixtures; do not connect previews to live services or persistent user data. If a production view cannot be previewed without violating an architecture boundary, document the specific blocker in the handoff. Test-only view harnesses do not need previews.
- Keep `#Preview` declarations and their deterministic fixture types available in every build configuration. SwiftUI preview macros do not affect the released app at runtime, so do not surround them or their fixtures with `#if DEBUG`. Keep preview fixtures free of live services and persistent user data.
- For new or changed iOS 27 SwiftUI APIs, or related SDK 27 compiler errors, use `swiftui-whats-new-27`. Follow this repository's SDK declaration, availability, and focused-compile checks before adopting an API.
- For simulator or device UI evidence, use ProjectAlpha's `.agents/skills/device-interaction` workflow and the plugin-first MCP requirements above.
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
- The default sequence is risk-based: triage -> owning implementer -> affected tests -> final build gate. Add spec tracing for ambiguous/cross-cutting work, architecture review for high-risk state/concurrency changes, and device QA only when the assigned AC requires manual/device evidence.
