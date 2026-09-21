# Screens and journeys

Authority: [product decisions](01-product-and-decisions.md). Technical routing is specified in [document 05](05-navigation-and-deep-links.md).

## Screen inventory

| ID | Screen | Entry and exit | Required content/actions |
|---|---|---|---|
| S-01 | Home | Home tab root | Collections, icon, count, search by collection name, create/edit/delete, Find Saved Places entry |
| S-02 | Collection Detail | Push from Home; Back to Home | Name, location list, local search, favorites filter, add, Show All on Map, location actions |
| S-03 | Collection Map | Push from S-02; Back to S-02 | Scope title, scoped saved pins, search, save, current position, fit all, detail |
| S-04 | Global Map | Map tab root | All saved pins, search, save, current position, fit all, detail |
| S-05 | Location Detail | Selection on either map | Name, address, coordinate, collection for saved items, notes/photos, bounded related locations, quick save/share/directions actions |
| S-06 | Place Search | From either map or new-location editor | Saved results in applicable scope; separate Apple Maps results; loading/error/empty states |
| S-07 | Collection Editor | Create/edit sheet or editor subflow | Name and icon/photo; Save/Cancel |
| S-08 | Location Editor | Add details/edit sheet | Destination collection, place/coordinate source, optional custom name/notes/photos; Save/Cancel |
| S-09 | Collection Picker | Inside Location Editor | All collection names, selected destination, create collection inline |
| S-10 | Photo Viewer | From editor/detail | Full-size local image, paging, zoom, Close; no implicit photo edits |
| S-11 | Settings | Settings tab root | Language, map style, units, local-storage limitation, feedback, privacy link, app version |

## J-01 — Launch and library bootstrap

1. Load versioned local storage, preferences and scene restoration state.
2. Ensure exactly one default collection in the same serialized store used by CRUD.
3. Present Home on fresh launch, with the default collection and a count of zero. Do not display an impossible "no collections" state after successful bootstrap.
4. Existing installations restore valid navigation state; an incoming valid deep link takes precedence over restoration.
5. Storage failure shows a recovery screen with Retry. Never quietly replace persistent data with an empty in-memory store.
6. Do not request location, camera or photo-library permission just to view Home.

## J-02 — Manage collections

Home uses a native List with search, swipe actions and a context menu. Its search field filters collection names only. A separate, clearly labeled Find Saved Places action opens Global Map search with an `All Saved Places` scope; returning preserves Home's path and collection filter. Default collection appears first; remaining collections sort by `createdAt` descending, UUID ascending as a stable tie-breaker. Counts come from committed data, not view callbacks.

Create/edit uses a draft with name and either a built-in SF Symbol icon or one local cover image. A generic folder is the fallback. Name is trimmed, required and at most 30 grapheme clusters. Duplicate collection names are allowed; their IDs remain distinct. Pickers and overlapping-pin choices disambiguate identical names with the collection icon and count, plus creation date when those still collide; VoiceOver receives the same context. The app may warn that a name already exists but never silently renames a collection. A default collection may be renamed/redecorated but not deleted, demoted or duplicated. Its initial title is localized at creation and persisted as a normal name; later language changes do not rewrite it. A user rename is literal user content.

Delete a non-default collection requires a confirmation naming the collection and the current number of locations that will be deleted. Commit parent and children together; clean their media after commit. A failed delete retains the data and displays a retryable error. A successful delete invalidates affected selections, paths, counts, search results and widget snapshots.

An inline-created collection is saved immediately as its own operation and selected in the parent Location Editor. Cancelling that location draft does not delete the new collection.

## J-03 — Open a collection and its map

Collection Detail lists locations newest-created first with UUID tie-breaker. Show custom name when nonempty, otherwise the provider/manual name. Include address and favorite state. Support local search and favorites-only filtering; preserve these while pushing/popping its map or switching tabs. Leaving the collection for Home resets the local filters.

