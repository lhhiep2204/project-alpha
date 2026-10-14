# Screens and journeys

Authority: [product decisions](01-product-and-decisions.md). Technical routing is specified in [document 05](05-navigation-and-deep-links.md).

## Screen inventory

| ID | Screen | Entry and exit | Required content/actions |
|---|---|---|---|
| S-01 | Home | Home tab root | Collections with a fixed folder symbol and count, search by collection name, create and non-default edit/delete, Find Saved Places entry |
| S-02 | Collection Detail | Push from Home; Back to Home | Collection name as immediate navigation title, location list, local search, favorites filter, add, Show All on Map, location actions |
| S-03 | Collection Map | Push from S-02; Back to S-02 | Scope title, scoped saved pins, search, save, current position, fit all, detail |
| S-04 | Global Map | Map tab root | Full-bleed map with no navigation title and normal tab/sidebar chrome; native user-location indicator, upper-trailing current-position button and floating basic-information card for a successful fix or selected Apple Maps result. The approved search increment adds a trailing navigation-bar Search button and Apple Maps-only search. Full P-06 adds saved pins/search, save, fit all and richer detail. |
| S-05 | Location Detail | View Details from a map card, or selection on either map in full P-06 | This increment: read-only sheet with all available candidate/position information. Full P-06: name, address, coordinate, collection for saved items, notes/photos, bounded related locations and approved save/share/directions actions. |
| S-06 | Place Search | From either map or new-location editor | Saved results in applicable scope; separate Apple Maps results; loading/error/empty states |
| S-07 | Collection Editor | Create/edit sheet or editor subflow | Name; Save/Cancel |
| S-08 | Location Editor | Add details/edit sheet | Destination collection, place/coordinate source, optional custom name/notes/photos; Save/Cancel |
| S-09 | Collection Picker | Inside Location Editor | All collection names, selected destination, create collection inline |
| S-10 | Photo Viewer | From editor/detail | Full-size local image, paging, zoom, Close; no implicit photo edits |
| S-11 | Settings | Settings tab root | Language, app appearance (System/Light/Dark), map style, units, local-storage limitation, feedback, privacy link, app version |

## Adaptive presentation contract

The screen inventory defines destinations and capabilities, not fixed device layouts. Home, Map and Settings remain the three top-level destinations. Let the system present those destinations as a tab bar or sidebar according to available space. Compact layouts use a stack; when the hierarchy benefits and space permits, iPad and the open iPhone Duo use native split/adjacent presentation so a list or map and its selection can remain visible together. A wide canvas must not merely stretch phone-width cards, and a narrow or resized window must not lose an action.

Choose presentation from available space, size classes and scene geometry. Do not detect a device model, interface idiom or orientation, read `UIScreen.main`, or encode fixed screen-width breakpoints. Prefer `NavigationStack`, `NavigationSplitView`, `TabView`, lists, forms, inspectors, sheets, popovers, menus, alerts and system bars so iPadOS/iOS can adapt keyboard, pointer, focus, overflow, safe-area and iPhone Duo behavior. Minimize blocking modal chains on iPad; use a column, inspector or popover when it preserves context and suits the hierarchy.

Every transition between compact, split, floating, tiled, outer-display, inner-display, side-by-side, Picture-in-Picture-constrained and partially folded sizes preserves the same route, selected record, map scope/camera/search, form draft and staged media. It may move or collapse a presentation, but must not duplicate a presentation owner, reset user work or hide functionality. Foreground controls honor safe areas, asymmetric margins and SDK-exposed reserved regions; full-bleed backgrounds may extend underneath them.

All actions remain discoverable and operable with touch, keyboard, trackpad/pointer, Voice Control and Switch Control. Use standard focus, hover, context-menu and command behavior where available. Custom controls have a target of at least 44 by 44 points and expose labels, values, state and order to assistive technologies. Every layout supports Dynamic Type without clipping, RTL without semantic reversal, VoiceOver, Voice Control, Switch Control, Reduce Motion and Reduce Transparency.

## J-01 — Launch and library bootstrap

1. Load versioned local storage, preferences and scene restoration state.
2. Ensure exactly one default collection in the same serialized store used by CRUD.
3. Present Home on fresh launch, with the default collection and a count of zero. Do not present a zero-collection empty view after successful bootstrap; an empty search result remains possible when the query matches no collection.
4. Existing installations restore valid navigation state; an incoming valid deep link takes precedence over restoration.
5. Storage failure shows a recovery screen with Retry. Never quietly replace persistent data with an empty in-memory store.
6. Do not request location, camera or photo-library permission just to view Home.

## J-02 — Manage collections

