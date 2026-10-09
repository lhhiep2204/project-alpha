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

## Build iOS Apps coordination

The installed Build iOS Apps plugin provides reusable skills and a separate `xcodebuildmcp` server. Custom agents retain their existing ownership; skills provide methods within that ownership. Read this section before using plugin workflows. Select skills by the actual task, and load only the relevant references. Pure Domain/persistence work need not invoke a UI skill.

Resolve instructions in this order: applicable system/developer and explicit user instructions, repository `AGENTS.md` and approved product contracts, the assigned role/file scope, project SwiftUI/SDK guidance, then compatible plugin methods/examples. A plugin example does not approve a product/architecture change. When a real choice or contradiction remains unresolved, follow the repository clarification gate and ask the product owner before the affected action.

### Skill routing

Names below are selected from the active catalog as `build-ios-apps:<skill>`. Resolve the installed skill path there; do not pin a user-specific plugin-cache path or copy the plugin into the repository. If a required skill/tool is missing, report that operation `BLOCKED`; continue only independent work.

| Plugin skill | Task trigger | Owner / evidence boundary |
|---|---|---|
| `swiftui-ui-patterns` | Screen, form, list, navigation or control composition | Assigned UI owner; scene owns routing, composition owns root wiring. Load project `swiftui-specialist` and relevant `swiftui-whats-new-27` references. |
| `swiftui-view-refactor` | Requested structural refactor or required extraction in an assigned view | Existing view owner; preserve Presentation models, injection, lifecycle and behavior. Reviewer checks the result without editing. |
| `swiftui-liquid-glass` | Implement/review an approved Liquid Glass surface | Owning feature; shared design-system/toast belongs to settings. Verify the installed SDK and accessibility behavior. |
| `swiftui-performance-audit` | SwiftUI responsiveness symptom or material rendering risk | Investigator diagnoses; reviewer audits; production owner fixes; QA supplies runtime measurements when required. |
| `ios-app-intents` | P-08 collection entity/query/widget configuration | Widget owner only within approved snapshot/configuration scope; scene supplies URLs and composition supplies target/App Group wiring. |
| `ios-debugger-agent` | Assigned simulator runtime reproduction/debugging | Investigator/QA operates runtime diagnostics/UI; the build gate operates final build/tests. All use plugin tools within one session protocol. |
| `ios-memgraph-leaks` | Concrete retained-object/leak or memory-growth investigation | One investigator/QA collector captures; reviewer can analyze supplied evidence; production owner fixes. |
| `ios-ettrace-performance` | Focused simulator CPU/launch/runtime profile with authorized instrumentation | Composition owns temporary wiring in an isolated task copy; one investigator/QA collector captures and analyzes. Simulator evidence is diagnostic. |
| `ios-simulator-browser` | User requests a browser simulator mirror or package-backed preview | One assigned investigator/QA operator; mirror the discovered UDID and verify a rendered frame. Package preview requires an existing importable Swift package. |

### Adapt plugin examples to ProjectAlpha

- The MV-first and `@Query` examples in `swiftui-view-refactor` are not an instruction to remove injected Presentation models, introduce SwiftData in views, or replace app-owned services. Keep Domain/Data/Presentation/App boundaries and existing cheap model initialization/lifecycle ownership.
- Navigation, sheets and App Intents examples must use the existing per-scene coordinator and the scene owner's URL encoder. Sheet dismissal participates in dirty-draft protection and real coordinator acknowledgement. Do not add a second router, route path, modal owner, or app-global service owner.
- App Intents support is limited to approved widget configuration. Generic AppShortcutsProvider/Siri/Spotlight/control suggestions do not expand v1 scope or authorize a new target.
- Literal strings, live-service examples and preview fixtures in plugin snippets must be adapted to repository constants/localization, deterministic inputs and owning-layer rules. Every materially changed production View retains a nearby `#Preview` in all build configurations.
- Liquid Glass guidance uses ProjectAlpha's verified deployment target; do not add dead earlier-OS branches merely to copy a snippet. Preserve real Reduce Transparency/Motion and accessibility fallbacks. New symbols still require declaration/availability checks and a focused compile.
- Runtime/evidence roles remain read-only even when a skill says to patch a leak, refactor code, or link a framework. Route that step to the declared writer and verify against the task baseline.
- ETTrace requires explicit authorization for temporary third-party instrumentation before downloads, host installation or linking. Composition works in an isolated, checksummed task copy outside the repository, owns all project/Info/embedding edits and removal, and returns restoration evidence. No instrumentation enters shipping builds. The primary orders preparation/build before capture; do not ask a read-only collector to modify project files. If this setup is not approved, report the ETTrace step blocked and use available read-only evidence.
- Browser mirroring is optional and starts only for a requested browser workflow. Keep helper artifacts outside the repository, clean up only the assigned UDID/helper, and do not leave watchers running. ProjectAlpha is currently an Xcode app with no `Package.swift`; package-preview hot reload is unavailable unless that prerequisite changes under an approved task. Never restructure the project or edit build settings to force support.

