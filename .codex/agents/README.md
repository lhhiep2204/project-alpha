# ProjectAlpha custom agents

These project-scoped agents follow the repository `AGENTS.md` and the approved design in `docs/`. They are optional specialists; a request must not automatically run every agent or every gate.

## Routing and token policy

The primary agent performs a lightweight risk triage first: docs/read-only, small bug, Domain/Data, UI/navigation, or cross-cutting/release. Use `projectalpha_spec_tracer` only for new cross-cutting work, unclear requirements, or work spanning multiple ownership areas. A clear, narrow request can go directly to its owner.

`AGENTS.md` is the source of truth for clarification, ownership, working-tree safety, architecture, and evidence rules. Do not repeat those rules in every handoff. Never run two write-capable agents against the same file at the same time. Subagents consume additional tokens, so each one gets a narrow scope and returns a concise evidence summary rather than raw logs.

Every owner applies the `AGENTS.md` performance and app-size priority to its slice. Handoffs state the expected impact on startup, interaction smoothness, memory, storage, and bundled size as relevant, plus actual measurements or the remaining evidence needed. Architecture review checks avoidable work and unbounded resource use; build/release gates record size changes; device QA measures responsiveness on the documented physical-device workload. Do not label estimates as measured results.

## Adaptive Apple UI/UX ownership

- Scene navigation owns the adaptive tab/sidebar and stack/split route shell.
- Feature owners own adaptive rendering inside their existing boundaries; composition owns only wiring.
- Architecture review checks semantic state continuity and anti-patterns; device QA owns actual resize, input, accessibility, and Duo evidence.
- Follow the adaptive contract in `AGENTS.md`. Xcode 27.1/Duo limitations remain `BLOCKED`; never substitute an ordinary simulator or invent an API.

## Xcode MCP access

The project-level `xcode` MCP server is declared in `.codex/config.toml`; custom agents inherit it. Keep the detailed simulator/device runbook in `.agents/skills/device-interaction/SKILL.md`. If the server or required runtime is unavailable, report `BLOCKED` and do not claim device evidence.

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

## Risk-based workflows

- Docs/read-only: primary agent only, or `projectalpha_contract_maintainer` after explicit product-owner approval; run documentation checks only.
- Small clear bug: owner -> affected regression test -> final build gate. Use `projectalpha_bug_investigator` only when reproduction/root cause is uncertain. Add architecture review for concurrency, persistence, routing, or invariant risk.
- Domain/Data/Persistence: owner -> affected tests -> architecture review when atomicity, concurrency, identity, or lifecycle is involved -> final build gate. No device QA.
- UI/navigation: feature owner -> model/UI tests -> architecture review when state/routing/lifecycle is involved -> final build gate -> device QA only when the AC requires manual/device evidence.
- New cross-cutting or release/widget work: `projectalpha_spec_tracer` -> non-overlapping production owners -> acceptance-test author -> architecture review -> final build gate -> device QA only for applicable ACs.

Production agents provide the smallest deterministic test matrix and may run a focused smoke check; they do not run the full suite by default. The acceptance-test agent authors/updates tests and may run only newly affected tests to catch authoring errors; it does not run the full suite or final UI matrix. The build gate is the single authoritative final runner. Adaptive source review belongs to the architecture reviewer, while device UX QA owns actual manual/device evidence.

A production agent must hand Xcode project, entitlement, or target-membership edits to `projectalpha_composition_integrator`.

Custom-agent format follows the official OpenAI Codex project-agent convention: one TOML file per agent under `.codex/agents/`.

SwiftUI owners keep `#Preview` and deterministic preview fixtures available in every build configuration, without `#if DEBUG` wrappers. The build gate checks Release compilation and flags preview-only conditional compilation that hides broken fixtures.