Tapping a row pushes Collection Map with a focus intent for that location. All saved locations from the collection remain in map scope even if the list was filtered. The selected location gets its detail presentation immediately.

Show All on Map pushes the same map with a fit-all intent and no selected location. Label it `Show All {count} on Map` so a filtered list does not imply that only visible rows are included. It always includes the entire collection, not just filtered rows. Keep the action available for an empty collection as `Show All 0 on Map`: open an empty map with an Add Place prompt. Repeated taps must not push duplicate map screens.

## J-04 — Search and add a place

1. Open Search from a map, Find Saved Places from Home, or Add Location from a list/editor.
2. Show saved results in the calling scope and Apple Maps results as separate sections. Home's entry uses the global saved scope. Offline, saved search still works and provider failure is shown only in its section.
3. A saved result opens that exact record without creating another record. Show its collection context. A provider suggestion must be resolved before it becomes a savable candidate.
4. A resolved candidate opens detail with its place/address or coordinate and the visible destination from D-07. The primary action is `Save to {collection}`. `Add Details` opens optional custom name, notes and photos using the same stable draft; quick capture never bypasses validation.
5. The user can change destination or create a collection inline before committing. This does not alter the calling map's scope or its saved-search scope.
6. Validate coordinates, bounded draft values, destination existence and duplicates. On a blocking duplicate, offer Open Saved Place, Choose Another Collection or return to editing; never silently overwrite notes/photos.
7. Commit once; disable every repeated Save entry while the operation is pending. Failed validation or persistence keeps the destination, candidate, optional fields and staged images intact. An unresolved suggestion never enables Save.
8. Global Map selects the committed record. Collection Map selects it only if it belongs to that map's scope. For an out-of-scope save, retain the current camera/scope and show a committed `Saved to {collection}` receipt with `Open Saved Place`; never leave the primary action implying that the same save is still pending. Re-resolve that receipt if the record changes, moves or disappears.

Opening an out-of-scope duplicate from a Collection Map explicitly routes to Global Map. It does not mutate Collection Map's scope. Protect dirty drafts using the policy in document 05.

### Add-place entry and return contract

| Entry | Search selection | Save result | Cancel / Back |
|---|---|---|---|
| Collection Detail → Add | A resolved result fills the one active draft and defaults to that collection. | Return to the list, retain query/scroll, update count and show the destination. If filters hide the record, offer View without clearing filters. | Return to the same list; protect dirty edits. |
| Collection Map → Search | Resolve and show candidate detail in the same map session. | Apply the in-scope/out-of-scope contract above. | Restore the previous selection/detail when search is cancelled. |
| Global Map → Search | Resolve and show candidate detail; default to the protected collection. | Select the committed record globally. | Restore the previous global selection/detail. |
| Existing new-location editor → Choose Place | Fill the existing draft; never stack a second editor. Confirm before replacing a candidate when user-entered fields would be discarded. | Commit once from the existing draft. | Return to the editor with its previous candidate and fields. |

## J-05 — Manual pin and current position

Both maps support dropping a pin with a long press and an accessible Add at Map Center action. A manual coordinate option is available in the new-location editor. Latitude and longitude must parse as finite values in valid ranges; `(0, 0)` is valid and must not be a missing-value sentinel.

A selected point produces a candidate immediately. Optional reverse geocoding may fill an empty address; lack of a network/address is not an error for local saving. Do not assign the Place ID of a nearby business to a manually selected point merely because it is close.

The current-position action requests When In Use permission on demand. Denied/restricted/unavailable location leaves saved pins and manual search usable. Offer system Settings when appropriate. Save Current Position creates a coordinate candidate, not a magic persistent Location ID.

## J-06 — Edit, move, favorite and delete a location

The editor allows changing the custom name (up to 50 grapheme clusters), notes (up to 10,000 grapheme clusters), up to five photos and the owning collection. A manual identity name is trimmed, required and at most 80 grapheme clusters. Provider name, provider coordinate and category are read-only for a provider-backed place. Manual name/coordinate entry is available only when creating a new manual place. A saved location's underlying coordinate is fixed; replacing a saved location's underlying place is outside v1, so add a new place and delete the old record instead.

