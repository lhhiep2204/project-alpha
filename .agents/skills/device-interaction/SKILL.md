---
name: device-interaction
description: Coordinate Build iOS Apps MCP workflows and required Apple Xcode MCP fallbacks for ProjectAlpha simulator/device UI evidence. Use for UI acceptance checks; this skill does not add or configure MCP servers.
---

# ProjectAlpha device interaction

Use Build iOS Apps skills and callable MCP tools first for supported simulator/device evidence; use Apple Xcode MCP only for a required unsupported capability. Read the repository's `AGENTS.md` instructions and the feature's required product/verification documents before interacting. Keep the check scoped to the requested feature.

## Build iOS Apps coordination

Read the shared [tools/evidence and session/handoff protocol](../../../.codex/agents/README.md) before mixing this workflow with plugin debugging, profiling or browser mirroring. This skill coordinates the project evidence boundary: plugin tools perform supported operations, custom agents own scope and verdicts, and Apple Xcode MCP supplies required unsupported capabilities. Select current tools from their exposed schemas rather than copying stale skill aliases. End or explicitly transfer the current session before another operator/backend takes control. Read-only collectors never perform project instrumentation or production fixes.

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

## Recover a lost interaction session

- Use the exact `interactionSessionKey` returned by the current start call. Keep each session focused and end it promptly. On this project's Xcode 27.0 setup, service logs showed two sessions removed about two minutes after their last UI call. Prepare the build, QA steps, and subagent before starting a session; perform UI calls promptly and analyze saved media after ending the session. If `DeviceInteractionSynthesize` reports `Session not found`, stop using that key, start a new session with a unique identifier, and delegate UI events for the new session as required below. Reinstall and run when the debug session has disconnected. A lost session may be recoverable without restarting the simulator.
- If a new start reports that the device is already in use by the lost key, but `DeviceInteractionEndSession` says that key does not exist, treat this as stale Xcode MCP service state. First ensure no other agent is actively using the service. Check `xcrun mcp-server status --format json`, then use the installed Xcode toolchain's `xcrun mcp-server stop` and `xcrun mcp-server open <absolute-project.xcodeproj>` to restart the service and reopen the project. The old MCP transport may close; reconnect with a fresh agent session before retrying. Do not reset the simulator or erase its data to repair an MCP session.
- Confirm recovery with a new start and end before claiming UI evidence. If the service remains unavailable, report the exact tool error and mark the device check blocked.

## Xcode MCP subagent requirement

When a device-session response says that UI events must be performed by a subagent, do not synthesize events from the parent task. Delegate the interaction to the `projectalpha_device_ux_qa` role and tell it to load this `device-interaction` skill before acting. Give it the current workspace identifier and session key. If the skill is not available to that subagent, stop before interacting and report the exact missing-skill/tool error; do not claim UI evidence.

## iPhone Duo evidence

For a Duo acceptance case, verify that Xcode 27.1 Device Hub and the required runtime are actually available. An ordinary iPhone or iPad simulator is not Duo evidence. If the required environment is unavailable, report that case as blocked with the exact limitation.

## Evidence boundary

A successful build proves compilation only. Do not claim a UI, accessibility, localization, RTL, or device acceptance criterion passed unless the required interaction was performed and its resulting state was inspected.
