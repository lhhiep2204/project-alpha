# Map, search and adaptive location detail

## Two contexts, one reusable component family

| Contract | Collection Map | Global Map |
|---|---|---|
| Owner | A Home route/session | Map tab session |
| Saved-location scope | Fixed collectionID | All collections |
| Initial camera | Fit entire collection or focus tapped location | Restore camera; otherwise fit saved locations; otherwise safe fallback |
| Initial detail | Open only for location entry | None on fresh launch; selected record for widget intent |
| Saved search | Current scope collection | Entire library |
| Provider search | Apple Maps, biased by visible map region | Same |
| New-save default | Scope collection | Protected default collection |
| Change save destination | Permitted, never changes scope | Permitted, never filters map |
| Saved selection after save | Select only if in scope | Select committed location |
| Tab bar | Hidden on this pushed destination | Normal tab navigation |
| Back | Pop to Collection Detail | No artificial back-to-Home action |

Home's Find Saved Places action selects the existing Global Map search with a visible `All Saved Places` scope. It does not create another search implementation or a fourth tab, and closing it leaves Home's path/filter intact.

Reuse `MapCanvas`, detail content, editor, provider adapters and domain operations. Keep separate `MapSession` values for scope, selection, camera, search query and presentation. Do not use a global `selectedCollection` to represent both scope and destination.

Conceptual state:

```text
MapScope = allCollections | collection(UUID)
MapSelection = none | savedLocation(UUID) | candidate(PlaceCandidate)
CameraIntent = restore(CameraState) | fitScope | focus(Coordinate) | followUser
MapSession = scope + selection + cameraState + currentIntentGeneration
LocationDraft.destinationCollectionID = independent form value
```

## Camera rules

| Situation | Behavior |
|---|---|
| Show All with 2+ locations | Fit a bounding map rect to every location, padding for safe area, controls and visible detail/panel |
| Show All with 1 location | Center it at a useful neighbourhood scale, not a zero-size rect |
| Empty scope | Restore valid session camera; otherwise show broad fallback region and Add Place prompt |
| Tap saved location/search result | Focus the selected coordinate and show detail without changing saved scope |
| User pans/zooms | Respect the camera; no auto-refit from unrelated record/favorite updates |
| Tap Fit All | Explicitly refit scope and clear transient candidate; clear detail/selection |
| Close detail/delete selection | Retain camera and saved scope; clear selection |
| Return from editor | Do not reset camera unless a newly saved in-scope selection needs focus |
| Widget intent | Focus selected saved location in Global Map after its view is ready |

Include points around the antimeridian correctly; avoid a naive min/max longitude span that zooms out across the world. Clamp usable zoom for coincident points. A fit includes all scoped records, not just the viewport or currently filtered list.

