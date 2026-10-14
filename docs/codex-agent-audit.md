# Codex agent architecture audit and optimization proposal

Audit date: 2026-10-14. Status: Phases A and B complete; awaiting explicit implementation approval. Phase C/D have not started. The consolidated proposal below supersedes preliminary checkpoint notes.

## Scope and safety

This is an infrastructure audit, performed sequentially by the main agent. No subagents, application builds, app tests, device sessions, or configuration changes are authorized in this phase. The only repository write is this checkpoint. Existing staged/unstaged work is preserved.

Initial status and checksummed copies of inspected policy/configuration/docs are saved outside the repository at `/tmp/projectalpha-codex-agent-audit-20261014/` (`initial-status.txt`, `manifest.json`, `baseline/`). This is an audit baseline, not a pristine application baseline or authorization to edit source. User instruction explicitly authorizes this main-agent documentation artifact.

## Checkpoints completed

- Configuration/agent/skill inspection checkpoint saved during Phase A.
- Configuration and targeted module/workflow evidence checkpoint saved at Phase A completion.
- Consolidated Phase B proposal finalized below. Earlier preliminary notes have been consolidated to avoid duplicate reading on resume.

## Architecture audit

### Current orchestration

The main agent triages requests and assigns optional specialists through natural-language descriptions, role instructions and `.codex/agents/README.md`; there is no executable task classifier. Sixteen standalone TOML definitions provide three discovery/documentation roles, nine production owners and four quality roles. All are exposed in this session. Role names come from `name`, not the hyphenated filename; renaming files for cosmetic consistency is unnecessary.

AGENTS supplies architecture, working-tree safety, clarification, ownership, reading requirements and evidence rules. The agent README supplies routing, plugin adaptation, runtime resource reservations and handoffs. Every role repeats a common preamble, then its boundaries, specialist contracts and skill recommendations. Skills supply methods; docs 01–09 remain product/architecture authority, and source/project settings plus dated doc 10 establish implementation state.

Current small-bug routing still calls for owner → affected regression test → final build gate. Cross-cutting routing adds tracer, multiple owners and independent review. Requirements make delegated production writers and test writers separate; composition alone handles Xcode configuration. Parallel writes must not overlap, and runtime operators are serialized. Only the main agent can combine applicable evidence into an AC/slice verdict. These protections are useful, but the main agent's permission to implement and author focused tests without a specialist pipeline is not explicit.

### Strengths to retain

- Foundation-only Domain, Data-owned persistence/adapters, MainActor Presentation, App composition and extension-safe contracts have real, distinct ownership.
- Single-writer SwiftData critical sections, rollback, post-save success, immutable crossings, revisions and cancellation are explicit. Media reference removal precedes deletion; draft identity and map scope stay stable.
- Immutable baselines protect untracked work; status and evidence identity prevent false attribution. The current tree contains existing staged/unstaged work, including infrastructure, docs and application files.
- Test authoring, semantic review, mechanical execution and device evidence are distinguished. Live provider calls and timing sleeps are excluded from deterministic tests.
- Plugin-first tooling, SDK availability checks, one runtime/defaults owner, isolated evidence artifacts and honest BLOCKED cases are already documented.
- No model is pinned globally in the project. Default subagent reasoning is medium; specialist effort is explicit. No new dependencies or generic architecture frameworks are needed.

### Confirmed issues and cost risks

| ID / priority | Evidence | Consequence / recommendation |
|---|---|---|
| F-01 / P0 | All 16 role TOMLs line 4 set `sandbox_mode`; official custom-agent guidance says this setting does not override the parent's permissions. Reviewer/tracer say read-only; runtime roles describe workspace-write as artifact permission. | Remove reliance on inert per-role permission settings; accurately document inherited permissions and retain no-edit policy plus baseline comparison. Do not claim enforced isolation. Runtime enforcement remains untested. |
| F-02 / P1 | AGENTS lines 14–18 stop for any uncertainty; README also sends unresolved choices to that gate. | Naming, local refactoring and equivalent implementation choices can trigger unnecessary approval round trips. Replace with the proposed risk gate below, retaining stops for contract/data/destructive choices. |
| F-03 / P1 | AGENTS coordination and README lines 109 onward prescribe specialized production/test/final execution even for small bugs. | Optional-agent language does not make the actual workflow main-agent-first. Explicitly allow main-agent implementation, affected tests and focused execution for low risk, without calling it independent verification. |
| F-04 / P1 | AGENTS line 22 requires docs index + 01/03/04/08 for every implementation slice; every role's line 6 requires the whole agent README before acting. | Mandatory documents total 172,918 bytes / 23,960 whitespace words before feature docs. The docs index itself is 32,055 bytes / 4,273 words, largely historical records. Read current task-relevant sections once; give children exact sections/IDs and prior findings. Infrastructure-only work need not load app contracts. |
| F-05 / P1 | Identical 506-byte / 67-word role preamble appears 16 times; six SwiftUI production roles repeat the global preview rule; adaptive/performance/plugin warnings recur across layers. | Consolidate general rules, keeping specialist failure checks near their owner. Trim unconditional runtime reading. Moving text helps only if loading becomes conditional. |
| F-06 / P1 | Agent README has 18,258 bytes / 2,378 words of routing and runtime/profile/browser detail; Domain and contracts roles must load it too. | Keep a short routing/ownership index; place runtime-only sections in an on-demand document and make the existing device skill link there. Preserve resource reservations and fallback rules. |
| F-07 / P1 | Security skill entry point is 59,187 bytes / 8,173 words, including seven phases, templates, per-setting task bookkeeping and three routine prompts. | Keep a short trigger/prerequisite/approval index and move procedure to a reference loaded for an actual security audit. Remove briefing-only acknowledgment and final cleanup prompts when prior authorization/preferences settle them. Never remove approval for applying settings. |
| F-08 / P0 | Both SwiftUI skill bodies claim unconditional authority over model knowledge; repository declares contracts/SDK precedence. | State that guidance is reference material subordinate to higher-priority instructions, approved contracts and installed declarations. Apple-authorship assertions are UNVERIFIED provenance, not a reason to bypass SDK checks. |
| F-09 / P1 | Security skill requires TaskCreate/Get/List/Update and AskUserQuestion; those names are not exposed. Xcode read/settings/entitlement tools are exposed. | Replace task-tool dependence with a small Markdown checkpoint and available user-input capability. Record missing capability explicitly; no guessed aliases or config bypass. |
| F-10 / P2 | Project and personal `device-interaction` catalog entries share a name and differ in bytes. | Use the exact project skill path for ProjectAlpha evidence; do not modify personal skills or assume duplicate names resolve correctly. |
| F-11 / P1 | Generic source rules permit parallel test execution, while README reserves one workspace/defaults/runtime owner. Build role asks Release for all production slices; global text is conditional. | Explicit resource leases and an applicability table resolve over-broad interpretations. Do not parallelize mutating build/UI tooling merely because source files differ. Make Release conditional on risk/configuration/slice evidence. |
| F-12 / P2 | Settings role says audit every feature for accessibility; several roles refer to planned widget/media/draft work. | Limit audits to assigned changed surfaces and adjacent dependencies; label future ownership paths as planned. Avoid expanding a one-view task into a whole-app audit. |

No project-level setting has been established as invalid. F-01 is a documented ineffective role override, not a parser rejection. No percentage savings, execution-speed improvements or allowance savings have been measured.

### Configuration verification and limits

