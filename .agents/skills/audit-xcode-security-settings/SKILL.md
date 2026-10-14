---
name: audit-xcode-security-settings
description: |
  Audit and enable security-oriented Xcode build settings. Progressively enables compiler warnings, static analyzer checkers, and Enhanced Security features. Use when: user wants to secure their Xcode project, audit security settings, enable hardening, review security posture of build configuration, set up security-focused static analysis, enable static analysis, improve warning coverage, harden diagnostics, or catch more bugs at compile time in C/C++/Objective-C/Swift. SKIP: network security (TLS/ATS), code signing, privacy APIs.
---
# Audit Xcode Security Settings

Use for an explicit Xcode security/build-settings audit or hardening request, not ordinary feature work. Audit compiler/analyzer/clang-tidy diagnostics, Enhanced Security, pointer authentication, typed allocation, runtime protections, library slices, hardware memory tagging and checked pointer arithmetic only where applicable. Network security, code signing and privacy APIs remain outside this skill.

## Scope, tools and approval

- Follow AGENTS.md and the assigned file leases. Only the composition integrator among delegated agents may write project/build settings, target membership, Info configuration or entitlements. Read-only reviewers/collectors never apply settings. This skill does not authorize product, dependency or architecture changes.
- Load [references/workflow.md](references/workflow.md) for an actual audit. It contains language/target discovery, existing-state predicates, the editable plan, all security checks, approval/application steps and reporting. Load individual technical references only for the settings in scope; their index and the filter script are in that workflow.
- Discover actual workspace/project/target identity and exposed tool schemas; do not infer the Xcode project name from the repository directory. Use scoped Xcode tools where supported, with recorded capability gaps and repository plugin-first runtime rules. Missing required tools/evidence block the affected operation; never invent aliases or bypass permissions.
- Prepare a concrete editable plan and checksum baseline before asking to apply changes. Planning never changes settings, entitlements or target membership, including registration of a Markdown plan. Use one Markdown checkpoint with per-target evaluated values, explicit overrides, rationale, approval and outcomes instead of unavailable task-management APIs.
- Explicit approval of the concrete settings/target delta is required before application. Existing exact authorization remains valid; do not ask again just to acknowledge a briefing or confirm completion. Unchecked/deleted plan items are skipped; Cancel/missing plan applies nothing. New discoveries that widen the approved delta require updated approval.
- Keep task artifacts outside the repository unless their location is approved. Retain the reviewed plan/checkpoint by default; remove only task-created artifacts under an authorized cleanup preference. Never delete existing user files or auto-register documentation in Xcode.

Verify results and record skips/failures without claiming a security or device pass from configuration alone. Hardware-specific hardening needs actual capable-device evidence before shipping; preserve soft-mode rollout and checked-pointer-arithmetic prerequisites. No runtime/settings audit is performed merely by editing this skill.