Home uses a native List with search, swipe actions and a context menu. Its search field filters collection names only. A separate, clearly labeled Find Saved Places action opens Global Map search with an `All Saved Places` scope; returning preserves Home's path and collection filter. Default collection appears first; remaining collections sort by `createdAt` descending, UUID ascending as a stable tie-breaker. Counts come from committed data, not view callbacks.

Every collection row uses the same folder symbol. The protected default collection never shows or announces its creation date or time. When non-default collections share the same name, count and creation date, each affected non-default Home row visibly includes its localized creation time. VoiceOver announces that time alongside the row's other identifying details.

Create/edit for non-default collections uses a name-only draft. There is no icon picker or cover-photo control; every collection displays the fixed folder symbol without an icon/cover field in collection data. Name is trimmed, required and at most 30 grapheme clusters. Duplicate collection names are allowed; their IDs remain distinct. Pickers and overlapping-pin choices disambiguate identical names with location count and creation date/time when needed; VoiceOver receives the same context. The app may warn that a name already exists but never silently renames a collection. The default collection has no edit or delete affordance and cannot be renamed, deleted, demoted or duplicated. Its English title is “My Places”; its displayed title follows the app language currently selected.

Delete a non-default collection requires a confirmation naming the collection and the current number of locations that will be deleted. Commit parent and children together; clean their media after commit. A failed delete retains the data and displays a retryable error without removing its row. After a successful commit, visibly animate that row out and close the list gap using native list motion; honor Reduce Motion without delaying interaction. A successful delete also invalidates affected selections, paths, counts, search results and widget snapshots.

An inline-created collection is saved immediately as its own operation and selected in the parent Location Editor. Cancelling that location draft does not delete the new collection.

## J-03 — Open a collection and its map

Tapping a collection opens its location list with the collection name in the navigation title on the first displayed frame. The tapped row's name can provide an immediate scene-local hint while the latest record loads; the route remains ID-based and the title updates if that record has since been renamed. A stale or deleted ID follows the missing-entity contract rather than showing the hint as authoritative content.

Collection Detail lists locations newest-created first with UUID tie-breaker. Show custom name when nonempty, otherwise the provider/manual name. Include address and favorite state. Support local search and favorites-only filtering; preserve these while pushing/popping its map or switching tabs. Leaving the collection for Home resets the local filters.

Tapping a row pushes Collection Map with a focus intent for that location. All saved locations from the collection remain in map scope even if the list was filtered. The selected location gets its detail presentation immediately.

Show All on Map pushes the same map with a fit-all intent and no selected location. Label it `Show All {count} on Map` so a filtered list does not imply that only visible rows are included. It always includes the entire collection, not just filtered rows. Keep the action available for an empty collection as `Show All 0 on Map`: open an empty map with an Add Place prompt. Repeated taps must not push duplicate map screens.

## J-04 — Search and add a place

**Approved Apple Maps-only Global Map increment (2026-10-09; detail endpoint refined 2026-10-11):** The trailing navigation-bar Search button opens a search screen. Keyword edits wait for 1 second without another edit before starting provider search; show results with place name and address/location text. Selecting a result resolves it, then closes Search, focuses Global Map at its coordinate and displays an icon-only unsaved candidate marker with a floating basic-information card. A failed resolution leaves Search open for retry. The card can open a read-only detail sheet in this increment; editor/save flow and saved-place results follow later. The full journey below remains required for P-06.

**Approved selection scale (2026-10-13; ambiguity refined 2026-10-14):** A new resolved search selection focuses at the shared scale for its reliably known geographic kind: a point-like place such as a building or market appears closer than a city, which appears closer than a larger region. It does so even after an earlier manual zoom. If the kind is unavailable or ambiguous, keep the current useful zoom while centering; use a near default when that zoom is too far out, including an approximately 8° view. A result whose name matches both structured city and region metadata uses the region scale only when a valid country/region code corroborates that region; without that code it remains unknown. Subsequent user pan/zoom is respected. The same rule applies to saved-place focus, Collection Map and widget focus when those later flows are implemented; Show All/Fit All retains its complete-scope fit.

**Keyboard refinement (2026-10-10):** Search keeps its title and app Close action visible when the query field is focused. Do not show an external X or native search Cancel. Enter dismisses only the keyboard, preserving the query and results. While Search remains open, only the clear X inside the query field explicitly clears it; ordinary editing remains available. Closing Search uses its existing presentation owner.

**Dismissal lifecycle refinement (2026-10-10):** App Close, system dismissal and successful selection discard the search presentation, model and provider session, clear all query/results/errors/resolution state and cancel pending work. Reopening Search starts empty with a fresh session. A successfully resolved candidate is transferred to the existing map first, so its focused marker and card remain under the 2026-10-11 refinement. Enter and a scene/tab pause while the presentation is still owned retain the open search; resize/display/pose changes do not discard it.

