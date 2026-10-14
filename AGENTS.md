# ProjectAlpha agent instructions

These instructions govern every task in this repository, including work delegated to custom agents under `.codex/agents/`.

## Authority and current state

- For application work, read the relevant current guidance in `README.md` and `docs/README.md` once, then the task-specific contract sections below. Infrastructure-only work does not require unrelated product or Swift source reading.
- Treat `docs/01-product-and-decisions.md` through `docs/09-apple-technology-references.md` as the approved target product and architecture contract.
- Treat the checked-out source, `ios/ProjectAlpha/ProjectAlpha.xcodeproj/project.pbxproj`, and `docs/10-scaffold-architecture-verification.md` as the authority for the scaffold's current implementation state.
- The source currently confirms that app and test targets use Swift 6 and target iPhone/iPad device families (`1,2`). Do not regress either setting; recheck source/project settings before changing current-state documentation.
- If documents disagree about user-visible behavior, data identity, feature scope, or an invariant, stop and ask the product owner. Do not silently select a contract.
- `U-*` entries are confirmed product decisions, `D-*` entries are engineering decisions, `INV-*` entries are invariants, `AC-*` entries are acceptance criteria, and `FUTURE` is explicitly out of current scope.

## Risk-based clarification

- Ask before an unapproved change to product behavior/UX requirements, Domain invariants, data identity or persistence semantics, SwiftData migrations, public/cross-module contracts, external dependencies, destructive operations, or major architecture. Existing explicit approval covers the named scope; do not request it again.
- Contradictory approved contracts block the affected choice. Do not invent a product default or expand scope. Read-only investigation and unaffected work may continue while awaiting the owner; record approved answers in the handoff. Approved product-contract edits belong to `projectalpha_contract_maintainer`.
- Proceed autonomously with internal naming, small implementation decisions, behavior-preserving refactors, test organization, equivalent technical implementations, and minor non-breaking organization. Record a material assumption briefly for review.
- Investigate API facts and ownership through read-only evidence before asking. Never guess an unsupported API, fabricate a Swift creation date, silently alter the deployment target, or claim unavailable evidence. If an equivalent implementation would change approved behavior, ask; if required evidence cannot be produced, report that case `BLOCKED` without blocking unrelated work.

## Selective context and task routing

Main handles clear low-risk work directly, including focused tests and verification; self-checks are not independent review. One-line persistence, identity, cancellation, concurrency or invariant changes may be high risk.

Read relevant sections once, with enough context to detect conflicts: docs 01 decisions/exclusions, 03 affected layer/lifetimes, 04 affected data/invariants, 08 assigned P/AC dependencies/evidence. Do not load the whole index or historical records for every task. Additional reading:

- CRUD: 02 journeys, 04 data/duplicates.
- Navigation/restoration/intents: 05; 07 for widget intents.
- Maps/search/detail/position/ETA/directions/share: affected 02, 05, 06, 09 sections.
- Widgets: 04 snapshot boundary, 05 URLs, 07, relevant 09.
- Persistence/concurrency/media: affected 03, 04, 08 sections.
- Settings/localization/accessibility/release: relevant 01, 02, 08, 09 sections.
- Current scaffold/project claims: 10 and relevant source/settings.
- UI/API adoption: relevant Apple guidance plus installed declaration/availability and focused compile.
- Infrastructure only: approved request and exact affected policy/skill files; no unrelated app contracts/source.

Use the [routing guide](.codex/agents/README.md) to select specialists for meaningful expertise, substantial work or required independence. Handoffs give exact paths/sections, IDs, approved decisions, baseline, leases, dependencies and verification; prefer bounded fresh context unless history is necessary. Tracer/investigator activation is conditional.

For build/run/test/UI/log/debug operations, use Build iOS Apps `xcodebuildmcp` skills/tools first and load applicable [runtime workflows](.codex/agents/runtime-workflows.md); UI/device evidence also uses project `device-interaction`. Apple's `xcode` MCP (`xcrun mcpbridge`) supplies required unsupported capabilities after a recorded gap and clean handoff. Artifacts stay outside the repository; unavailable evidence is `BLOCKED` for that case.

