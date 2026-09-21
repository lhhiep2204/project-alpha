# ProjectAlpha design specification

Version: 1.0 • Updated: 2026-09-20 • Language: English

This is the implementation specification for a new, independent app. It describes the intended product, not functionality already implemented. The iOS repository currently contains a three-tab scaffold. No application code was changed when preparing this specification.

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

## Rules for implementing this design

1. Read documents 01, 03, 04 and the relevant feature document before implementing a slice. Use document 08 for its dependencies and acceptance criteria.
2. `U-*` decisions were explicitly confirmed by the product owner. `D-*` decisions are engineering choices in this design; do not present them as direct user quotations. `FUTURE` means a documentation placeholder, not an implementation task.
3. Preserve user-visible requirements when adapting implementation to the SDK. If a change affects behavior, data identity or feature scope, update the decision and its acceptance criteria together.
4. Keep Home's Collection Map and the global Map tab separate in navigation and state. Reuse components and use cases, not their mutable screen state.
5. A widget location tap always opens the global Map tab. Saving from Collection Map into another collection never changes the map's collection scope.
6. No backend, authentication, CloudKit sync or Android implementation belongs in the first release. Local data and media must work without an account.
7. Do not claim a feature or acceptance criterion is implemented until code and its specified verification exist. This documentation task does not establish an app build/test pass.

## Reading by task

| Task | Required additional documents |
|---|---|
| Collection/Location CRUD | 02, 04, 08 |
| Map, search or location detail | 02, 05, 06, 09 |
| Router, deep link or scene lifecycle | 05, 07, 08 |
| Widget | 04 snapshot boundary, 05, 07, 09 |
| Persistence, images or concurrency | 03, 04, 08 |
| Future Android/backend work | 01 exclusions, 03 future boundaries; obtain a new feature specification |

## Definition of readiness

The product questions raised during discovery are resolved for the documented v1 scope. This includes quick capture, duplicate-warning behavior, local-only/no-in-app-backup limits and supported capture sources. Saved coordinates are fixed after creation. This readiness applies to specification and implementation planning; actual usability still requires the task-based participant and device validation in document 08. Release identifiers, signing, support email and privacy/support URLs remain release configuration values; they do not block architecture or local feature implementation. See document 08 for release gates.

## Documentation verification

Validation on 2026-09-20: documentation links resolve, code fences are balanced, and all 56 acceptance IDs are present exactly once in order. Documentation whitespace checks pass.

No app build or automated app tests were run for this documentation-only delivery. A repository-wide `git diff --check` also reported existing extra blank lines at EOF in `CollectionItemView.swift` and `CommonKeys.swift`; those unrelated source edits were preserved.

## Implementation records

- [Scaffold architecture alignment and verification](10-scaffold-architecture-verification.md): ownership, preferences, Domain boundaries and focused validation of the existing code.
