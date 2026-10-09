# ProjectAlpha design specification

Version: 1.8 • Updated: 2026-10-09 • Language: English

This is the implementation specification for a new, independent app. It describes the intended product, not functionality already implemented. The iOS repository began with a three-tab scaffold; current implementation facts are recorded separately in document 10.

## Start here

| Order | Document | Purpose |
|---|---|---|
| 1 | [Product and decisions](01-product-and-decisions.md) | Confirmed scope, vocabulary, v1 features and explicit exclusions |
| 2 | [Screens and journeys](02-screens-and-journeys.md) | User-visible behavior, forms, error and empty states |
| 3 | [System and iOS architecture](03-system-and-ios-architecture.md) | Clean Architecture, ownership, concurrency, future platforms |
| 4 | [Data and duplicate detection](04-data-and-duplicate-detection.md) | Entities, invariants, SwiftData writes, media lifecycle |
| 5 | [Navigation and deep links](05-navigation-and-deep-links.md) | Tab paths, modal coordination, widget entry, restoration |
| 6 | [Map and location detail](06-map-and-location-detail.md) | The two map contexts, camera, search, adaptive detail UI |
| 7 | [Widgets](07-widgets.md) | App Group snapshot, refresh, configuration, tap contracts |
| 8 | [Implementation and verification](08-implementation-and-verification.md) | Ordered delivery slices, acceptance criteria and test matrix |
| 9 | [Apple technology references](09-apple-technology-references.md) | Verified platform baseline, official references and SDK checks |
| 10 | [Scaffold architecture alignment](10-scaffold-architecture-verification.md) | Verified current implementation state; not the target product contract |

## Rules for implementing this design

1. Read documents 01, 03, 04 and the relevant feature document before implementing a slice. Use document 08 for its dependencies and acceptance criteria.
2. `U-*` decisions were explicitly confirmed by the product owner. `D-*` decisions are engineering choices in this design; do not present them as direct user quotations. `FUTURE` means a documentation placeholder, not an implementation task.
3. Preserve user-visible requirements when adapting implementation to the SDK. If a change affects behavior, data identity or feature scope, update the decision and its acceptance criteria together.
4. Keep Home's Collection Map and the global Map tab separate in navigation and state. Reuse components and use cases, not their mutable screen state.
5. A widget location tap always opens the global Map tab. Saving from Collection Map into another collection never changes the map's collection scope.
6. No backend, authentication, CloudKit sync or Android implementation belongs in the first release. Local data and media must work without an account.
7. Do not claim a feature or acceptance criterion is implemented until code and its specified verification exist. This documentation task does not establish an app build/test pass.
8. Every app and widget surface follows current Apple Human Interface Guidelines and adapts from available space, size classes and scene geometry. Preserve three top-level destinations while allowing the system to present them as tabs or a sidebar; never branch UI from device model, idiom, orientation, `UIScreen.main` or fixed screen breakpoints.
9. Use Apple-native containers and controls first. Verify every proposed SDK symbol and availability against the installed SDK and compile a focused use; do not invent an iPhone Duo API or silently change the deployment target when the local toolchain does not yet expose it.
10. Treat fast launch/interactions, smooth UI and lightweight installation as high-priority requirements in every slice (U-31, D-20). Record comparable performance and size evidence for release acceptance (AC-65/66); do not claim a target or size cap without measurements.

## Reading by task

| Task | Required additional documents |
|---|---|
| Collection/Location CRUD | 02, 04, 08 |
| Map, search or location detail | 02, 05, 06, 09 |
| Router, deep link or scene lifecycle | 05, 07, 08 |
| Widget | 04 snapshot boundary, 05, 07, 09 |
| Persistence, images or concurrency | 03, 04, 08 |
| Adaptive UI, iPad, iPhone Duo, accessibility or input | 01, 02, 05, 06, 07 when widgets apply, 08, 09, 10 |
| Future Android/backend work | 01 exclusions, 03 future boundaries; obtain a new feature specification |

## Definition of readiness

The product questions raised during discovery are resolved for the documented v1 scope. This includes quick capture, duplicate-warning behavior, local-only/no-in-app-backup limits, supported capture sources, the initial default-collection title and its edit/delete protection, a fixed folder symbol without collection icon/cover data, animated collection-row deletion and an immediately visible location-list title. Saved coordinates are fixed after creation. This readiness applies to specification and implementation planning; actual usability still requires the task-based participant and device validation in document 08. Release identifiers, signing, support email and privacy/support URLs remain release configuration values; they do not block architecture or local feature implementation. See document 08 for release gates.

## Approved delivery refinement

