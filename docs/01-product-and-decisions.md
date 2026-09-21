# Product and decisions

Status: approved design baseline. Product decisions below reflect discovery decisions confirmed on 2026-09-20.

## Product intent

ProjectAlpha saves and organizes places in collections for everyday use, travel planning and field work with location notes. The primary v1 task is to capture a valid place quickly and enrich it later. Home is the entry to the personal library. A map pushed from a collection supports focused exploration; the Map tab supports exploration across the entire library. All user records and attached images are stored locally.

The first implementation targets iPhone on iOS 27 and iPad on iPadOS 27. There is no compatibility requirement for earlier OS releases, macOS, visionOS, watchOS or Android in this delivery.

## Confirmed decisions

| ID | Requirement |
|---|---|
| U-01 | ProjectAlpha is a standalone app and repository with its own data store, bundle identity, URL scheme and App Group. |
| U-02 | SwiftData local persistence. No backend server, login, cloud storage or synchronization in the first release. |
| U-03 | Three tabs: Home, Map and Settings. Keep the existing three-tab foundation. |
| U-04 | Home → Collection Detail/location list → Collection Map. Tapping a location opens its detail on that map, alongside other locations in the same collection. |
| U-05 | Collection Detail has Show All on Map. It fits the camera to all locations in the collection. |
| U-06 | Collection Map initially targets its own collection when saving. The user may choose another destination collection; this changes only the save destination. |
| U-07 | The Map tab displays saved locations across all collections and supports searching and saving places. |
| U-08 | Each saved Location record belongs to exactly one Collection. Keep a default collection that cannot be deleted. Deleting another collection deletes its locations. |
| U-09 | Prevent duplicate places within a collection. Allow independent records for the same place in different collections. |
| U-10 | Keep favorites, notes, location photos, collection images/icons, arbitrary map pins, distance/ETA, external directions, location sharing, widgets and deep links. |
| U-11 | Sharing a location uses the system share sheet and an Apple Maps link. Account-based collection sharing and collaboration are future placeholders. |
| U-12 | iPhone detail uses a bottom sheet; wide iPad uses an adjacent detail panel, adapting to a sheet when narrow. Closing detail keeps the map open. |
| U-13 | Collection Map hides the tab bar and uses Back to return to its collection's location list. |
| U-14 | Widget location taps open the global Map tab, selecting the location and presenting its detail. |
| U-15 | Collection Map searches saved locations in that collection plus Apple Maps. Global Map searches all saved locations plus Apple Maps. |
| U-16 | Keep Favorites and configurable Collection Home Screen widgets: Small, Medium, Large, plus Extra Large on iPad. Widgets display and open content; editing from widgets, Lock Screen widgets, Siri/Shortcuts are future scope. |
| U-17 | Native SwiftUI with Liquid Glass. Support the 20 languages listed below. Documentation is entirely English. |
| U-18 | Document Android and backend architecture only as future placeholders. |
| U-19 | Without a reliable Place ID match: same normalized coordinate and name is a blocking duplicate; otherwise proximity within 20 metres produces a possible-duplicate warning. A same name at a remote coordinate does not warn by itself. |
| U-20 | Optimize v1 for quick capture. A resolved candidate can be explicitly saved to its visible destination without first completing optional custom name, notes or photos. |
| U-21 | In-app Apple Maps search, dropped pins, manual coordinates and current position are sufficient capture sources for v1. Receiving external map links and bulk import remain future scope. |
| U-22 | Local-only storage without in-app backup/restore is an accepted v1 limitation. Settings must state that there is no in-app sync or backup/restore; do not imply verified device-backup behavior. |

## Vocabulary

| Term | Meaning |
|---|---|
| Place | A real-world destination or selected geographic point. It need not be saved. |
| Place candidate | Resolved search result, POI, current position or dropped pin; no collection ownership yet. |
| Search suggestion | A provider suggestion requiring resolution before saving. It is not a coordinate-bearing Location. |
| Saved Location | A persistent, independently editable record with a UUID and one owning collection. |
| Collection Detail | The list of saved locations in a collection; not the map detail sheet. |
| Collection Map | Map pushed on Home's navigation stack; its saved-location scope is fixed to one collection. |
| Global Map | Root map in the Map tab; its saved-location scope is the entire library. |
| Save destination | Collection chosen in a new-location draft. Independent of map scope. |
| Location Detail | Read/view actions for one saved location or place candidate, presented over/beside a map. |
| Favorite | A Boolean on a saved Location, not another collection or ownership relation. |

## Feature scope

