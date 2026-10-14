# ProjectAlpha agent routing and ownership

[AGENTS.md](../../AGENTS.md) owns shared safety, contracts, clarification, source rules and evidence. Keep all 16 optional specialists; load relevant contract sections and skills on demand. Runtime operators use [runtime-workflows.md](runtime-workflows.md); source-only tasks do not need runtime procedures.

## Choose work by risk

| Task risk | Primary executor and delegation | Verification |
|---|---|---|
| Low: bounded, understood, reversible, behavior-preserving | Main implements, writes a focused regression if warranted and executes checks. Usually zero children. | Relevant diff/static checks, focused tests/compile as appropriate; self-verification is not independent review. |
| Medium: meaningful feature/state/lifecycle work | Main identifies the owning layer; select an implementer, test author or focused reviewer only for useful expertise/independence. | Affected tests, appropriate build and focused semantic review for meaningful state/lifecycle concerns; assigned device cases only. |
| High: identity/invariants, atomicity/migration, concurrency/cancellation, shared state or major architecture | Main coordinates selected owners and separate semantic reviewer/final runner. Independent test design for complex integrity cases. | Relevant full tests/builds, data/migration/concurrency/media failure checks and required device evidence. |

A one-line persistence, identity or cancellation change may be high risk. Escalate routing when investigation exposes such effects. Product/public-contract changes need prior approval under AGENTS.md. Infrastructure-only changes use TOML/Markdown/preservation checks, with no app build or device run.

Do not require a tracer/investigator for already understood work. Use the tracer for substantial contract/dependency mapping, investigator for difficult reproduction/root cause, and specialists for significant technical ownership. Avoid delegation that duplicates loaded context, repeats checks or forces serial handoff without adding expertise. Four children plus primary is a ceiling, not a target; default serial execution.

## Ownership and write leases

Main may assume an owner responsibility for bounded authorized work and perform related edits serially (including a focused test and shared localized key). Delegated specialists keep the ownership/exclusions below and in their TOMLs; production specialists never edit test targets. Substantial Xcode/configuration work belongs to composition. Product-contract changes go to the contract maintainer; infrastructure checkpoints may be maintained by main.

Before delegation, state its independent value and exact files/paths, relevant contract IDs/sections, approved decisions, immutable baseline, dependencies, required evidence and stop condition. Use bounded fresh context where supported; forward full history only for a concrete need. Every writer/reviewer reads the shared core and exact active contracts; a handoff cannot override them.

Reserve explicit file leases, including catalogs, preview fixtures, generated output and configuration. Recheck status/diff on assignment/release. Never overlap writers; settle shared interfaces before dependent implementation. Separate worktrees do not isolate runtime/defaults/helpers and do not automatically include dirty/untracked input. Preserve working-tree baselines without manufacturing a commit.

Exact shared boundaries: scene owns `Presentation/Features/MainTabs/**` and URL grammar/encoding; settings owns preferences/design-system/localization/formatting paths and catalogs; composition owns root/DI/bootstrap/project/release wiring and `Shared/Utilities/**`. Widget owns snapshot/publisher behavior, composition registers it. Library owns the shared Photo Viewer; Domain owns immutable LocationDraft, library owns its mutable editor state. Feature preview fixtures follow the feature owner.

## Discovery and diagnosis

| Agent | Sole responsibility |
|---|---|
| `projectalpha_spec_tracer` | Translate a feature/change into product contracts, owning agents, dependencies, and verification. |
| `projectalpha_bug_investigator` | Reproduce a defect and establish evidence-backed root cause and ownership. |
| `projectalpha_contract_maintainer` | Apply explicitly approved product/architecture changes to README/docs and keep U/D/INV/AC traceability consistent. |

## Production implementation

