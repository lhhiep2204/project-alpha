# ProjectAlpha runtime workflows

On-demand reference for assigned build/test, simulator/device, debugger, profiling or browser operations. Routing-only and source-only work need not load this file. [AGENTS.md](../../AGENTS.md) governs scope, risk and safety; [routing guide](README.md) assigns owners. For UI/device evidence, also load the [project device skill](../../.agents/skills/device-interaction/SKILL.md).

## Build iOS Apps coordination

The installed Build iOS Apps plugin provides reusable skills and a separate `xcodebuildmcp` server. Custom agents retain their existing ownership; skills provide methods within that ownership. Read only the relevant skill/method sections; runtime operators also read tools/evidence and session/handoff sections before operating. Select skills by the actual task, and load only the relevant references. Pure Domain/persistence work need not invoke a UI skill.

Resolve instructions in this order: applicable system/developer and explicit user instructions, repository `AGENTS.md` and approved product contracts, the assigned role/file scope, project SwiftUI/SDK guidance, then compatible plugin methods/examples. A plugin example does not approve a product/architecture change. Resolve routine technical facts read-only; ask before consequential unapproved choices or conflicting contracts under AGENTS.md. Block only unavailable required evidence or the affected choice.

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
- An approved Liquid Glass requirement applies to each named surface and its contained controls. Feature owners load `swiftui-liquid-glass` for cards and child actions as well as standalone controls; do not infer that a card is excluded because it is not a system bar/control.
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

Before runtime work, the primary handoff names the operator, purpose (diagnostic or acceptance), backend, workspace/project, scheme, discovered UDID/runtime, source/checksum baseline, exact app/build artifact, evidence directory, requested ACs/flow and cleanup responsibility. Discover any missing identifier through read-only tooling; resolve identifiers read-only; ask only for an unresolved consequential choice under AGENTS.md, and report unavailable required evidence as BLOCKED.

End log capture/debugger/profile/browser helpers and the device session before transferring control. Release or explicitly transfer resources/defaults and record their current values; the next operator rechecks rather than reuses stale state. A stale-session service restart requires confirming that no other agent/chat owns the service. Do not erase a simulator, clear shared defaults, kill another helper, reset settings or restart Xcode as a generic retry.

When an Xcode device-session response requires subagent UI events, the parent prepares the assignment and delegates to `projectalpha_device_ux_qa` as specified in the project `device-interaction` skill. Preparation is not a second UI operator; keep one current session key and end the session once.

Return a concise handoff: assigned files/responsibility, AC/INV/D mapping, baseline and changed-file identity, skills actually read, backend/tool actions/results, evidence paths, performance/size impact (measured or unverified), cleanup/next owner, approved deviations and blocked/unrun cases. The primary alone combines independent applicable gates into an AC/slice verdict.


## Recover a lost interaction session

- Use the exact `interactionSessionKey` returned by the current start call. Keep each session focused and end it promptly. On this project's Xcode 27.0 setup, service logs showed two sessions removed about two minutes after their last UI call. Prepare the build, QA steps, and subagent before starting a session; perform UI calls promptly and analyze saved media after ending the session. If `DeviceInteractionSynthesize` reports `Session not found`, stop using that key, start a new session with a unique identifier, and delegate UI events for the new session as required below. Reinstall and run when the debug session has disconnected. A lost session may be recoverable without restarting the simulator.
- If a new start reports that the device is already in use by the lost key, but `DeviceInteractionEndSession` says that key does not exist, treat this as stale Xcode MCP service state. First ensure no other agent is actively using the service. Check `xcrun mcp-server status --format json`, then use the installed Xcode toolchain's `xcrun mcp-server stop` and `xcrun mcp-server open <absolute-project.xcodeproj>` to restart the service and reopen the project. The old MCP transport may close; reconnect with a fresh agent session before retrying. Do not reset the simulator or erase its data to repair an MCP session.
- Confirm recovery with a new start and end before claiming UI evidence. If the service remains unavailable, report the exact tool error and mark the device check blocked.

## Xcode MCP subagent requirement

When a device-session response says that UI events must be performed by a subagent, do not synthesize events from the parent task. Delegate the interaction to the `projectalpha_device_ux_qa` role and tell it to load this `device-interaction` skill before acting. Give it the current workspace identifier and session key. If the skill is not available to that subagent, stop before interacting and report the exact missing-skill/tool error; do not claim UI evidence.

## Device backend workflows

## Preferred plugin workflow

1. Load `build-ios-apps:ios-debugger-agent` from the active catalog. Check exposed tool metadata: installed names and capabilities may differ from the skill examples. Call `session_show_defaults` before this agent's first build/run/test; do not speculatively discover projects or change defaults in parallel. Use the assigned project path, discover a scheme and eligible installed iOS 27 runtime/UDID as needed, and record them. A booted device on the wrong runtime is not an eligible default. Do not invoke a build/run just to audit configuration.
2. While holding the shared session assignment, set missing/wrong defaults with isolated `/tmp` DerivedData, `persist: false`, and `CODE_SIGNING_ALLOWED=NO` for simulator work. Use a task-specific profile when supported and verify the resulting values. For a requested run, use the exposed build/run or install/launch workflow; follow its current boot behavior rather than adding speculative boot/open steps. For a build-only assignment, do not launch the app. Do not reset simulator data/settings.
3. Confirm the exact current app/build launched, then capture and inspect the runtime UI snapshot, screenshot and available logs. Prefer current semantic element references. Use only documented tool schemas; refresh and inspect state after navigation, scrolling, sheet changes, layout changes, or an action whose result the case asserts. Do not reuse stale element references or hide intermediate assertions in a batch.
4. Check only assigned outcomes, including relaunch/persistence when required. Keep evidence outside the repository and tie every result to source/baseline, build configuration, device/runtime and actual actions. A successful launch/screenshot is not an accessibility, resize or physical-device performance pass.
5. Detach the debugger and stop captures/helpers you started before releasing control. Report any retained defaults/resources for the next operator to recheck. If a required capability is absent, record it and transfer control before the Apple fallback below. If a tool errors, classify the failure; do not silently switch backend or grant missing permissions. When no available backend can perform a required case, mark it blocked.

## Apple Xcode MCP fallback

Use this path only for an assigned required capability the plugin's exposed tools cannot provide. Record that gap and keep one operator. Existing first-party device-session requirements remain applicable on this path.

## Apple fallback workflow

1. Discover the open Xcode workspace, scheme, and eligible run destinations with Xcode MCP. Open the repository's Xcode project only if it is not already open. Choose an installed simulator that matches the repository's required iOS version; do not invent or reuse a device UUID without discovering it in the current run.
2. Build the current project with Xcode MCP. If interaction is needed, start a workspace device session, install and launch the current build, then capture the initial accessibility hierarchy, screenshot, and logs.
3. Use the latest accessibility hierarchy to identify controls and their positions. The current Xcode MCP tool contract demonstrates tap syntax as `t <x> <y>`. Do not guess shorthand for swipe, typing, or other events; consult Xcode's first-party `device-interaction` command reference for the active toolchain. If that reference is unavailable, stop before issuing an undocumented command and report the blocker. After every event, capture and inspect the resulting state before taking another action. Prefer semantic/accessibility evidence over guessed coordinates.
4. Check the requested user outcome, including persistence or relaunch behavior only when that is part of the requirement. Do not erase simulator data or reset settings as a shortcut.
5. Store screenshots, logs, and traces outside the repository. End the device session when interaction is finished. Report the exact device/runtime, actions, evidence paths, and any blocked cases.