| Feature | ProjectAlpha v1 requirement |
|---|---|
| Collection CRUD | Home is the collection list; support create, edit and protected deletion |
| Default collection | Guarantee exactly one through persistence bootstrap |
| Location CRUD and moving collection | Support local create, edit, move and delete; check duplicates on create and move; saved coordinates are fixed |
| Favorites | Store independently on each saved record and expose in lists, detail and widget |
| Notes and custom name | Support local editing and persistence |
| Location photos | Support up to five local photos with transactional media handling |
| Collection image/icon | Support one local photo or built-in symbol |
| Search | Search saved places in the active scope and search Apple Maps separately; Home exposes an entry to global saved-place search |
| Arbitrary pin/coordinate entry | Support dropped pins and manual coordinate input when creating a location; saved coordinates are fixed |
| Distance and ETA | Show route mode and useful failure state when route estimates are unavailable |
| External directions | Support Apple Maps and Google Maps handoff without an embedded third-party map SDK |
| Share location | Preview the composed payload, exclude notes by default, then use the system share sheet with an Apple Maps URL; no account required |
| Home Screen widgets | Favorites and configurable Collection widgets; route location taps to Global Map |
| Settings | Language, map type, distance unit and a concise local-storage limitation shared consistently by the app and widgets |
| Provider category | Display and include in search; tag editing and additional category filters are future scope |
| Online accounts, sync and collaboration | FUTURE only |

The v1 feature set is defined by U-10, U-16 and this table. Future placeholders are not implementation requirements.

## Engineering decisions

| ID | Decision and reason |
|---|---|
| D-01 | Clean Architecture + observable presentation models; pure Domain, Data implements Domain contracts, manual DI. Apple does not mandate MVVM or Clean Architecture. |
| D-02 | One app-owned SwiftData store actor serves all features. Writes validate and commit as one operation without suspension inside the critical section. |
| D-03 | Each scene owns navigation; each map instance owns camera/search/detail state. Repositories and committed data are shared. |
| D-04 | Push routes carry stable IDs. A scene coordinator handles external intents, modal transitions and unsaved drafts. |
| D-05 | Widgets read a versioned App Group snapshot, not the live SwiftData database. Publish after successful commits. |
| D-06 | Deduplicate by provider identity and known aliases; apply U-19 when an identity comparison cannot establish equivalence. Detailed normalization is in document 04. |
| D-07 | A new global-map save defaults to the protected default collection. A new Collection Map save defaults to its scope collection every time. No hidden last-used destination. |
| D-08 | When Collection Map saves into another collection, retain the original scope and show a confirmation naming the destination. Do not insert an out-of-scope saved pin. |
| D-09 | CRUD uses explicit Save/Cancel drafts and destructive confirmation. No five-second delete undo or sync tombstones in v1. |
| D-10 | Use versioned local schema from v1, local media tokens, explicit error propagation and repairable widget/media projections. |
| D-11 | Support resizing/multitasking and scene-isolated state. Do not add an Open New Window feature in v1; if the system creates another scene it must not corrupt state. |
| D-12 | Base libraries are Apple frameworks. Add no general routing/DI/state library or remote analytics SDK by default. |
| D-13 | Candidate detail owns one stable draft and exposes explicit `Save to {collection}` plus optional `Add Details`. Both paths use the same commit-time validation and duplicate policy; quick capture is not autosave. |
| D-14 | A share starts with notes excluded. The user can include notes for that share after previewing the exact composed payload; the choice does not persist to the next share. |
| D-15 | Possible-duplicate warnings use the approved proximity rule. Name equality without proximity is searchable context, not an interruption. |

## Offline behavior

Local viewing, filtering, favorites, CRUD, attached photos, manual coordinates and widget snapshots work offline. Map tiles, provider search, reverse geocoding and ETA are best-effort services; downloaded/cached tiles are not a promised offline-map feature. Missing provider data must not block saving a valid coordinate.

Creating a share payload works offline. Delivery through another app and external navigation depend on that app's capabilities. Do not disable all sharing/directions merely because a network monitor says offline.

## Future placeholders

Android client, authentication, server API, remote media, account ownership, cloud sync, in-app backup/restore, collection collaboration, inbound map-link sharing, public/universal share links, bulk import/export, tag management, notifications and other widget families require new specifications. No Share Extension, disabled login/sync buttons, unused Supabase SDK, speculative API DTOs or persisted `pendingSync` state should be added to v1.

## Languages

Retain `ar`, `bn`, `de`, `en`, `es`, `fr`, `he`, `hi`, `id`, `it`, `ja`, `ko`, `nl`, `pt`, `ru`, `th`, `tr`, `uk`, `vi`, `zh-Hans`, plus a System language choice. Arabic/Hebrew require RTL verification. User-entered names/notes are never translated automatically.