| Agent | Sole responsibility |
|---|---|
| `projectalpha_composition_integrator` | App composition, bootstrap wiring, Xcode targets/configuration, entitlements, and target membership. |
| `projectalpha_domain_policy_engineer` | Pure Domain values, validation, identity/duplicate policy, use cases, and ports. |
| `projectalpha_swiftdata_library_engineer` | SwiftData schema, LibraryStore, repositories, atomic CRUD, revisions, and observations. |
| `projectalpha_local_media_engineer` | Local media staging, finalization, downsampling, cleanup, reconciliation, and thumbnails. |
| `projectalpha_scene_navigation_engineer` | Per-scene routing, modal ownership, restoration, URL parsing, and external-intent execution. |
| `projectalpha_library_workflow_engineer` | Home, collection/location lists and editors, picker, drafts, and quick-capture UI. |
| `projectalpha_map_location_services_engineer` | Map sessions/UI, search, POI resolution, position, ETA, directions, and map detail. |
| `projectalpha_widget_integration_engineer` | Shared widget snapshot contracts, publisher, AppEntity configuration, and widget UI; it consumes the scene owner's URL encoder. |
| `projectalpha_settings_localization_accessibility_engineer` | Settings, string catalogs, locale/RTL behavior, and locale-aware formatting; feature owners apply accessibility fixes in their own views. |

## Independent quality gates

| Agent | Sole responsibility |
|---|---|
| `projectalpha_acceptance_test_engineer` | Automated tests and test-only fixtures/helpers. |
| `projectalpha_architecture_concurrency_reviewer` | Read-only architecture, correctness, and Swift concurrency review. |
| `projectalpha_build_verification_gatekeeper` | Read-only execution and classification of build/test/whitespace gates. |
| `projectalpha_device_ux_qa` | Read-only device, localization, accessibility, widget, and performance acceptance evidence. |

## Skills and reference loading

- SwiftUI implementation/review: project `swiftui-specialist`, only affected references; `swiftui-whats-new-27` for changed APIs or related compiler errors. Approved Liquid Glass surfaces include contained actions and require `build-ios-apps:swiftui-liquid-glass`.
- UI composition/refactor/performance: relevant Build iOS Apps skill within the assigned view/layer. Examples cannot introduce @Query in Presentation, another router/service owner, live previews or unapproved product changes.
- Widgets: `build-ios-apps:ios-app-intents` only for approved snapshot-based collection configuration; no extra Siri/Shortcuts/Spotlight/control surface.
- Runtime/debug/leak/profile/browser: load the corresponding runtime-workflows sections and project device skill when UI evidence is needed. One operator holds shared resources through cleanup; read-only collectors never instrument or fix production.
- Test modernization and security audit skills activate only for those actual requests. They do not authorize incidental migrations, security settings edits or additional agents.

## Verification and compact handoff

Designate one final runner per source revision. Main runs low-risk and suitable medium checks; build gatekeeper supplies required independent execution. Test-author smoke checks are optional feedback. Reuse successful relevant evidence if source/environment are unchanged; rerun for material edits, failures or unresolved concerns. High-risk semantic review must be separate from implementation/self-review.

Release checks apply to release/project/resource, configuration-sensitive preview changes, large/cross-cutting slices or explicit gates. Widgets require actual extension scope. Adaptive review/device matrix follows assigned ACs; do not turn an isolated view task into whole-app QA. A compile/launch/frame is not proof of accessibility, RTL, input, physical performance/size or Duo behavior. Report affected unavailable evidence BLOCKED.

Return: outcome/scope; AC/INV/D and approved input; files/baseline; key findings/seams; exact checks/results/evidence paths; performance/size impact or unmeasured status; cleanup/next owner; limitations/deviations. Do not paste global rules, full logs or repeated plans. Only primary issues AC/slice verdicts after every applicable current independent gate; low-risk main-only work cannot be described as independent acceptance.

Permissions come from the parent session. Repository-read-only roles are behavioral restrictions, not isolated per-agent sandboxes. No role/model/default configuration change is implied by this guide.