### Tools and evidence

The project `xcode` server is Apple's Xcode MCP (`xcrun mcpbridge`), distinct from the plugin's XcodeBuildMCP server. Both are inherited when enabled and exposed to the session; verify actual availability rather than assuming inheritance succeeded. Do not add duplicate project/per-agent servers or override plugin permissions/model settings for this integration.

Use Build iOS Apps skills/tools first for supported build, run, test, simulator UI, logs and debugging operations. Custom agents coordinate scope, ownership, sequencing and evidence; they use the plugin's callable MCP tools to perform those steps rather than maintain a competing implementation of the workflow. The plugin is a skill/tool package, not an independently running replacement for a custom agent.

Use Apple `xcode` MCP only for a required operation the exposed plugin tools do not support (for example, first-party Xcode workspace/SDK evidence or a specific Device Hub/device-session capability). Record the capability gap, selected backend and reason before switching, transfer the runtime/session cleanly, and load project `device-interaction` for UI/device work through either backend. A temporary failure is not evidence of unsupported functionality: diagnose/report it rather than silently bypassing the plugin. If no available backend can produce the required evidence, that case is `BLOCKED`.

- The final build gate uses compatible plugin build/test tools first and records the exact tool/command, source/baseline identity, selected destination, build configuration, isolated `/tmp` DerivedData/result bundle and signing override. Plugin smoke builds/profiles are not a second final verdict. Use `CODE_SIGNING_ALLOWED=NO` for simulator verification; use `xcodebuild` for reproducible final gates when needed for destinations/flags/result bundles the MCP workflow cannot express.
- Read the current tool metadata before calling it. Static skill examples may name `describe_ui` or log tools that the active server no longer exposes; use only actual compatible tools/schemas, not guessed aliases. `session_show_defaults` is required before the first XcodeBuildMCP build/run/test in each agent session. Validate the project/workspace, scheme and discovered eligible iOS 27 simulator; set missing/wrong defaults only while owning the session. Preserve the required runtime/configuration rather than blindly copying `useLatestOS` from an example. Use ephemeral defaults (`persist: false`) and a task-specific profile when supported; never create `.xcodebuildmcp/config.yaml` or persist machine-local UDIDs as a side effect. Tool mechanics do not bypass project scope or evidence rules. Build-only/test-only assignments use the corresponding tools; a generic tool instruction to build-and-run is applied only to a requested run workflow, not a policy audit or compile-only gate.
- Simulator traces, memgraphs, browser frames and source inspection retain their own proof limits. They cannot replace AC-65 physical-device measurements, AC-66 installed-size measurements, required accessibility/input interactions or Xcode 27.1/Duo evidence. A new build/source change requires current evidence for the applicable gates.

### Session and handoff protocol

The primary assigns one operator at a time for a simulator/device and one mutating operation at a time for a shared Xcode workspace, XcodeBuildMCP defaults, debugger attachment or profiling helper. Isolated DerivedData alone does not isolate shared runtime/defaults. Reserve the active XcodeBuildMCP session/defaults profile for the entire assigned runtime workflow, including capture and cleanup; another operator must not switch that active profile mid-flow. ETTrace uses a fixed host-side localhost port: reserve it for the entire trace lifecycle and run only one ETTrace-instrumented simulator app on that host at a time, even when UDIDs differ. Do not run build/install/launch/UI automation, XCTest UI, LLDB, memgraph/ETTrace capture or browser driving concurrently against the same runtime. Read-only source reviews can run in parallel.

Before runtime work, the primary handoff names the operator, purpose (diagnostic or acceptance), backend, workspace/project, scheme, discovered UDID/runtime, source/checksum baseline, exact app/build artifact, evidence directory, requested ACs/flow and cleanup responsibility. Discover any missing identifier through read-only tooling; ask when the assignment/ownership or required evidence is unclear.

End log capture/debugger/profile/browser helpers and the device session before transferring control. Release or explicitly transfer resources/defaults and record their current values; the next operator rechecks rather than reuses stale state. A stale-session service restart requires confirming that no other agent/chat owns the service. Do not erase a simulator, clear shared defaults, kill another helper, reset settings or restart Xcode as a generic retry.

When an Xcode device-session response requires subagent UI events, the parent prepares the assignment and delegates to `projectalpha_device_ux_qa` as specified in the project `device-interaction` skill. Preparation is not a second UI operator; keep one current session key and end the session once.

Return a concise handoff: assigned files/responsibility, AC/INV/D mapping, baseline and changed-file identity, skills actually read, backend/tool actions/results, evidence paths, performance/size impact (measured or unverified), cleanup/next owner, approved deviations and blocked/unrun cases. The primary alone combines independent applicable gates into an AC/slice verdict.

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

SwiftUI owners keep `#Preview` and deterministic preview fixtures available in every build configuration, without `#if DEBUG` wrappers. When a production/configuration slice requires a Release check, the build gate checks compilation and flags preview-only conditional compilation that hides broken fixtures. Agent-policy-only changes require configuration/Markdown checks, not an app build.