**Appearance refinement (2026-10-10):** The query field uses a Liquid Glass capsule with fully rounded ends. Remove any custom or fixed shared top background behind the title, Close action and query field; retain default system navigation-bar/scroll-edge blur like Home when results scroll underneath; retain the field’s own capsule surface and safe-area layout. Keep the same title/Close visibility and keyboard behavior. Reduce Transparency uses a readable opaque capsule, with Dynamic Type, RTL and labeled input actions preserved.

**Floating-card refinement (2026-10-11; clearance and progressive content approved 2026-10-12):** Search selection has one icon-only marker, with name/address/basic actions on a floating card. Its X returns to the latest valid current-position card and recenters the map; if no position exists, the card disappears and the camera stays. Persistent position detail appears immediately for a successful automatic first fix or explicit recenter as a card without X. Both card types offer Open in Apple Maps and View Details; the latter is an explicitly opened read-only sheet with all data available for that selection. Neither surface offers Save/Add Details in this increment. For the same available map geometry, card height is fixed independently of Dynamic Type, selected place, card type and missing facts. Recompute a smaller shared height from a full template at the default iOS text size: two-line title, two-line address, three single-line metadata rows (coordinate, horizontal accuracy and position time, each with its label and value inline) and one horizontal action row. Reserve 12-point card content padding and the required metadata/action spacing; remove vertical space previously needed for separate label/value lines without reducing these content reservations. Recalculate height when the available map geometry changes. At default text size, fit all applicable basic information within those line limits in portrait and landscape, except that Open in Apple Maps is hidden when both actions cannot fit horizontally. Use one inline label/value row for each available coordinate, horizontal accuracy and position time in every map-card geometry, not only when height is constrained. At default text size, these three metadata rows fit alongside the reserved two-line title and two-line address. Keep a minimum 16-point metadata-to-action gap. Reduce the visible action-control size only if needed for fit, preserving at least 44-by-44-point hit targets, readable labels and the existing horizontal action-fit rule. Keep the inline arrangement across available geometries; choose any further fit adjustment from available geometry, not orientation or device identity, and format values for the selected locale. Never stack the actions. Anchor the card at the bottom, with approximately 8 points from its bottom edge to the top edge of the actual MapKit Maps/legal-attribution row. Calibrate the clearance by measuring the actual simulator UI; Apple layout changes can vary the gap, and no public legal-frame API availability is asserted. Anchor the visible action row 12 points above the card bottom, avoiding excessive blank padding beneath it. At larger text sizes, change only the content shown inside the fixed-height card, without internal scrolling. Retain View Details, then title, available address, coordinate, horizontal accuracy/position time, then Open in Apple Maps as space permits. Search-card X always remains visible and operable, including maximum Dynamic Type. Hide Open in Apple Maps whenever the two actions cannot fit side by side, including at default text size; the full-information sheet retains that action. Overlay a visually smaller search-card X with reserved title/address space and at least a 44-by-44-point hit target. Retain approximately 16 points between visible accuracy/position-time information and the action row. The earlier automatic View Details and hidden-card fallback is superseded; View Details remains available by button with complete information and Open in Apple Maps. Card placement and adaptive continuity follow document 06; a multi-card carousel is future design capacity, not part of this increment.

**Liquid Glass clarification (2026-10-11):** The approved card refinement specified placement and actions but omitted explicit Liquid Glass styling for the card itself. Apply native SwiftUI Liquid Glass to the full card surface and its in-card action controls. Keep actions compact and intrinsically sized with hit targets of at least 44 by 44 points; group glass controls in `GlassEffectContainer` when suitable. Under Reduce Transparency, provide a readable opaque fallback. Preserve Dynamic Type and RTL. These are ProjectAlpha requirements; Apple does not prescribe this card's dimensions.

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

The Global Map's first actual activation checks authorization and requests When In Use if undetermined. After authorization succeeds, obtain one position and center the camera as soon as the first geographically and metadata-valid fix arrives with a finite, nonfuture timestamp, regardless of past age. Show persistent current-position detail immediately as an adaptive card that retains View Details at every text size, with “My Location”, exact coordinate, horizontal accuracy and timestamp when space permits on the card; show a reverse-geocoded address only when available. Previously denied access, including denial in this initial prompt, produces no denial alert. Subsequent tab returns preserve the camera and card. Get Current Location sits in the trailing navigation toolbar alongside Search; on iPad both buttons stay directly visible at every supported window width and do not collapse into the system ellipsis overflow menu. The current-position button uses native Liquid Glass, keeps the same visible size while loading, and shows a black icon in Light appearance or a white icon in Dark appearance; activating it follows the immediate-response refinement below. When authorization is denied, that explicit action immediately shows Settings and Cancel without another system permission prompt. Other position actions continue to request permission on demand. Services return typed errors and never present alerts or open Settings.

