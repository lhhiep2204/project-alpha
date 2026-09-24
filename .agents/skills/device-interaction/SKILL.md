---
name: device-interaction
description: Use ProjectAlpha's Xcode MCP workflow to build, launch, inspect, and verify iOS or iPadOS UI on an installed simulator or device. Use for UI acceptance evidence; this skill does not add or configure MCP servers.
---

# ProjectAlpha device interaction

Use the Xcode MCP server for simulator or device evidence. Read the repository's `AGENTS.md` instructions and the feature's required product/verification documents before interacting. Keep the check scoped to the requested feature.

## Required workflow

1. Discover the open Xcode workspace, scheme, and eligible run destinations with Xcode MCP. Open the repository's Xcode project only if it is not already open. Choose an installed simulator that matches the repository's required iOS version; do not invent or reuse a device UUID without discovering it in the current run.
2. Build the current project with Xcode MCP. If interaction is needed, start a workspace device session, install and launch the current build, then capture the initial accessibility hierarchy, screenshot, and logs.
3. Use the latest accessibility hierarchy to identify controls and their positions. The current Xcode MCP tool contract demonstrates tap syntax as `t <x> <y>`. Do not guess shorthand for swipe, typing, or other events; consult Xcode's first-party `device-interaction` command reference for the active toolchain. If that reference is unavailable, stop before issuing an undocumented command and report the blocker. After every event, capture and inspect the resulting state before taking another action. Prefer semantic/accessibility evidence over guessed coordinates.
4. Check the requested user outcome, including persistence or relaunch behavior only when that is part of the requirement. Do not erase simulator data or reset settings as a shortcut.
5. Store screenshots, logs, and traces outside the repository. End the device session when interaction is finished. Report the exact device/runtime, actions, evidence paths, and any blocked cases.

## Xcode MCP subagent requirement

When a device-session response says that UI events must be performed by a subagent, do not synthesize events from the parent task. Delegate the interaction to the `projectalpha_device_ux_qa` role and tell it to load this `device-interaction` skill before acting. Give it the current workspace identifier and session key. If the skill is not available to that subagent, stop before interacting and report the exact missing-skill/tool error; do not claim UI evidence.

## iPhone Duo evidence

For a Duo acceptance case, verify that Xcode 27.1 Device Hub and the required runtime are actually available. An ordinary iPhone or iPad simulator is not Duo evidence. If the required environment is unavailable, report that case as blocked with the exact limitation.

## Evidence boundary

A successful build proves compilation only. Do not claim a UI, accessibility, localization, RTL, or device acceptance criterion passed unless the required interaction was performed and its resulting state was inspected.
