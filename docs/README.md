# ProjectAlpha design specification

Version: 1.5 • Updated: 2026-10-01 • Language: English

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

## Documentation verification

Validation on 2026-10-01: documentation links resolve, code fences are balanced, U-01 through U-31, D-01 through D-20 and AC-01 through AC-66 each occur once in order, and `git diff --check` passes. U-27/D-18 remain as retired identifiers; no acceptance criterion is marked passed by this documentation change.

No app build, automated app tests or device checks were run for this documentation-only update. The current-state statement in document 10 remains based on its recorded source/project-setting inspection; this documentation change does not establish implementation or pass status for AC-01, AC-02, AC-64 or any other criterion.

## Implementation records

- [Scaffold architecture alignment and verification](10-scaffold-architecture-verification.md): ownership, preferences, Domain boundaries and focused validation of the existing code.