Moving preserves the record ID, photos and favorite state. Recheck duplicates in the destination collection while excluding the current record ID. A failed move leaves its original owner unchanged. A location moved out of Collection Map disappears from that map and closes its detail; Global Map keeps it selected with its updated collection label.

Favorite changes affect only that saved record. Saving the same real-world place to another collection does not share notes, images or favorite state between the records. New records start not-favorited; favorite can be toggled in detail/list after save.

Photo controls show remaining capacity before selection. At five photos, disable another selection and explain the limit. A failed import identifies the affected asset, retains successful/staged assets and offers retry or removal; cancellation never silently drops the rest of the draft.

Delete requires confirmation. On success clear that selection and detail, retain camera position and remain in the map/list. Do not unexpectedly request GPS or select an unrelated location. On failure show the error and preserve the record.

## J-07 — Read detail, share and get directions

Detail shows custom/provider names, address if available, coordinates, owning collection, notes and local photos. Saved items offer Favorite, Edit, Share, Open in Maps and Delete. Candidates offer Save, Share and Open in Maps. Copy actions cover address, coordinates, notes and place information.

Related places in Collection Map are other locations in its scope. In Global Map, related places are other locations in the selected saved record's owning collection. Candidate detail has no fabricated ownership; it may show the calling collection's saved places as contextual related results. Show at most five, ordered by geodesic distance, then `updatedAt` descending and UUID. Selecting a related place changes selection, not the map scope.

The default share payload contains display/provider name, address when available, coordinates and an Apple Maps URL. It excludes notes and photos. When notes exist, offer `Include Notes`, off for every new share. Show the complete composed payload inside ProjectAlpha before opening the system sheet and ensure the final payload matches it. Dismissing a composer or share sheet is not proof of delivery. Never share an app-local UUID link as if it will open another user's local database.

Directions hand off to Apple Maps by default, with Google Maps as an external option. In-app distance/ETA is supplementary, not turn-by-turn navigation. Display the current supported mode beside ETA and let the user select Walking or Driving for the active map session. Changing mode cancels/replaces the route estimate but does not change a global hidden preference. Label straight-line distance separately from route distance. No current position means no origin-based ETA, but opening the destination in an external maps app remains available.

## J-08 — Settings and language

Settings provides System/supported language selection, Standard/Satellite/Hybrid map style, kilometres/miles, feedback, privacy information and app version/build. Changes apply across both maps and widgets without resetting navigation or discarding drafts.

Settings states that records are stored on this device and v1 has no in-app synchronization or backup/restore. This copy must not claim whether an OS/device backup includes the app until that behavior is separately verified.

Use ProjectAlpha-specific support email and privacy URL when configured. During development, keep unresolved values explicit and block release until valid endpoints are supplied. A failed external open shows a useful fallback; do not claim feedback was sent merely because an email composer opened.

## Common state contract

| State | Required presentation |
|---|---|
| Loading | Progress with navigation still understandable; no false empty list |
| Empty collection | Add Place and Show All on Map remain available |
| Empty search | No matching saved/provider results, with query retained |
| Provider unavailable | Saved content remains usable; retry provider search |
| Permission denied | Explain the affected action and Settings option; do not block library |
| Save failure | Keep draft, show actionable error, allow retry |
| Edit conflict | Keep the local draft, show latest committed data, and offer explicit Reload or Reapply; confirm before discarding the draft and revalidate any reapplication |
| Missing selected entity | Close stale detail, refresh content, show unavailable message |
| Storage unavailable | Recovery screen; never present success or an empty replacement library |
| Unsaved draft interrupted | Keep Editing or Discard; queued external navigation waits |

All visible strings, pluralized counts, accessibility labels and share labels are localized. Read-only detail is dismissible. Dirty editors protect against accidental dismissal; clean editors dismiss normally.