Fallback order is retained camera, saved-scope fit, usable last position when already authorized, then a neutral broad region. Do not infer a location from IP or require permission just to open a map. Camera is UI state, not a persisted business entity. [Apple MapCameraPosition](https://developer.apple.com/documentation/mapkit/mapcameraposition)

## Saved pins and overlapping places

Use saved-record UUIDs for annotation identity. Global Map can have independent records for the same Apple place in several collections. Preserve those records; overlapping annotations must provide a disambiguation affordance listing collection name, icon and count, plus creation date when identical names still collide. VoiceOver exposes the same context. Group coincident saved pins for display or use a native selection list, but do not deduplicate database records across collections. Selecting an item opens the correct UUID's notes/photos/favorite state.

Use accessible Buttons or native selection for annotations, not gesture-only tappable images. Expose the selected state and collection name to VoiceOver. Unselected Apple POIs remain provider content; selecting one resolves a candidate.

For a POI selection, resolve the actual selected MapFeature/MapItem through the current SDK API. Do not search its name and blindly use the first result within a 500-metre radius; this can attach another business's identity. Carry primary and alternate Place IDs from authoritative map items. A manual coordinate reverse-geocode may supply address text but must not infer business identity.

## Search lifecycle

Saved results update from current committed data, scoped as shown above. Match custom name, provider/manual name, address, notes and provider category with locale-aware case/diacritic-insensitive user search. Rank exact display/provider/manual-name matches first, then name prefixes, then other field matches; within a tier use `updatedAt` descending, localized display title and UUID. Show collection context in global results. This is distinct from the conservative duplicate-name normalization in document 04.

Provider suggestions debounce by 300 ms as an initial tuning value. Every query/resolution has a generation/session ID and a cancellable task. Cancellation must terminate continuations exactly once and cancel SDK requests when possible. Empty query cancels pending work and clears results. A late result for an older query/region/locale must never replace current results.

Provider search is biased to the visible region captured when its request starts. Panning does not silently issue another provider search or change saved scope. When the visible region changes materially, offer `Search This Area`; activating it creates a new generation for the same query and current region.

Each active search UI owns a provider-search session, including editor subflows. Do not share one mutable MKLocalSearchCompleter continuation globally. Saved filtering and provider loading/errors are independent. Cached saved results must be invalidated by the library revision.

A suggestion can contain display text without a coordinate. It cannot be saved as `(0,0)`. Only resolved candidates or explicit manual coordinates enter the editor's savable state. Provider resolution failure keeps the result UI open with retry; it must not silently dismiss.

## Detail layout

On iPhone/compact width use a native bottom sheet with:

- **Peek:** name, short address, Close and primary Save/Open in Maps action.
- **Medium:** core metadata, favorite/edit/share actions and optional ETA.
- **Large:** notes, photos, coordinates and related locations, with scrolling.

Use content-aware sizing for Peek; at accessibility text sizes default to Medium/Large instead of clipping. Enable background-map interaction through Medium, disable it at Large. Dismissing a read-only sheet clears map selection. A candidate need not occupy an empty sheet before selection.

On a wide iPad use an adjacent trailing inspector/panel sharing the same content and state. Keep enough visible map area; adapt by actual window width, not device model. Resizing must not trigger duplicate presentations. Keep the map focus clear of the panel. SwiftUI provides inspector adaptation and sheet background interaction controls. [Apple inspector guidance](https://developer.apple.com/videos/play/wwdc2023/10161/), [presentationBackgroundInteraction](https://developer.apple.com/documentation/swiftui/view/presentationbackgroundinteraction(_:))

Within detail, distinguish saved and unsaved candidates. A resolved candidate shows its destination and the explicit primary action `Save to {collection}`; `Add Details` edits optional custom name, notes and photos on the same stable draft. An unresolved suggestion has no enabled Save. An existing scoped match offers Open Saved Place instead. A successful out-of-scope save switches the candidate presentation to a committed receipt naming the destination with Open Saved Place; it does not add an out-of-scope annotation or show Save again for that completed operation. Deletion is in an overflow/context action with confirmation. Keep the information surface readable with standard backgrounds. Liquid Glass belongs primarily to navigation and controls; do not apply it to every photo/list/card or stack glass layers. [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials)

Show at most five related places. Use the scope rules in document 02, ordered by geodesic distance, then `updatedAt` descending and UUID. Related-place selection changes selection without changing scope.

## Position, distance and directions

Request When In Use authorization at the first user action that needs device position. A CoreLocation adapter exposes plain permission states and an asynchronous position sequence/result to Domain. Stop unneeded updates when the screen/action no longer needs them; no background or Always authorization is needed.

Handle reduced accuracy, denied/restricted access, stale/no position and cancellation. Show position age/accuracy when it affects usefulness; do not present an old fix as live. For the first ETA in a map session, automatic mode uses walking at straight-line distance ≤1 km and driving otherwise. Display that mode next to the result and let the user select Walking or Driving for the active map session; the choice is not a hidden global preference. Offer route failure/unavailable state; never fabricate an ETA from straight-line distance. Label straight-line distance separately from route distance.

Key route requests by origin, destination coordinate or saved-record identity, mode and generation. Cancel/reject old requests on any key change, including manual pins without Place IDs. A nullable provider Place ID alone is not a sufficient change key. Changing distance units reformats the same metric value; it does not require a new directions request.

Directions handoff opens a destination even without ProjectAlpha location permission. The external app handles its own origin, permissions and offline support. Do not implement in-app turn-by-turn navigation in this scope.

## Loading and performance

Keep saved content visible during provider failures. Use cancellable asynchronous thumbnails and MapSnapshotter work with bounded caches. Avoid re-geocoding every record on each screen appearance. Optional address enrichment fills only missing values, checks current revisions and never prevents local rendering/saving.

Initial performance test dataset: 100 collections and 5,000 saved locations. This is a verification workload, not a product cap. Fetch efficient projection/count data, debounce invalidation, avoid one query per row, and profile map annotation behavior. If clustering or viewport loading is introduced for scale, Fit All still uses the complete logical scope and no location becomes inaccessible.