The official [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) supports the four current `[agents]` keys, MCP command/args/enabled/startup timeout and per-tool `approval_mode = "approve"`. Four concurrent spawned threads excludes the primary, consistent with this session's five total slots. Preserve these values; no reason to change approvals or concurrency was found. Project config loading depends on project trust; effective trust/merge precedence was not independently inspected.

Official [subagent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents) supports standalone TOMLs with name, description and instructions. Custom role model/effort fields take precedence over resolved spawn/default settings; permissions and MCP servers come from the parent. Thus a spawn-effort suggestion cannot reliably override an explicit role effort. This session confirms role enumeration, not actual role spawn or sandbox enforcement.

Official [skill guidance](https://learn.chatgpt.com/docs/build-skills) describes name/description discovery followed by full skill-body loading on activation. All five project skills are listed in this session and their referenced local resources exist. Reference bodies were not exhaustively read or their SDK examples compiled: this infrastructure task does not adopt those APIs.

Installed CLI is `codex-cli 0.155.1`; `codex --help` documents model and strict-config options. `codex --strict-config features list` failed because this subcommand does not support that option. Plain feature listing and bundled model listing succeeded; neither proves strict config validation. No Codex inference, subagent, daemon launch or network model refresh was run.

UNVERIFIED: exact desktop binary version; effective main model/effort and project trust; role permission enforcement; model entitlement/account allowance multipliers; inherited MCP behavior inside a child; live tool/session operation; SDK 27 reference declarations and current Duo environment. These do not prevent a policy proposal and must not be called configuration defects.

## Agent decision matrix

Decisions apply to responsibilities. KEEP can still receive common preamble/permission cleanup. REFINE changes activation, loading or scope without removing expertise. No MERGE/REMOVE candidate is justified by the evidence. No agent-use telemetry was inspected: frequency below is expected from task type and delivery slices, not measured historical usage. `projectalpha_` prefixes are omitted only in frequency shorthand, not in the inventory names.

All role files below are under `.codex/agents/` and have the hyphenated equivalent of their `name` with `.toml` suffix. Ownership evidence is normally their line 8; descriptions are line 2.

| Agent | Decision | Reason / concrete evidence | Expected benefit | Risk |
|---|---|---|---|---|
| [projectalpha_spec_tracer](../.codex/agents/projectalpha-spec-tracer.toml) | REFINE | Lines 10–20 require seven base/index documents and a multi-part plan. Valuable for unresolved cross-module dependencies; main can classify a narrow task. | Activate only for substantial contract/dependency analysis; accept already-traced IDs and exact sections. | Under-tracing a true product conflict; keep mandatory escalation for changed contracts. |
| [projectalpha_bug_investigator](../.codex/agents/projectalpha-bug-investigator.toml) | REFINE | Line 8 forbids fixes; reproduction, cancellation/revision and environment diagnosis are valuable. High effort and a separate context are wasteful when root cause is already established. | Reserve for difficult reproduction/races or evidence-heavy diagnosis; main handles straightforward bugs. | Root cause assumed prematurely; require evidence before fixes regardless of executor. |
| [projectalpha_contract_maintainer](../.codex/agents/projectalpha-contract-maintainer.toml) | KEEP | Line 8 confines edits to README/docs after explicit approved input; it does not implement Domain behavior. | Retain traceability expert for approved U/D/INV/AC changes; main can write infrastructure checkpoints. | Accidental product approval; keep quoted approved input and smallest document set. |
| [projectalpha_domain_policy_engineer](../.codex/agents/projectalpha-domain-policy-engineer.toml) | KEEP | Domain-only ownership and exact duplicate policy; current Domain policies/ports are separate from Data. | Retain specialist for identity/validation/contracts; narrow ordinary value changes can remain with main. | Persisted normalization drift; high-risk identity work still requires approval and independent review. |
| [projectalpha_swiftdata_library_engineer](../.codex/agents/projectalpha-swiftdata-library-engineer.toml) | KEEP | Persistence/repository/mapper ownership; `LibraryStore.swift:36` and `SwiftDataCollectionRepository.swift:11` are real store/adapter boundaries. | Dedicated expertise for atomicity, rollback, migrations and observation races. | Store semantics affect every feature; preserve high reasoning and data gates. |
| [projectalpha_local_media_engineer](../.codex/agents/projectalpha-local-media-engineer.toml) | KEEP | Data media implementations; docs 04 media lifecycle and INV-06/08 require filesystem/database ordering distinct from CRUD. Concrete pipeline ownership is mostly planned. | Preserve specialist when pipeline work exists; do not activate for collection-only work. | Lost committed media; preserve reference recheck, cancellation ownership and failure tests. |
| [projectalpha_scene_navigation_engineer](../.codex/agents/projectalpha-scene-navigation-engineer.toml) | KEEP | Routing/MainTabs and URL state machine; root wiring explicitly excluded. D-03/04/16/17 and INV-09 are separate state concerns. | Keep complex navigation expertise; main handles a local behavior-preserving adjustment. | Duplicate state owners or draft loss; review lifecycle/intent changes independently. |
| [projectalpha_library_workflow_engineer](../.codex/agents/projectalpha-library-workflow-engineer.toml) | REFINE | UI/editor/draft state only. `CollectionEditorViewModel.swift:77` calls use cases instead of mutating storage. Broad adaptive/plugin text repeats global instructions. | Tighten path ownership and scope around non-map library UI; avoid persistence handoff for a UI-only change. | Quick-capture/editor overlap with map; explicitly list shared component and draft responsibilities. |
| [projectalpha_map_location_services_engineer](../.codex/agents/projectalpha-map-location-services-engineer.toml) | REFINE | Owns per-map UI plus concrete MapKit/CoreLocation adapters, excluding Domain identity/store/coordinator. Long global and plugin repeats; approved floating card now differs from older general detail prose. | Retain domain expertise; point to the exact active feature contract rather than embedding an alternate UI specification. | Stale role text treated as product authority; contract wins and disagreements must escalate. |
| [projectalpha_widget_integration_engineer](../.codex/agents/projectalpha-widget-integration-engineer.toml) | KEEP | Shared snapshots/publisher/AppEntity/views; excludes live store, URL encoder and project wiring. Project currently has no widget target. | Preserve P-08 specialization without invoking it before widget work. | Overlap in contracts/App integrations; keep snapshot-vs-URL and behavior-vs-wiring boundaries. |
| [projectalpha_settings_localization_accessibility_engineer](../.codex/agents/projectalpha-settings-localization-accessibility-engineer.toml) | REFINE | Exact preference/localization/design-system paths; cross-feature audit mandate is broader than an assigned change. | Scope audits to affected surfaces; other feature owners perform view edits. Main may make related key/catalog edits serially in a small task. | Missing localized/accessibility coverage; retain required checks for every changed shipping key/control. |
| [projectalpha_composition_integrator](../.codex/agents/projectalpha-composition-integrator.toml) | KEEP | Exclusive App/DI/project/release wiring ownership, explicitly no business behavior. `AppContainer.swift:11` composes services/preferences. | Preserve a single Xcode integrator; avoid handing ordinary feature-model edits to it. | Project/target edits conflict easily; retain exclusive writer, membership and build checks. |
| [projectalpha_acceptance_test_engineer](../.codex/agents/projectalpha-acceptance-test-engineer.toml) | REFINE | Test-target-only paths, deterministic store/media/provider cases and newly affected authoring runs. Valuable independent test design; mandatory separate context is excessive for a trivial edit. | Main may author a small regression alongside its own fix; delegate meaningful test matrices or independent coverage. | Self-authored tests miss behavior; independent test design/review remains for high risk. |
| [projectalpha_architecture_concurrency_reviewer](../.codex/agents/projectalpha-architecture-concurrency-reviewer.toml) | KEEP | Read-only semantic checks of atomicity, isolation, stale completions and adaptive continuity; no execution-gate ownership. | Preserve fresh review for high-risk changes and focused concerns; skip style-only low-risk review. | Same agent implementing and reviewing cannot supply independence; retain separate reviewer when required. |
| [projectalpha_build_verification_gatekeeper](../.codex/agents/projectalpha-build-verification-gatekeeper.toml) | REFINE | Executes/classifies applicable final checks; excludes editing and logic review. Explicit policy-only no-build rule is good; blanket production Release wording overreaches. | Primary runs low-risk checks; one designated final runner for independent/medium-high gates. Consolidate deterministic checks and concise outputs. | Focused run mistaken for full suite; record exact command, scope, artifact and NOT RUN cases. |
| [projectalpha_device_ux_qa](../.codex/agents/projectalpha-device-ux-qa.toml) | KEEP | Manual/runtime acceptance, physical performance and input/RTL/Duo evidence; forbids fixes. This differs from deterministic tests. | Activate for assigned UI/device evidence, not every model test; preserve collector independence and runtime lease. | Tool availability mistaken for executed QA; keep direct interaction proof and blocked cases. |

Expected frequency/context justification:

| Role group | Expected activation | When separate context adds value | Main/skill/script alternative |
|---|---|---|---|
| Spec / contract | New cross-module work or approved specification changes; occasional | Large dependency/traceability set or an independent contract pass | Main classifies simple tasks; deterministic link/ID checks. Do not move authority into a skill. |
| Bug investigator | Hard reproductions, unexplained races/services; occasional | Noisy logs, multiple hypotheses, runtime tracing | Main diagnoses a clear execution path; debugger/performance skills supply methods. |
| Domain / SwiftData | P-01/P-02 and later identity/persistence changes; substantial during these slices | Pure policy versus serialized storage expertise and difficult failures | Main handles bounded routine changes; preserve specialist roles. |
| Library / scene / map / settings | Frequent during corresponding feature slices | Significant feature/state work or an independent module | Main handles small UI/key changes; select only relevant SwiftUI references. |
| Media / widget / composition | Specific pipeline/P-08/wiring tasks; bursty | Recovery/publication/project configuration expertise | Do not activate planned owners for absent pipelines. Composition remains the delegated project writer. |
| Tests / reviewer / build / QA | Conditional on changed behavior and risk | Independent failure design, semantic audit, final evidence or actual device interaction | Scripts/tools execute checks; main interprets low-risk runs. These functions must remain distinct when independence is required. |

### Overlap assessment

- SwiftData vs Library Workflow: save UI and persistence participate in one flow but own different layers; the observed use-case → repository → store path supports retaining both. UI does not reimplement duplicate policy or commit transactions.
- Domain Policy vs Contract Maintenance: Domain implements approved rules; contract maintainer records approvals and acceptance traceability. Neither approves product behavior. Merge would blur code/spec authority.
- Architecture Review vs Composition: reviewer evaluates dependencies/lifetimes without editing; composition wires supplied interfaces and Xcode. Keeping them distinct gives meaningful independent scrutiny.
- Acceptance Testing vs Build Verification: one designs/asserts behavior; the other runs and classifies results. Replace routine mechanical bookkeeping with deterministic checks, without merging high-risk test design and final evidence.
- Device UX QA vs automated/general testing: physical interaction, accessibility, adaptive layout and physical profiling cannot be supplied by a passing unit suite. Keep QA conditional, scoped and independent.
- Settings vs feature owners: settings owns shared catalogs/design system; a feature owns its views. A main-agent small task may assume both responsibilities sequentially. Delegated specialists retain their narrower scope and handoffs.

## Skill assessment

The assessment covers every repository skill entry point. Reading them for this audit did not activate their application workflows.

| Skill / current purpose | Duplication or activation issue | Recommended change | Expected benefit / compatibility |
|---|---|---|---|
| `swiftui-specialist`: Apple-oriented data flow, structure, Environment, lists, localization and deprecation guidance | Long description and authority/provenance claims; global SwiftUI rules also repeat in roles. Body already routes to relevant references. | Keep; front-load a shorter SwiftUI implementation/review trigger; retain reference map. Add contract/SDK precedence and verified-source caveat. Load only references matching changed constructs. | Preserve useful expertise with smaller metadata and no unnecessary full reference load. Deployment iOS 27 is compatible in principle; individual APIs still need local verification when adopted. |
| `swiftui-whats-new-27`: changed SDK APIs/compiler behavior | SDK-year wording and `becaming` typo; absolute correctness claims; new APIs asserted in references have not been compiled here. | Keep trigger around SDK 27 errors/adoption; correct wording, preserve targeted references and add installed declaration/availability check. Do not migrate unrelated APIs. | Avoid training-memory fixes and accidental unsupported API adoption. Target is iOS 27.0, but target number alone does not establish every 27.x declaration. |
| `modernize-tests`: migration and Swift Testing modernization | Generic description can activate for ordinary test authoring; body encourages migration and optional agent splitting. Its asynchronous confirmation example lacks guidance to await completion before the confirmation scope exits. | Restrict to explicit modernization/migration; preserve XCTest UI/performance exceptions; scope optional delegation by project risk; explain completion/clock/continuation requirements when adapting async tests. | Avoid opportunistic churn and extra agents. Existing Swift Testing tests need no migration; UIKit lifecycle and UI tests retain XCTest. Sample APIs remain subject to installed Testing support. |
| `device-interaction`: plugin-first project evidence and Apple fallback | Repeats much of README runtime protocol; same name as personal skill; recovery detail is always loaded. | Keep short project-specific prerequisites, evidence boundary and conditional child-event requirement. Link one runtime protocol; load recovery only after a matching failure. Refer to exact project path. | Preserve required backend and runtime ownership with less routine context. Required tools are exposed, operational behavior and Duo runtime are untested here. No server installation/config changes. |
| `audit-xcode-security-settings`: security warnings, analyzer, Enhanced Security and entitlements | Very large body, mandatory task APIs absent here, routine begin/cleanup prompts, planned Xcode registration before settings approval, assumptions about workspace name from CWD. | Short entry point + on-demand workflow reference; record evidence in one document; discover workspace/target identity through actual tools. Explicitly delegate project/entitlement writes to composition. Approval applies to concrete settings changes; do not mutate target membership just to make an audit plan visible. | Stronger ownership and workable tooling with lower activation context. Clang warning sections already skip pure Swift; runtime/hardware-specific hardening requires actual SDK/device evidence in a separately authorized security task. |

All 33 referenced local reference/script tokens resolve (17 security, 9 SwiftUI specialist, 7 SDK 27). Their contents were not fully reviewed; path existence is not API/provenance correctness. No new skill is recommended. Existing skills can carry procedural guidance; contracts and ownership remain in repository instructions/docs.

## Optimization proposal

### Minimal core plus on-demand context

Keep one concise AGENTS core containing authority, risk-based clarification, task-first routing, working-tree baseline safety, the layer map, ownership locks, critical persistence/concurrency/media/draft invariants, skill triggers and honest reporting. Keep Swift headers/string constants/localization/preview rules once, scoped to source work. Do not duplicate full plugin examples, historical workflow logs or the adaptive QA matrix here.

Keep `.codex/agents/README.md` as a short routing/ownership/evidence index. Detailed runtime reservations, backend transfer, ETTrace and browser exceptions move into `.codex/agents/runtime-workflows.md`, loaded only before corresponding runtime operations. Agent TOMLs retain their specific path responsibility, exclusions, specialist hazards, trigger and output. Safety cannot rely solely on a handoff's summary; all writers/reviewers must have the core plus exact current relevant contracts.

Documentation is reference material, not mandatory whole-file context. Read README/index current routing sections once, then the active relevant decisions/invariants/ACs and exact feature sections. Search and bounded reads include surrounding context; do not select a convenient excerpt that conceals a conflicting contract. Changed product behavior still requires checking the coherent decision/AC document set. Children receive IDs, paths, approved input and prior investigation, not duplicated prose or the parent's full history by default.

### Proposed clarification policy

Ask before changing product/UX requirements, Domain invariants, identity/persistence semantics, migrations, public or cross-module contracts, external dependencies, destructive operations or major architecture. A contradictory approved contract or unavailable required evidence blocks the affected choice/claim; independent read-only work can continue.

Proceed autonomously with internal naming, small implementation details, local behavior-preserving refactors, test organization, equivalent implementations and non-breaking local organization. Record a low-risk assumption briefly when it materially affects review. Establish API facts through read-only evidence first; unsupported APIs must not be guessed. Routine investigation is not itself an approval request. Missing header-history evidence and edits outside authorized scope still require the owner; no fabricated dates or silent scope expansion.

### Exact files and priorities

These are proposed modifications only. Approval must cover changes to workflow authority as well as textual deduplication.

| Priority | Exact files | Specific changes / reason | Expected efficiency effect | Risk / trade-off |
|---|---|---|---|---|
| P0 | All 16 `.codex/agents/projectalpha-*.toml` files listed in the matrix | Remove misleading `sandbox_mode` overrides; keep repository-read-only instructions where applicable. Correct artifact-permission explanations. No permission/server/service-tier changes. | Remove false assumptions about isolation and artifact access. | Parent permissions still control tools; prose restrictions are not enforced sandboxing. Baseline/status comparisons remain essential. |
| P0 | `.agents/skills/swiftui-specialist/SKILL.md`, `.agents/skills/swiftui-whats-new-27/SKILL.md` | Replace unconditional authority claims with precedence and installed-SDK verification rules; do not rewrite technical references without evidence. | Avoid contradictions/unsupported adoption and needless clarification. | Must preserve legitimate specialist guidance and deployment constraints. |
| P1 | `AGENTS.md` | Explicit main-agent small-task authorization, risk gate, conditional reading and verification, preserve critical safety/ownership. Clarify main may implement/test serially under owner responsibilities; delegated production writers still do not edit tests. | Fewer spawned contexts/handoffs and repeated full-document reads. | Requires explicit approval to relax current agent-only workflow language; independence must remain for high risk. |
| P1 | `.codex/agents/README.md` | Replace fixed small-task pipeline with routing table; add delegation justification, exact write leases, compact handoff, final-run applicability, main/specialist distinctions. Remove unconditional whole-runtime reading. | Less orchestration overhead and duplicate execution. | Incorrect risk classification could under-verify; escalate when persistent/state effects appear. |
| P1 | New `.codex/agents/runtime-workflows.md`; `.agents/skills/device-interaction/SKILL.md` | Move existing runtime/tools/profile/browser/ETTrace protocol into one reference; retain narrow trigger and recovery/evidence links. Keep plugin-first, session_show_defaults, persist:false, isolated artifacts, no reset and conditional Apple child-event requirement. | Runtime detail loaded only by an operator who needs it. | Dangling links or missed reservations; check all references and lease rules. |
| P1 | All 16 role TOMLs | Replace common preamble with minimal core/reference directions; remove repeated global preview/adaptive/performance text; keep specialist invariant summaries. Narrow spec/investigator activation, library/map/settings task scope, testing and gate applicability. | Smaller role context and fewer accidental broad audits. | Over-trimming could erase a specialist hazard; retain ownership/exclusions and relevant failure checks. |
| P1 | `.agents/skills/audit-xcode-security-settings/SKILL.md`; new `.agents/skills/audit-xcode-security-settings/references/workflow.md` | Move existing procedure/template to reference; replace unavailable task APIs; preserve concrete approval boundary; remove needless prompts and preapproval project registration; add composition ownership. | Far less entry-point context and routine approval overhead. | This is the largest text move; perform after core cleanup and verify original safety coverage. No security settings are applied. |
| P1 | `.agents/skills/modernize-tests/SKILL.md` | Explicit modernization-only activation; conditional delegation; clarify async confirmation completion. | Avoid incidental migrations and unnecessary test subagents. | Preserve XCTest UI/performance/lifecycle boundaries and framework availability checks. |
| P2 | `.codex/agents/projectalpha-composition-integrator.toml`, `.../projectalpha-domain-policy-engineer.toml`, `.../projectalpha-map-location-services-engineer.toml`, `.../projectalpha-scene-navigation-engineer.toml` | Optional medium default for routine work, but only with a proven high-risk escalation mechanism (see model strategy). | Reduce reasoning effort for ordinary implementation. | Fixed role effort wins over spawn effort; defer this change until high-risk routing is demonstrably supported. |
| P2 | `.agents/skills/swiftui-specialist/SKILL.md`, `.agents/skills/swiftui-whats-new-27/SKILL.md`, `.agents/skills/device-interaction/SKILL.md` | Shorten/front-load descriptions, typo fix, exact project-path routing. | Smaller metadata and clearer activation. | Short descriptions must still discriminate the task. Do not edit personal copies. |
| P2 | `docs/codex-agent-audit.md` | Record approved scope, implemented differences, configuration-only evidence and unresolved items. | Durable resume path and fewer repeated audits. | Keep this audit artifact out of every app task's mandatory reading. |

Unchanged in this proposal: `.codex/config.toml` (all existing settings retained), application/test Swift, project.pbxproj, product docs 01–10, top-level README and personal/plugin-cache configuration. No agent deletion, new agent, dependency, product change or global model pin is proposed. New Markdown references are infrastructure material, not new product contracts. Future repeatable validation scripts are an opportunity; they are not added until a stable duplicated operation justifies a concrete script.

## Proposed task routing

Main → classify scope/risk → inspect actual path/contracts → decide whether delegation adds value → implement under explicit ownership → run applicable validation → report evidence.

| Task size/risk | Default executor and delegation | Reading/skills | Verification |
|---|---|---|---|
| Small / low risk | Main handles diagnosis, change and a meaningful focused regression if needed. Usually zero children; at most one specialist for a concrete expertise or required capability. | Core + relevant contract sections + applicable skill/reference. No research/tracing child for a clear request. | Diff/static checks; focused test or compile where warranted; directly affected UI interaction if required by the change. No automatic full suite/Release/independent review. |
| Medium | Main names primary layer owner. Delegate significant implementation OR independent test/review work when useful; one/two modules does not itself require two writers. Main can coordinate serial cross-owner work. | Exact sections and seams; scoped skills. Tracer only for difficult unresolved dependencies. | Relevant module tests and appropriate Xcode build; focused semantic review for state, persistence, cancellation or lifecycle risk; device cases only where AC requires them. |
| Large / high risk | Plan dependencies and approved decisions. Main coordinates selected specialists. Preserve independent semantic review/final execution, and independent test design where complex integrity cases warrant it. | Trace active contracts, affected boundaries and exact required evidence; on-demand specialist/runtime references. | Full relevant suite/build(s), data/migration failure checks, fresh architecture/concurrency review and required device evidence. Scope whole-app/Release/widget checks to real impact. |

Small is not synonymous with low risk: a one-line store suspension, normalization change or stale-task guard is high risk. Upgrade routing immediately when evidence shows invariant/state/data effects. A UI task needing extra independent/device gates is medium/high risk; do not suppress those gates to meet a numerical small-task agent limit.

Avoid delegation when the outcome is narrow, understood, reversible and serial; when the main already has the needed context; when a deterministic tool can execute the check; when dependencies force repeated waiting/handoffs; or when required tools cannot provide evidence. A role definition alone is never a reason to spawn it.

### Safe parallelism and handoffs

Keep the existing cap of four children plus primary; it is a ceiling, not a target. Default serial execution. Before spawning, name purpose, expected independent value, allowed files, inputs/contracts, baseline, dependencies, evidence and stop condition. Prefer a fresh bounded context for independent work when supported; forward inherited history only when it is actually required and model/effort controls permit it.

Maintain explicit file leases, not just module labels. Include shared catalogs, previews, generated files, project settings and incidental tool output in the lease. Recheck status/diff when assigning and releasing. Never assign overlapping writes. One integrator accepts results after dependent interfaces settle; one test writer changes test files. Read-only investigations/reviews can overlap when meaningful; stale reviews need rechecking only after relevant subsequent changes.

Use isolated worktrees only when supported and useful. Current app tools expose managed-worktree operations; CLI feature listing reports worktrees experimental/false. Neither is evidence of a tested isolation workflow here. Creation would require later authorization/scope, the correct starting state and preserving dirty work; an ordinary worktree does not copy uncommitted/untracked inputs. No worktree was created for this audit. Shared simulators, Xcode workspaces, active defaults, debugger/profiling ports and services still need one operator even with separate checkouts/DerivedData.

Compact handoff: outcome/scope; exact IDs and approved input; files/baseline; relevant findings; required seams/dependencies; exact verification/result/evidence; performance/size impact or unmeasured status; cleanup; remaining blocker/next owner. Do not paste global rules, full logs or a repeated plan. Only the primary reports an AC/slice verdict after applicable current independent evidence; a low-risk main-only completion is not an independently passed AC.

## Verification design

Use repeatable tools/scripts for parsing, links, whitespace and mechanical checks; agents choose applicability and interpret failures. One designated final runner per source revision. Reuse a focused successful result when the relevant source/environment is unchanged; rerun after a material change, failure or unresolved concern. Test-author smoke checks are optional feedback, not an extra mandatory final run.

- Low risk: relevant static/diff check, source-specific focused compile/tests as necessary. Do not add tests that only mirror a cosmetic implementation.
- Medium: affected module tests, appropriate Debug/Release configuration, review only the meaningful architecture/state risks, directly affected UI evidence.
- High risk: all relevant builds/tests, independent semantic reviewer, save/reload/rollback/concurrent-attempt checks, migration fixtures if affected, media recovery protection if affected, physical/device evidence where the assigned criteria require it.
- Release required for release/project/resource changes, preview/configuration-sensitive changes, large/cross-cutting slices or explicit acceptance gates. A small routine production change does not automatically require a universal Release build. Widget build requires actual P-08/extension scope.
- Build/test tools remain plugin-first. Read actual schema, show defaults, discover an installed iOS 27 destination, isolate DerivedData/results under `/tmp`, disable simulator signing and preserve one active profile/operator. Use CLI/Apple fallback only for a recorded capability gap. No invented tool names or guessed UDID.
- Never substitute unit/source/simulator evidence for unexecuted input/RTL/accessibility, physical AC-65/66 or Duo checks. Block only the affected evidence case and report why.

For the eventual infrastructure implementation, validation is TOML/Markdown/discovery/consistency/source-preservation only. App builds, app tests and device runs remain unnecessary because no app source/project changes are approved.

## Model and reasoning strategy

Current state: project main model/effort unset; no role model pin; all 16 role efforts explicit (eight medium, eight high). The medium subagent default therefore does not lower the eight high-effort roles. No expensive global model/effort setting exists in the inspected project config. Host-selected main settings and account-specific consumption are unverified.

The offline CLI catalog and this session's collaboration catalog differ. Both expose `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna` and `gpt-6-astra`, with low/medium/high support; the session also exposes `gpt-6.1-sol`, `gpt-6-sol` and `gpt-6-luna`. A bundled catalog proves schema/catalog recognition, not account entitlement or relative Plus allowance cost. No recommendation pins a new model based on unmeasured multipliers.

Recommended main policy: use the user's available configured model; low/medium for bounded lookup, medium for normal implementation, high for difficult concurrency/identity/migration/debugging. No routine xhigh/max/ultra. Select supported effort through the host's settings when available; do not invent a project key for per-task switching.

Recommended child policy: inherit the available parent model initially and retain `agents.default_subagent_reasoning_effort = "medium"`. Keep high for the independent semantic reviewer, SwiftData integrity/migration, media integrity and difficult bug investigation. A future verified comparison could try an exposed lighter model such as `gpt-6-luna` in this desktop session or `gpt-5.6-luna` where actually selectable, on bounded mechanical/read-only work. This is a candidate experiment, not a claim about Plus savings or an approved model change.

Domain/composition/map/scene currently use high even for ordinary work. Optional P2 is to reduce routine defaults to medium only after a supported escalation route is proven. Fixed role fields take precedence and this session explicitly disallows overriding role effort. Until then, preserve high for delegated high-risk work and keep simple work with main; do not silently assume a spawn request will raise a medium role. Supported keys are `model`, `model_reasoning_effort`, `agents.default_subagent_model`, and `agents.default_subagent_reasoning_effort`; none is invented or changed during this audit.

## Cost optimization summary

The highest-value changes reduce work per task: eliminate routine tracer/investigator/test-author/build-runner handoffs; read relevant sections once; avoid full inherited child histories when bounded context suffices; load runtime/profile instructions only for an operator; activate modernization/security only for their actual tasks; use one scoped final execution; summarize evidence instead of copying logs.

Measured instruction inventory: AGENTS 22,352 bytes / 3,066 words; agent README 18,258 / 2,378; role files collectively 63,952 / 7,948. The repeated preamble is 506 bytes / 67 words per role. These totals are not all injected into every task and are not usage charges: role bodies are relevant only when loaded/spawned. Removing unused definitions is therefore a weaker strategy than preventing unnecessary activations. The mandatory reading set is 172,918 bytes / 23,960 words before feature/source context; section-based loading is the largest concrete context opportunity observed.

No tokenization, billed-token, task-duration or allowance comparison was performed. No percentage savings are proposed. After approval, compare matched routine/high-risk tasks using agents spawned, handoffs, loaded context, executed checks, turnaround and actual available usage telemetry. Do not rerun expensive app tasks merely to manufacture a benchmark. Text-size reductions can be measured directly after refactoring, but do not prove faster execution or lower account consumption.

## Proposed scenario evaluation (hypothetical; no execution)

| Scenario | Executor / children | Skills | Required verification | Avoided unnecessary work |
|---|---|---|---|---|
| 1. Small SwiftUI visual change | Main; zero children, or one relevant UI owner when expertise justifies it. Elevate if behavior/state/accessibility contract changes. | Project SwiftUI specialist, only affected reference; Liquid Glass for an approved glass surface; SDK 27 skill only for changed API/error. | Diff/static/local compile as appropriate, deterministic preview, directly affected visual/accessibility check if required; no full matrix unless AC demands it. | No tracer, investigator, independent style review, test-author pipeline or whole-app QA. |
| 2. SwiftData persistence bug | Main establishes path; SwiftData owner for substantial fix or main for bounded fix. Independent reviewer/build runner for atomicity/data risk; test author only for meaningful independent matrix. | Relevant persistence contracts; no generic SwiftUI/modernization/runtime skill for a store-only issue. | Regression proving real save/reload/rollback, duplicate/concurrent/stale-revision cases as affected, module tests and appropriate build. | No library UI owner unless feedback flow changes; no device QA for store-only behavior. |
| 3. Cross-module feature | Main plans owner/dependency map; tracer only if mapping is substantial; selected non-overlapping owners, tests, independent reviewer/final runner. | Only actual UI/widget/runtime skills required by feature. | Relevant full suite/build, contract/data checks, required UI/device evidence. Product/API changes approved first. | No automatic activation of every role; serial dependent interfaces, parallel independent modules only. |
| 4. Swift concurrency race | Main or investigator reproduces with deterministic seam; owning implementation layer fixes; fresh architecture/concurrency reviewer and final runner. | SwiftUI data-flow references only for UI state; debugger/leak/profile skill only if concrete runtime evidence is needed. | Controlled interleavings, cancellation/generation/lifecycle regression, Swift 6 compile, affected integration suite. Broader checks if shared ownership changes. | No wall-clock wait tests, unrelated QA, all-module refactor or profiling without a concrete need. |
| 5. Device-specific UX issue | Main narrows contract; one assigned QA/investigator operator; feature owner fixes, composition only if wiring required. | Exact project device skill + plugin debugger, relevant SwiftUI/SDK/glass reference. | Actual affected device/runtime/geometry/input actions and source-linked evidence; regression/model checks for state. Duo cases blocked if required environment absent. | No device-model implementation branches; no whole matrix for an isolated case unless the assigned AC requires it; one runtime operator. |

These examples evaluate the proposed policy, not executed workflows or acceptance results. Under the current unchanged policy, existing stricter ownership/gate rules still apply until approval.

## Implementation plan (approval required)

1. Approve P0 and P1 policy scope, especially main-agent small-task authority, risk-based clarification and conditional reading/final verification. Retain all roles and current project config.
2. Recheck status and snapshot the dirty infrastructure baseline. Edit core/routing first, then move runtime-only reference and update every backlink. Do not touch app/product files.
3. Clean role preambles and misleading sandbox fields; preserve unique ownership and specialist hazards. Narrow tests/investigator/tracer/settings activation; keep independent high-risk gates.
4. Refine five skill entry points; move security procedure last into its existing reference mechanism. Validate safety/approval/tooling coverage after the move. No new skill or operational server configuration.
5. Perform Phase D configuration-only validation after implementation: TOML syntax; Markdown fences/links; verified-key review; fresh role/skill discovery where tooling allows; consistency, leases, risk routing and source checksums. Test actual role/model permission behavior only with separately scoped authorization if a spawn is necessary; report unexecuted behavior UNVERIFIED.
6. Re-evaluate the five scenarios on paper and report implemented file changes/evidence. Compare text sizes without claiming performance gains. P2 model/default-effort experiments remain deferred unless explicitly approved with a supported escalation path.

## Complete inspection inventory and evidence record

Full policy/config reading: `AGENTS.md`, `README.md`, `docs/README.md`, `.codex/config.toml`, `.codex/agents/README.md`, all 16 `.codex/agents/projectalpha-*.toml`, all five `.agents/skills/*/SKILL.md`. Security entry point was read in bounded chunks; all referenced paths were checked for existence, not loaded as a security workflow.

Targeted documentation reading: docs 01 product/platform scope and engineering decisions; docs 03 architecture/ownership/concurrency; docs 04 invariants, exact duplicate and atomic/media sections; docs 08 slice table, test strategy, command/release/evidence sections and relevant AC rows; docs 09 local baseline; docs 10 ownership/current-state/verification and dated service evidence. Historical claims remain dated, not rerun. Docs 02/05/06/07 were inventoried but not fully read: no feature implementation or product decision is proposed.

Targeted source/project inspection: `ios/ProjectAlpha/ProjectAlpha.xcodeproj/project.pbxproj`; `ProjectAlpha/App/DI/AppContainer.swift`; `ProjectAlpha/Data/Persistence/LibraryStore.swift`; `ProjectAlpha/Data/Repositories/SwiftDataCollectionRepository.swift`; `ProjectAlpha/Presentation/Features/Home/ViewModel/CollectionEditorViewModel.swift`; `ProjectAlphaTests/CollectionWorkflowTests.swift`; `ProjectAlphaUITests/ProjectAlphaUITests.swift` (all below `ios/ProjectAlpha/`). Bounded method/import/fixture reads only. Filename inventory covered the relevant App/Domain/Data/test paths and workflow extensions; no whole Swift source scan.

Read-only tooling evidence:

- `git status --short --branch --untracked-files=all`: initial dirty state saved; final state recorded at completion.
- `command -v codex`, `codex --version`: `/opt/homebrew/bin/codex`, 0.155.1; restricted environment prints PATH-alias warning without preventing these reads.
- `codex --help`, `codex features --help`, `codex debug --help`, `codex app-server --help`, `codex debug models --help`, `codex debug prompt-input --help`, `codex doctor --help`: help only; no doctor, daemon or inference execution.
- `codex --strict-config features list`: exit 1, unsupported flag for this subcommand. Plain `codex features list`: exit 0. `codex debug models --bundled`: exit 0, filtered offline catalog inspected.
- `xcode-select -p`: `/Applications/Xcode.app/Contents/Developer`; no Xcode version/runtime refresh or build. Project-setting `rg` confirms target settings; it does not evaluate a build configuration.
- `rg --files` in named workflow paths reported `.github` and `scripts` absent; Python existence checks confirmed absence. Narrow workflow-artifact search returned no shared schemes/test plans/xcconfigs/scripts. No CI execution.
- Python 3.9.6 stdlib copied and SHA-256 hashed inspected policy/config/docs into `/tmp/projectalpha-codex-agent-audit-20261014/`; computed bytes/word counts; all 33 named reference/script paths exist; personal/project device skill byte comparison differs.
- Current tool metadata confirms Apple Xcode and plugin session/build/test/UI capabilities, `persist:false`, named defaults profiles and extra build args. Security task API names are absent. No MCP tool was called to build, test or interact with a device.
- Official OpenAI pages fetched as cited above. Markdown endpoint fetch failed with unsupported content type; HTML pages provided the cited evidence. No unrelated web searches or third-party sources.

Final artifact-only hygiene/status results are appended below. These checks protect the requested checkpoint and are not Phase D runtime validation of a refactored system.

## Remaining work and next recommended action

Phases A/B are complete. Review and explicitly approve the P0/P1 proposal, or narrow its scope. No implementation work begins until approval. P2 is optional/deferred. Runtime permission/model/discovery behavior beyond the observations above remains UNVERIFIED; application acceptance remains outside this task.

Assigned scope: Codex infrastructure audit/proposal only. AC/INV/D: no IDs or requirements changed and no AC marked passed; retained safeguards reference INV-01–09, D-01–06/09–13/15–17/19–20 and AC-01/02/57–60/65/66 as applicable. Changed repository file: this checkpoint only. Manual checks: textual ownership/precedence/scenario analysis; no app/device/RTL/accessibility/participant checks. Performance/size impact: no runtime/assets/dependencies changed; expected app impact negligible, unmeasured. Approved deviation: the user explicitly permits main-agent checkpoint edits during this audit, overriding any requirement to delegate this documentation artifact. No other deviation.

## Final checkpoint hygiene results

- `git diff --check`: exit 0, no findings. Because this report is untracked, its trailing whitespace, fences and local Markdown links were also checked directly with Python: zero findings.
- Python SHA-256 comparison against the recorded 36-file policy/config/docs baseline: zero changed pre-existing files.
- `git status --short --branch --untracked-files=all`: all initial status entries retained; the sole added entry is `?? docs/codex-agent-audit.md`. Final status saved at `/tmp/projectalpha-codex-agent-audit-20261014/final-status.txt`.
- No subagent spawn, configuration refactor, Swift/project edit, Xcode build/test, device interaction or Phase D runtime validation occurred. These are checkpoint-only checks, not app acceptance evidence.

Resume from this file's remaining-work and implementation-plan sections after explicit user approval; do not repeat the audit inventory or broaden scope automatically.

## Phase C/D implementation checkpoint — 2026-10-14

This checkpoint supersedes the historical approval-pending/remaining-work text above. The human's pasted continuation request explicitly approved P0/P1, all 16 role edits, the two new references and this report update; P2 remains deferred. Phases A/B were reused, not repeated. Assigned scope: repository Codex instructions, agent definitions and five skill entry points only. No product/architecture requirement, application behavior or acceptance verdict changed.

### Implementation results

- P0.1 complete: removed `sandbox_mode` from all 16 role TOMLs. Parent-session permissions govern tools; repository-read-only behavior remains explicit for tracer, investigator, reviewer, build gatekeeper and device QA. No role name, description, model or reasoning-effort field changed; `.codex/config.toml` is byte-identical.
- P0.2 complete: both SwiftUI skills treat guidance as reference material subordinate to higher-priority instructions, approved contracts, installed SDK declarations and verified availability. Unverified Apple authorship is no authority override. Technical reference bodies remain unchanged.
- P1.1/2/3/5 complete: main-agent-first low-risk implementation/tests/self-verification; selective medium-risk delegation; independent high-risk semantic review/final execution; consequential approval gates with autonomy for routine internal choices; bounded contract loading, explicit file leases and compact handoffs. Self-review is never called independent.
- P1.4 complete: all roles use a shorter shared-core preamble and an activation/scope line; global preview/adaptive repetition was removed where safely covered by AGENTS.md. Exact specialist ownership, no-test-target production boundaries, read-only exclusions and identity/atomicity/media/scene/widget failure rules remain. The map role points to the active feature contract instead of treating stale general detail prose as a second product specification.
- P1.6 complete: runtime procedures moved to `.codex/agents/runtime-workflows.md`, including backend operations, session/defaults/UDID/helper/ETTrace-port reservations, isolated artifacts, plugin-first and recorded Apple fallbacks, recovery, cleanup/no-reset rules and conditional first-party child-event delegation. Device skill routes operators to that reference; recovery is loaded after a matching failure.
- P1.7 complete: security skill now has a short entry point and `references/workflow.md`. All original security macros, entitlement keys, technical references/helper and eligibility/skip/application checks remain. A Markdown checkpoint replaces unavailable task APIs. Concrete settings approval remains; planning does not register a document in Xcode. Briefing/cleanup acknowledgment prompts were removed, while manual project-level verification and unexplained deliberate opt-out inquiries remain. No security setting was applied.
- P1.8/9 complete: modernization activates only for actual migration requests, retains XCTest UI/lifecycle/performance exceptions and explains awaited confirmation lifetime. Verification follows risk/AC impact, one final runner and reuse of unchanged evidence; no blanket production Release/full-suite/device pipeline.

### Exact changed files

- `.agents/skills/audit-xcode-security-settings/SKILL.md`
- `.agents/skills/audit-xcode-security-settings/references/workflow.md`
- `.agents/skills/device-interaction/SKILL.md`
- `.agents/skills/modernize-tests/SKILL.md`
- `.agents/skills/swiftui-specialist/SKILL.md`
- `.agents/skills/swiftui-whats-new-27/SKILL.md`
- `.codex/agents/README.md`
- `.codex/agents/projectalpha-acceptance-test-engineer.toml`
- `.codex/agents/projectalpha-architecture-concurrency-reviewer.toml`
- `.codex/agents/projectalpha-bug-investigator.toml`
- `.codex/agents/projectalpha-build-verification-gatekeeper.toml`
- `.codex/agents/projectalpha-composition-integrator.toml`
- `.codex/agents/projectalpha-contract-maintainer.toml`
- `.codex/agents/projectalpha-device-ux-qa.toml`
- `.codex/agents/projectalpha-domain-policy-engineer.toml`
- `.codex/agents/projectalpha-library-workflow-engineer.toml`
- `.codex/agents/projectalpha-local-media-engineer.toml`
- `.codex/agents/projectalpha-map-location-services-engineer.toml`
- `.codex/agents/projectalpha-scene-navigation-engineer.toml`
- `.codex/agents/projectalpha-settings-localization-accessibility-engineer.toml`
- `.codex/agents/projectalpha-spec-tracer.toml`
- `.codex/agents/projectalpha-swiftdata-library-engineer.toml`
- `.codex/agents/projectalpha-widget-integration-engineer.toml`
- `.codex/agents/runtime-workflows.md`
- `AGENTS.md`
- `docs/codex-agent-audit.md`

No additional repository file is in the change scope. Both new files were absent at baseline. The audit's original content is preserved verbatim; this checkpoint is appended.

### Configuration-only validation

Commands used from the repository root (scripts/results are outside the repository):

1. `git status --short --branch --untracked-files=all` at start and completion. Initial state was `main...origin/main` with only `?? docs/codex-agent-audit.md`. An index entry for that audit appeared during work before this append; its staged blob matched the original snapshot. No staging/unstaging/commit command was issued. That original index entry is preserved; this appended checkpoint remains an unstaged edit.
2. `/Users/hoanghieple/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 /tmp/projectalpha-agent-optimization-20261014/validate.py`: exit 0, 247 checks with zero failures after this report append; TOML parsing, all 16 names/unchanged settings, 69 local links/anchors, 17 skill code-reference paths, Markdown fences/whitespace, ownership/read-only restrictions, safety coverage and protected SHA-256 comparisons. Final post-report results are recorded in `validation.json`.
3. `ruby /tmp/projectalpha-agent-optimization-20261014/validate-skills.rb`: exit 0; Ruby Psych parsed all five YAML frontmatters, each with string name/description. Exact program/output and metadata are retained in `validate-skills.rb`, `yaml-validation.txt` and `skill-discovery.json`. The Python skill-creator quick validator was unavailable because PyYAML is absent; the standard YAML parser plus local structural/reference checks supplied the configuration validation instead. No dependency was installed.
4. `git diff --check`: exit 0; newly created references and the audit are also directly checked because Git does not cover every untracked file. Original protected AGENTS sections (Swift headers, architecture boundaries, performance/size, adaptive UI and product invariants/exclusions) compare byte-for-byte to the baseline. All four originally read-only skill files retain filesystem mode `0444`; the device skill retains `0644`.
5. Manual policy review: scope, permissions wording, ownership/lease separation, clarification, selective loading, independent high-risk review, final-run applicability, runtime recovery and security approval/skip rules checked against the approved audit. Security macro/entitlement/reference coverage also compared mechanically.

The task snapshot is `/tmp/projectalpha-agent-optimization-20261014/baseline/`, with inventory/checksums in `inventory.json` and original tracked-file hashes in `tracked-checksums.json`. Evidence includes `validation.json`, `instruction-sizes.json`, `skill-discovery.json`, initial/final status and the original staged audit hash. The temporary implementation/validation scripts are retained there for reproducibility; none is added to the repository.

Discovery boundary: all 16 agent names and all five project skills were advertised in this session at task start, and their edited files/metadata now parse and retain the same names. Fresh desktop reload, effective project trust, child permission behavior and actual revised-role execution were not tested. Static presence/parsing is not a live discovery/behavior pass. No subagent, Codex inference, web research, app build/test, runtime/device session or benchmark was run.

An initial automatic approval review rejected the role-edit script as possible broad permission weakening. Read-only evidence from the human's exact P0.1 authorization and the recorded parent-permission contract established its scope; review then permitted the retry. No permission bypass occurred. Subsequent filesystem write failures identified local `0444` modes; only the approved local files were temporarily made owner-writable and their original modes restored. No personal/global configuration or skills changed.

### Five policy simulations

These are instruction/routing evaluations, not application tests or AC passes.

| Scenario | Executor / necessary agents | Applicable context/skills | Required verification and avoided work | Result |
|---|---|---|---|---|
| A. Small SwiftUI visual change | Main; normally zero children, with delegation only for meaningful expertise. Escalate if behavior/state/accessibility contracts change. | Affected UI contract, SwiftUI specialist reference; SDK 27 only for changed APIs/errors; Liquid Glass for approved surfaces. | Diff/static/focused compile as appropriate, deterministic preview and assigned visual/input evidence. No routine tracer/investigator/test-author/reviewer/full-suite/device matrix. | Policy consistent |
| B. SwiftData persistence bug | Main traces the real failure; main may implement a bounded fix or select SwiftData owner for substantial work. Integrity risk requires separate semantic reviewer and final runner; test specialist for complex independent failure design. | Affected docs 03/04/08 and store/repository/tests. No incidental SwiftUI, modernization or device skill. | Real save/reload/rollback and affected duplicate/stale/concurrent cases; relevant tests/build and independent gates. No store-only device QA or unrelated UI owner. | Policy consistent |
| C. Cross-module feature | Main maps dependencies and approved decisions; selective non-overlapping owners plus independent reviewer/final runner. Tracer only when mapping is substantial; test owner when useful for substantial coverage. | Exact active U/D/INV/P/AC sections, interfaces and file leases; only actual feature skills. New public/product contracts need prior approval. | Relevant full tests/builds, cross-boundary data checks and assigned device evidence. Serialize dependent interfaces; do not activate all roles. | Policy consistent |
| D. Swift concurrency race | Main or investigator establishes deterministic reproduction; owning layer fixes; separate architecture/concurrency reviewer and final runner required. | Relevant lifetime/isolation contracts; SwiftUI data-flow only for UI state; runtime debugging/profiling only for a concrete evidence need. | Controlled interleavings/cancellation/generation/lifecycle regressions, Swift 6 compilation and affected integration/full gates. No sleep-based correctness tests, unrelated QA or broad refactor. | Policy consistent |
| E. Device-specific UX issue | Main narrows contract; one assigned QA/investigator runtime operator, feature owner fixes; composition only for wiring. First-party child-event delegation only when the session requires it. | Project device skill/runtime reference, debugger and relevant SwiftUI/SDK/glass guidance. | Actual affected geometry/input/accessibility/runtime actions tied to current build/source; state regression and review if meaningful. Required Duo environment absent means BLOCKED, not substitute evidence; no automatic whole-app matrix. | Policy consistent |

### Before/after instruction sizes

UTF-8 bytes / whitespace-separated words, measured from the task snapshot. These are text sizes, not tokenizer, billed-token or Plus-allowance measurements. Audit-report text and unchanged technical references are excluded.

| Instruction file/group | Before bytes / words | After bytes / words |
|---|---:|---:|
| `.agents/skills/audit-xcode-security-settings/SKILL.md` | 59,187 / 8,173 | 3,427 / 434 |
| `.agents/skills/audit-xcode-security-settings/references/workflow.md` | 0 / 0 | 53,946 / 7,168 |
| `.agents/skills/device-interaction/SKILL.md` | 7,877 / 1,145 | 2,999 / 354 |
| `.agents/skills/modernize-tests/SKILL.md` | 9,464 / 1,322 | 10,586 / 1,460 |
| `.agents/skills/swiftui-specialist/SKILL.md` | 4,895 / 656 | 5,121 / 678 |
| `.agents/skills/swiftui-whats-new-27/SKILL.md` | 5,120 / 634 | 5,260 / 643 |
| `.codex/agents/README.md` | 18,258 / 2,378 | 8,947 / 1,043 |
| `.codex/agents/runtime-workflows.md` | 0 / 0 | 18,477 / 2,529 |
| `AGENTS.md` | 22,352 / 3,066 | 24,296 / 3,201 |
| All 16 role TOMLs | 63,952 / 7,948 | 58,527 / 7,133 |
| Total policy set, including both new references | 191,105 / 25,322 | 191,586 / 24,643 |

The core grew to make authorization, risk and independence explicit. Most entry-point reduction comes from routing/security/device text moved behind conditional references; the entire policy set is not materially smaller in bytes. Five skill descriptions were preserved except the SwiftUI specialist's misleading authority claim corrected under P0. No P2 metadata-shortening/typo or model-effort experiment was performed. These changes aim to avoid unnecessary activations, whole-file reads, approval turns and redundant checks; no token/usage savings are claimed.

### Preserved contracts, limitations and follow-up

AC/INV/D impact: no IDs or requirements changed and no application AC/slice marked READY/PASSED. Preserved safety coverage includes INV-01–09, exact duplicate policy, atomic save/rollback/publication, committed-media ordering, stable drafts, separate scene/map ownership, Swift 6 and iPhone/iPad settings, D-01–06/09–13/15–17/19–20 and relevant AC-01/02/57–60/65/66. Approved deviation: the human explicitly allows main-agent infrastructure/checkpoint edits and the new low-risk execution policy; no product-contract deviation.

Application source/tests/project/config, product docs 01–10 and top-level README remain checksum-identical. Expected app runtime/asset/installed-size impact is negligible because none changed; it is unmeasured. Manual checks were textual policy/scenario review only; no device/accessibility/RTL/widget/performance/participant testing.

Remaining risks: incorrect future risk classification could omit a required gate; role read-only restrictions remain behavioral under parent permissions; dormant references must actually be loaded by runtime/security operators. Fresh discovery, effective sandbox/model inheritance, installed API behavior and runtime workflows remain UNVERIFIED. P2 remains deferred: model/reasoning changes, metadata shortening/typo cleanup and personal/project duplicate-skill cleanup. No further implementation is required for approved P0/P1; future live-task observations can validate routing/discovery without adding an unnecessary benchmark now.
