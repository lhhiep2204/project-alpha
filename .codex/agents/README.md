# ProjectAlpha custom agents

These project-scoped agents follow the repository `AGENTS.md` and the approved design in `docs/`.

## Xcode MCP access

The project config declares the `xcode` MCP server as `xcrun mcpbridge`. It is explicitly attached to the agents that need simulator/Xcode evidence: `projectalpha_bug_investigator`, `projectalpha_composition_integrator`, `projectalpha_scene_navigation_engineer`, `projectalpha_library_workflow_engineer`, `projectalpha_map_location_services_engineer`, `projectalpha_widget_integration_engineer`, `projectalpha_settings_localization_accessibility_engineer`, `projectalpha_acceptance_test_engineer`, `projectalpha_build_verification_gatekeeper`, and `projectalpha_device_ux_qa`.

Those agents must discover the scheme and installed simulator, build/install/launch as needed, inspect the UI/accessibility tree, capture screenshots/logs, and re-read UI state after interactions. If the Xcode MCP server is unavailable in the current host/session, they must report `BLOCKED` and cannot claim simulator or device verification.

### Xcode MCP runbook

1. Confirm the selected Xcode instance, project/workspace, scheme, and an installed iOS 27 simulator.
2. Build/install/launch the relevant target through Xcode MCP or the paired build command; keep artifacts in a unique temporary directory.
3. Capture a baseline UI tree/screenshot before interacting. Prefer accessibility identifiers/labels over coordinates.
4. Re-read the tree after every navigation, tap, text entry, scroll, deep-link, or widget action; capture logs/crash output when relevant.
5. Compare actual behavior to the assigned AC and report exact simulator/device/runtime, evidence paths, and any blocked capability. A screenshot or UI tree is evidence, not an automatic pass.

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

## Recommended workflows

- New feature: `projectalpha_spec_tracer` -> relevant production owner(s) in dependency order -> `projectalpha_acceptance_test_engineer` -> `projectalpha_architecture_concurrency_reviewer` -> `projectalpha_build_verification_gatekeeper` -> `projectalpha_device_ux_qa` when the AC requires device evidence.
- Bug: `projectalpha_bug_investigator` -> owning production agent -> `projectalpha_acceptance_test_engineer` -> both independent review/build gates.
- Approved contract change: `projectalpha_spec_tracer` identifies the exact U/D/INV/AC impact; after product-owner approval, `projectalpha_contract_maintainer` updates only README/docs.
- Cross-cutting work: let `projectalpha_spec_tracer` split the work. Do not run two write-capable agents against the same files at the same time.
- A production agent must hand Xcode project, entitlement, or target-membership edits to `projectalpha_composition_integrator`.

Custom-agent format follows the official OpenAI Codex project-agent convention: one TOML file per agent under `.codex/agents/`.