## Working-tree safety

- Start and finish with `git status --short --branch --untracked-files=all`.
- The current `ios/` tree may be untracked. Untracked does not mean disposable. Preserve it and all staged, unstaged, generated, or unrelated user work.
- Before any write-capable agent edits an untracked file, the orchestrator must provide an immutable baseline: either a tracked/staged Git baseline explicitly established by the owner, or a task-specific snapshot outside the repository with file inventory and checksums. Record the baseline identity/path in every writer and reviewer assignment. If no such baseline exists, the write task is `BLOCKED`; never run `git add` or commit merely to manufacture one without owner authorization.
- When reviewing untracked work, compare against that recorded snapshot (or an owner-provided patch). A plain `git diff` is not change attribution for untracked files.
- Never reset, replace, delete, or broadly reformat files outside the assigned scope.
- Hold explicit file write leases, including catalogs, previews, generated files and project settings. Never overlap writers. Read-only exploration/reviews may overlap; shared builds, runtimes, defaults and helpers also require exclusive resource reservations under runtime workflows.
- Among delegated agents, only `projectalpha_composition_integrator` may edit `project.pbxproj`, target membership, generated Info settings, entitlements, bundle identifiers, URL registration, or signing-related project configuration. Other delegated agents must hand those changes off. The main agent may assume an owner responsibility for bounded authorized work, serially under the same safeguards; substantial project/configuration work goes to composition.
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
4. Make the smallest coherent change. Delegated writers stay inside their ownership/lease and hand off cross-owner files; main may assume bounded owner responsibilities serially without widening approved scope.
5. Keep deterministic seams for clocks, IDs, provider requests, permission states, media files, and failures. Never depend on live Apple search in automated tests or wall-clock sleeps for correctness.
6. Select verification by risk below. Designate one final runner per source revision; reuse relevant unchanged evidence. A successful build alone does not satisfy an acceptance criterion.
7. Update product decisions and acceptance criteria together only when the product owner approved a behavior/scope change. A normal bug fix should not rewrite the specification.

## Risk-based verification and reporting

| Risk | Verification |
|---|---|
| Low | Relevant diff/static checks; focused tests/compile when appropriate. Main may execute. Avoid tests that mirror cosmetic implementation. |
| Medium | Affected tests, appropriate build and focused semantic review for meaningful state/lifecycle risks. Delegate when valuable or required by an AC. |
| High | Relevant full tests/builds; independent semantic review and final execution; affected integrity/migration/concurrency/media checks; required device evidence. Independent test design for complex integrity cases. |

- Swift Testing covers Domain, presentation models/coordinators and integration. Preserve critical XCTest UI/UIKit lifecycle and XCTest performance exceptions. Store tests use in-memory SwiftData with actual save/reload/rollback/concurrent attempts; media uses isolated temporary directories; providers/permissions/clocks use deterministic fakes.
- Runtime checks discover an installed iOS 27 destination, isolate DerivedData/results under `/tmp`, and use `CODE_SIGNING_ALLOWED=NO` for simulators, with runtime reservations and recorded plugin-first fallbacks.
- Full suite/Release/widget/adaptive/device gates depend on impact and assigned ACs. Release applies to release/project/resource, configuration-sensitive preview changes, large/cross-cutting slices or explicit gates; widgets require extension scope. Policy-only edits need no app build/device session.
- AC-57–60 retains required iPhone portrait/landscape, iPad full/half/third/quadrant/floating minimum-to-maximum widths, keyboard/pointer/accessibility and Duo display/pose/multitasking evidence. Run the assigned AC matrix; missing Xcode 27.1 Device Hub/runtime blocks Duo. Ordinary simulators/source inspection cannot substitute. Physical performance/size and participant gates remain in doc 08.
- Run `git diff --check`; directly check edited untracked files against the baseline. Classify product vs service/simulator/sandbox/signing/environment failures. Never claim unexecuted device/accessibility/RTL/widget/performance/participant evidence.
- One final runner per revision: main for low/appropriate medium risk; build gatekeeper for required independence. Test-author affected-test feedback is optional, not another full/UI run. Reuse unchanged relevant evidence; rerun for material edits, failures or unresolved concerns. Independent reviewer owns required semantic adaptive/concurrency review.
- Completion/handoff states scope, AC/INV/D, files/baseline, exact tools/commands/results, manual checks, performance/size impact (measured or unverified), limitations and approved deviations. Link logs; keep summaries compact.
- Only primary declares AC/slice `READY`/`PASSED` after all applicable current independent gates. Main-only low-risk completion is not independent acceptance; report `implementation complete; independent verification pending` when required gates remain.

