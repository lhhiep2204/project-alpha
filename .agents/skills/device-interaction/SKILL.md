---
name: device-interaction
description: Coordinate Build iOS Apps MCP workflows and required Apple Xcode MCP fallbacks for ProjectAlpha simulator/device UI evidence. Use for UI acceptance checks; this skill does not add or configure MCP servers.
---

# ProjectAlpha device interaction

Use for assigned simulator/device UI evidence, scoped to the requested ACs. Follow AGENTS.md and the exact relevant feature/verification sections; do not run a device session for a policy or compile-only task.

Before operating, read the [runtime tools/evidence and session protocol](../../../.codex/agents/runtime-workflows.md#tools-and-evidence) and its session/handoff section. Use Build iOS Apps exposed skills/tools first; Apple Xcode MCP supplies required unsupported capabilities only after recording the gap and transferring control. Current schemas outrank stale tool aliases. A temporary error does not justify silent backend switching.

## Required workflow

1. Hold the runtime/defaults/workspace reservation through cleanup. Use `session_show_defaults` before the first XcodeBuildMCP build/run/test, discover an eligible installed iOS 27 destination, and record project/scheme/runtime/build identity. Set needed ephemeral defaults (`persist: false`) with isolated `/tmp` artifacts, signing disabled for simulator work, and a task profile when supported. Do not reset simulator data/settings.
2. Execute only the requested build/run/interaction. Inspect the current UI tree, screenshot and logs; prefer current semantic references and refresh after each state-changing action. Apple fallback events use documented first-party syntax, never guessed commands. See the [backend workflows](../../../.codex/agents/runtime-workflows.md#device-backend-workflows).
3. Tie actual actions/outcomes to source/baseline, build configuration, runtime and evidence paths outside the repository. Check relaunch/persistence only when assigned. End sessions, debugger/captures/helpers you started, and release or transfer resources/defaults explicitly.

For a lost session or stale Xcode service, load [recovery](../../../.codex/agents/runtime-workflows.md#recover-a-lost-interaction-session) only after that failure. Never erase/reset a simulator, clear shared defaults, kill another operator's helper or restart a shared service without checking ownership.

If an Apple device-session response requires child-agent UI events, delegate to `projectalpha_device_ux_qa` with the current workspace/session key and this skill; the parent must not synthesize those events. Keep one operator/key and end once. Missing required skill/tool is BLOCKED for that interaction.

Duo evidence requires actual Xcode 27.1 Device Hub/runtime. Ordinary iPhone/iPad simulators cannot substitute. Compilation, launch, screenshot or browser frame alone proves no UI/accessibility/localization/RTL/input/device/physical-performance acceptance. Record PASS/FAIL/BLOCKED/NOT RUN per assigned case only after actual execution and inspection.