Restricted access, disabled/unavailable location services, or failure to obtain a usable fix before the 10-second acquisition deadline use a localized, nonblocking in-map toast shared through the common Presentation design system. Invalid/future samples do not complete the request; acquisition continues waiting for a valid fix within that same 10-second deadline. The deadline starts after authorization; permission-prompt wait is excluded. A timed-out provider request returns its timeout error without converting an old fix into success; the map retains any usable previously displayed camera/card. The toast uses a Liquid Glass capsule with fully rounded ends and text centered horizontally and vertically, including wrapped messages. Swipe up dismisses it; there is no visible close button. Keep the existing automatic-dismissal timing and provide assistive-technology and keyboard dismissal alternatives. Honor Reduce Transparency with a readable opaque capsule and Reduce Motion with appropriate motion reduction. The toast must remain readable inside safe areas, accommodate Dynamic Type/RTL, expose its message to assistive technology and leave map controls usable; cancellation does not produce an error message. Saved pins and manual search remain usable through position failures when delivered in full P-06. Save Current Position creates a coordinate candidate, not a magic persistent Location ID.

**Approved explicit current-position response (2026-10-13):** After checking current authorization, an explicit Get Current Location action immediately focuses and shows a valid position already held by that map session when its finite nonfuture timestamp is at most 30 seconds old, including exactly 30 seconds. This immediate response does not wait for acquisition or reverse geocoding and does not show an acquisition spinner while the usable card is displayed. Always start an asynchronous one-shot update; without a usable session position, retain the existing loading/error behavior. A new accepted fix updates the position card, but focuses the camera only if the user has not panned or zoomed since the action. Preserve current request/candidate generations so late completions cannot replace a newer selection, and cancel pending work when the map becomes inactive. A denied or restricted permission state cannot reuse the session fix. The 30-second limit applies only to immediate session reuse: the provider still accepts the first otherwise-valid past fix regardless of age, honors Reduced Accuracy and the 10-second post-authorization deadline, and does not return an old fix as a successful timeout result. Failure/timeout feedback preserves any usable prior camera/card. Add no persistent cache, continuous/background tracking or accuracy downgrade.

The first accepted position and each explicit Get Current Location selection use the shared near current-position scale, regardless of the prior manual zoom. Search-card X's return to an available current position uses that scale too. The later one-shot update may refocus only under the existing no-intervening-pan/zoom and current-generation guards; merely updating the card or address does not reset the camera.

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

## J-08 — Settings, language and appearance

Settings provides System/supported language selection, System/Light/Dark app appearance, Standard/Satellite/Hybrid map style, kilometres/miles, feedback, privacy information and app version/build. The selected appearance applies throughout ProjectAlpha and persists across launches. System follows the platform appearance; Light and Dark select their corresponding app appearance. Language and appearance changes take effect across the app without resetting navigation or discarding drafts. Appearance does not change a map's selected map style.

Settings states that records are stored on this device and v1 has no in-app synchronization or backup/restore. This copy must not claim whether an OS/device backup includes the app until that behavior is separately verified.

Use ProjectAlpha-specific support email and privacy URL when configured. During development, keep unresolved values explicit and block release until valid endpoints are supplied. A failed external open shows a useful fallback; do not claim feedback was sent merely because an email composer opened.

## Common state contract

| State | Required presentation |
|---|---|
| Loading | Progress with navigation still understandable; no false empty list |
| Collection with zero locations | In Collection Detail, show the empty location state; Add Place and Show All on Map remain available |
| Empty search | No matching saved/provider results, with query retained |
| Provider unavailable | Saved content remains usable; retry provider search |
| Permission denied | Initial/passive Global Map activation is silent; explicit position action explains denial with Settings and Cancel. Do not block library. Other position failures use the common nonblocking toast. |
| Save failure | Keep draft, show actionable error, allow retry |
| Edit conflict | Keep the local draft, show latest committed data, and offer explicit Reload or Reapply; confirm before discarding the draft and revalidate any reapplication |
| Missing selected entity | Close stale detail, refresh content, show unavailable message |
| Storage unavailable | Recovery screen; never present success or an empty replacement library |
| Unsaved draft interrupted | Keep Editing or Discard; queued external navigation waits |
| Window size or device pose changes | Reflow the same destination and presentation state; preserve route, selection, map state, search, draft fields and staged media |

All visible strings, pluralized counts, accessibility labels and share labels are localized. Read-only detail is dismissible. Dirty editors protect against accidental dismissal; clean editors dismiss normally.