## Project skill routing

- Project skills live under `.agents/skills/`. Load the relevant `SKILL.md` and its referenced material when the task matches; all agents working in this repository can use these skills.
- Build iOS Apps complements these skills within existing agent ownership. Select only task-relevant skills from the routing guide; runtime operators read the applicable sections of `.codex/agents/runtime-workflows.md`. Plugin examples do not authorize architecture/product changes, cross-owner edits, new system surfaces, instrumentation dependencies, or a competing final gate.
- For SwiftUI implementation or review, use `swiftui-specialist`.
- When an approved product or feature contract calls for Liquid Glass, load `build-ios-apps:swiftui-liquid-glass` for every applicable SwiftUI surface, including cards and their contained actions; do not limit it to standard controls. Read the feature contract to identify the required glass surfaces, compact control treatment, and Reduce Transparency fallback before implementation.
- For every production SwiftUI `View` a task creates or materially changes—including screens, subviews, reusable components, and generic view wrappers—add at least one `#Preview` next to the view. Give it representative deterministic inputs and preview-only fixtures; do not connect previews to live services or persistent user data. If a production view cannot be previewed without violating an architecture boundary, document the specific blocker in the handoff. Test-only view harnesses do not need previews.
- Keep `#Preview` declarations and their deterministic fixture types available in every build configuration. SwiftUI preview macros do not affect the released app at runtime, so do not surround them or their fixtures with `#if DEBUG`. Keep preview fixtures free of live services and persistent user data.
- For new or changed iOS 27 SwiftUI APIs, or related SDK 27 compiler errors, use `swiftui-whats-new-27`. Follow this repository's SDK declaration, availability, and focused-compile checks before adopting an API.
- For simulator or device UI evidence, use ProjectAlpha's `.agents/skills/device-interaction` workflow and the plugin-first MCP requirements above.
- Use `modernize-tests` when the user requests test modernization or a test task explicitly calls for migrating legacy tests. Do not migrate tests opportunistically; preserve the Swift Testing and critical XCTest UI boundaries above.
- Use `audit-xcode-security-settings` for an explicit Xcode security/build-settings audit. Project configuration changes remain owned by `projectalpha_composition_integrator`; this skill does not expand that ownership.
- `uikit-app-modernization` and `adopt-c-bounds-safety` are not installed because the current iOS implementation is SwiftUI/Swift and contains no UIKit app or C source to modernize. Reassess if that scope changes.

## Agent coordination

- Retain all 16 specialists. Main-agent-first low-risk execution is an exception to delegated role separation, not a transfer of specialist file ownership. Main may implement and author focused tests serially, including related feature key/catalog edits; never label its own review independent.
- Delegated production writers stay within their leased ownership and do not edit test targets. The acceptance-test engineer changes only tests. Composition is the delegated project/configuration writer. The contract maintainer alone among custom agents changes approved product/architecture contracts in README/docs; main may maintain infrastructure checkpoints without changing product contracts.
- Tracer maps substantial contract/dependency questions; investigator diagnoses difficult defects without fixing. Reviewer, final gatekeeper and device QA stay repository-read-only. Parent-session permissions govern tools; behavioral read-only rules do not create an independent sandbox.
- Medium work uses selected specialists when valuable. High-risk work requires separate semantic review and final execution; main coordinates dependencies and gates. Device QA is conditional on required manual/device evidence. No fixed all-agent pipeline; a role's existence is not a reason to spawn it.