On 2026-10-06 the product owner approved a service-only location/Apple Maps foundation before full P-06 UI integration. Documents 01, 02, 06 and 08 record its initial one-shot freshness/timeout policy and subsequent approved refinements, accepted Reduced Accuracy metadata, provider operations, early dependencies and deterministic test expectations. The permission-denial dialog and Settings action belong to the incremental Global Map UI approved on 2026-10-07. This approval does not establish implementation or acceptance pass status.

The 2026-10-07 approval adds incremental Global Map UI before the remaining full P-06 screens: first-entry authorization/current-position camera, explicit recenter and denial recovery, native user-location display and reusable nonblocking toast. Documents 01, 02, 06 and 08 refine U-07/U-10 and AC-37 together; full P-06 saved pins/search/save/detail and device gates remain required. No implementation or acceptance status is inferred.

The 2026-10-08 approval refines the common toast: public SwiftUI Liquid Glass capsule with fully rounded ends, always-centered message text and swipe-up dismissal replacing the visible close button, using Apple's Focus-mode toast as a visual/interaction reference. Documents 01, 02, 06 and 08 update U-07/U-10 and AC-37 together while preserving D-17 accessibility alternatives, Reduce Transparency/Motion, existing automatic-dismissal timing and partial P-06 scope. No implementation or acceptance status is inferred.

On 2026-10-09 the product owner approved accepting the first geographically/metadata-valid one-shot position fix with a finite nonfuture timestamp regardless of past age. Permission checks and Reduced Accuracy remain; at that approval the 5-second timeout started after authorization, with no old-fix fallback, persistent cache or background refresh. Documents 01, 02, 06 and 08 refined U-07/U-10 and AC-37 together. A later 2026-10-09 approval increases the timeout to 10 seconds while preserving these other semantics; it is recorded below. No implementation or acceptance status is inferred.

On 2026-10-09 the product owner approved increasing the post-authorization timeout from 5 to 10 seconds, still excluding permission-prompt time. Past otherwise-valid fixes remain accepted immediately regardless of age, and timeout still has no cached/old-fix fallback. Documents 01, 02, 06 and 08 update U-10/AC-37; the earlier 5-second verification is dated in document 10 and does not verify this newer timeout. No acceptance status is inferred.

## Documentation verification

Validation on 2026-10-01: documentation links resolve, code fences are balanced, U-01 through U-31, D-01 through D-20 and AC-01 through AC-66 each occur once in order, and `git diff --check` passes. U-27/D-18 remain as retired identifiers; no acceptance criterion is marked passed by this documentation change.

No app build, automated app tests or device checks were run for this documentation-only update. The current-state statement in document 10 remains based on its recorded source/project-setting inspection; this documentation change does not establish implementation or pass status for AC-01, AC-02, AC-64 or any other criterion.

The 2026-10-06 service-contract refinement passed local Markdown-link, fence, whitespace and ordered U/D/INV/AC declaration checks plus `git diff --check`. No new IDs were added. This documentation check did not run app builds, tests, live provider requests, device UI, accessibility or performance measurements; current implementation evidence remains separate.

The 2026-10-07 Global Map UI contract refinement passed local Markdown-link, fence, whitespace and ordered unique U/D/INV/AC declaration checks plus `git diff --check`. No IDs were added and no criteria were marked passed. Apple platform reference pages were requested, but the web reader returned JavaScript-only content; this documentation update does not assert new API availability, app/device validation, performance or size measurements.

The 2026-10-08 toast refinement passed local Markdown-link, balanced-fence, trailing-whitespace and ordered unique U/D/INV/AC declaration checks plus `git diff --check`. No IDs were added and no criteria were marked passed. Official Apple materials, accessibility, layout, iOS, iPadOS and iPhone Duo pages were requested but returned JavaScript-only bodies; the custom Liquid Glass Markdown endpoint was unavailable to the web reader. SDK declarations and focused compilation remain implementation-gate requirements. This documentation-only change adds no runtime work or bundled assets; its expected runtime/footprint impact is negligible and unmeasured. No app builds, tests, device/input/accessibility checks or performance/size measurements were run for this documentation update.

The 2026-10-08 product-owner approval changes U-25 so the protected default collection's displayed title follows the currently selected app language, and refines U-28 so its Home row never displays or announces a creation date/time, including when another row collides. Documents 01, 02, 04 and 08 update U-25/U-28 and AC-01/AC-52 together; non-default row date/time disambiguation remains. No IDs were added and no acceptance criteria were marked passed. This documentation-only change adds no runtime work or bundled assets; expected performance and footprint impact is negligible and unmeasured. No app builds, tests, device checks or performance/size measurements were run.

## Implementation records

- [Scaffold architecture alignment and verification](10-scaffold-architecture-verification.md): ownership, preferences, Domain boundaries and focused validation of the existing code, including the 2026-10-07 location/Apple Maps service foundation record.
