# Map, search and adaptive location detail

## Two contexts, one reusable component family

| Contract | Collection Map | Global Map |
|---|---|---|
| Owner | A Home route/session | Map tab session |
| Saved-location scope | Fixed collectionID | All collections |
| Initial camera | Fit entire collection or focus tapped location | Retain valid camera; first ordinary activation acquires/focuses current position after authorization succeeds; otherwise saved-scope fit or safe fallback. Explicit widget focus retains its existing priority. |
| Initial detail | Open only for location entry | None on fresh launch; selected record for widget intent |
| Saved search | Current scope collection | Entire library |
| Provider search | Apple Maps, biased by visible map region | Same |
| New-save default | Scope collection | Protected default collection |
| Change save destination | Permitted, never changes scope | Permitted, never filters map |
| Saved selection after save | Select only if in scope | Select committed location |
| Top-level navigation | Hidden on this pushed destination | Normal tab/sidebar navigation |
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

Fallback order is retained camera, saved-scope fit, usable last position when already authorized, then a neutral broad region. Do not infer a location from IP or make permission a prerequisite for using the map. The approved first Global Map activation requests permission when undetermined; denial still leaves the map usable. Camera is UI state, not a persisted business entity. [Apple MapCameraPosition](https://developer.apple.com/documentation/mapkit/mapcameraposition)

## Saved pins and overlapping places

Use saved-record UUIDs for annotation identity. Global Map can have independent records for the same Apple place in several collections. Preserve those records; overlapping annotations must provide a disambiguation affordance listing collection name and location count, plus creation date/time when identical names still collide. Every collection uses the same folder symbol, so it is not distinguishing context. VoiceOver exposes the same identifying context. Group coincident saved pins for display or use a native selection list, but do not deduplicate database records across collections. Selecting an item opens the correct UUID's notes/photos/favorite state.

Use accessible Buttons or native selection for annotations, not gesture-only tappable images. Expose the selected state and collection name to VoiceOver. Unselected Apple POIs remain provider content; selecting one resolves a candidate.

For a POI selection, resolve the actual selected MapFeature/MapItem through the current SDK API. Do not search its name and blindly use the first result within a 500-metre radius; this can attach another business's identity. Carry primary and alternate Place IDs from authoritative map items. A manual coordinate reverse-geocode may supply address text but must not infer business identity.

## Search lifecycle

Saved results update from current committed data, scoped as shown above. Match custom name, provider/manual name, address, notes and provider category with locale-aware case/diacritic-insensitive user search. Rank exact display/provider/manual-name matches first, then name prefixes, then other field matches; within a tier use `updatedAt` descending, localized display title and UUID. Show collection context in global results. This is distinct from the conservative duplicate-name normalization in document 04.

Provider suggestions debounce by 300 ms as an initial tuning value. Every query/resolution has a generation/session ID and a cancellable task. Cancellation must terminate continuations exactly once and cancel SDK requests when possible. Empty query cancels pending work and clears results. A late result for an older query/region/locale must never replace current results.

Provider search is biased to the visible region captured when its request starts. Panning does not silently issue another provider search or change saved scope. When the visible region changes materially, offer `Search This Area`; activating it creates a new generation for the same query and current region.

Each active search UI owns a provider-search session, including editor subflows. Do not share one mutable MKLocalSearchCompleter continuation globally. Saved filtering and provider loading/errors are independent. Cached saved results must be invalidated by the library revision.

A suggestion can contain display text without a coordinate. It cannot be saved as `(0,0)`. Only resolved candidates or explicit manual coordinates enter the editor's savable state. Provider resolution failure keeps the result UI open with retry; it must not silently dismiss.

## Approved service foundation boundary

The 2026-10-06 approval delivers services and composition before full map UI. Domain owns Foundation-only values, typed results/errors and service ports; Data owns CoreLocation/MapKit adapters; App owns shared service lifetime and creates separate provider-search sessions. No screen, camera, dialog or Settings handoff is added by this foundation.

| Service operation | Required result / boundary |
|---|---|
| Reverse geocode coordinate | Return address metadata for the exact input point. Do not change its coordinate or assign a nearby business's Place ID; absent address/provider failure does not invalidate that coordinate. |
| Suggest and resolve | Suggestions belong to an independent search session, resolve to coordinate-bearing candidates and obey cancellation/generation rules above. |
| Resolve Place ID | Resolve an opaque Apple Place ID directly and retain authoritative primary and known alternate IDs; do not approximate by nearby name search. |
| Estimate route | Return route distance and duration for explicit Walking or Driving mode, with request identity and typed unavailable/failure outcomes. Do not substitute straight-line distance or fabricate duration. |

This table records approved ProjectAlpha behavior, not a declaration that SDK adoption has been verified. Adapter implementers must verify the selected API declarations/availability and compile focused uses under document 09 before adoption. Locify is a reference implementation, not the authority for ProjectAlpha behavior or identity rules.

## Approved incremental Global Map UI

The 2026-10-07 delivery follows the service foundation and precedes the remaining full P-06 UI. Render the map full bleed without a navigation title, retaining Home/Map/Settings through normal native tab/sidebar chrome. Keep the current-position button at the lower trailing edge inside applicable safe areas, above the tab bar where it is horizontal and clear of system chrome when it adapts. Its accessible target is at least 44 by 44 points. MapKit supplies the native blue user-location indicator while authorized and visible; its display updates are independent of the app-owned one-shot acquisition service.

| Trigger / authorization | Position and feedback |
|---|---|
| First actual Map activation, undetermined | Request When In Use once; after grant acquire the first otherwise-valid fix with a finite nonfuture timestamp, regardless of age, and center camera. Denial is silent. |
| First actual Map activation, authorized | Acquire the first otherwise-valid fix with a finite nonfuture timestamp, regardless of age, and center camera. |
| First actual Map activation, denied | Show the usable map without a denial alert or another prompt. |
| Subsequent tab return or resize | Preserve the camera; do not repeat first-entry acquisition. |
| Explicit current-position button, authorized | Obtain the first otherwise-valid fix with a finite nonfuture timestamp, regardless of age, and animate camera to it; respect Reduce Motion. |
| Explicit current-position button, denied | Immediately show native explanatory Settings/Cancel alert; do not repeat the permission prompt. |
| Restricted access, disabled/unavailable service, provider failure or no usable fix before timeout | Show a localized nonblocking in-map toast; preserve usable map/camera. |
| Cancelled request / inactive map | Stop pending acquisition and ignore stale completion; do not show cancellation as a failure. |

Use a reusable Presentation design-system toast with public SwiftUI Liquid Glass styling, a capsule shape with fully rounded ends, and message text always centered horizontally and vertically, including wrapped localized messages. Swipe up dismisses it instead of a visible close button. Apple’s Focus-mode system toast is the product owner’s visual/interaction reference; this does not require private system UI or exact reproduction of undocumented system behavior. Apple [alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [layout](https://developer.apple.com/design/human-interface-guidelines/layout) are platform references; the nonblocking toast/error policy is a ProjectAlpha choice. Locify remains a reference implementation. Apple’s [custom Liquid Glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) and [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility) are additional platform references. No public system-toast symbol or iPhone Duo support is asserted by this contract; the implementer must verify SDK declarations and focused compilation, and retain document 09's toolchain limitations. Keep toast feedback inside safe areas, accessible with Dynamic Type/RTL and assistive technologies, and avoid blocking map interaction. Keep existing automatic-dismissal timing. Provide assistive-technology and keyboard dismissal alternatives without a visible close button; honor Reduce Transparency with a readable opaque capsule and Reduce Motion with appropriate motion reduction. Bound message state and cancel obsolete dismissal work; do not create an app-global map/toast state owner.

Saved annotations, global search, save/manual capture and adaptive detail remain required by full P-06. Their absence in this incremental delivery does not satisfy those acceptance criteria or remove them from scope.

## Detail layout

At compact available width use a native bottom sheet with:

- **Peek:** name, short address, Close and primary Save/Open in Maps action.
- **Medium:** core metadata, favorite/edit/share actions and optional ETA.
- **Large:** notes, photos, coordinates and related locations, with scrolling.

Use content-aware sizing for Peek; at accessibility text sizes default to Medium/Large instead of clipping. Enable background-map interaction through Medium, disable it at Large. Dismissing a read-only sheet clears map selection. A candidate need not occupy an empty sheet before selection.

When available space supports it, including wide iPad windows and the open iPhone Duo, use an adjacent trailing inspector/panel sharing the same content and state. Keep enough visible map area; decide from size classes and local scene geometry, not device model, idiom, orientation, `UIScreen.main` or a fixed screen-width breakpoint. Resizing must not trigger duplicate presentations. Keep the map focus clear of the panel. SwiftUI provides inspector adaptation and sheet background interaction controls. [Apple inspector guidance](https://developer.apple.com/videos/play/wwdc2023/10161/), [presentationBackgroundInteraction](https://developer.apple.com/documentation/swiftui/view/presentationbackgroundinteraction(_:))

Within detail, distinguish saved and unsaved candidates. A resolved candidate shows its destination and the explicit primary action `Save to {collection}`; `Add Details` edits optional custom name, notes and photos on the same stable draft. An unresolved suggestion has no enabled Save. An existing scoped match offers Open Saved Place instead. A successful out-of-scope save switches the candidate presentation to a committed receipt naming the destination with Open Saved Place; it does not add an out-of-scope annotation or show Save again for that completed operation. Deletion is in an overflow/context action with confirmation. Keep the information surface readable with standard backgrounds. Liquid Glass belongs primarily to navigation and controls; do not apply it to every photo/list/card or stack glass layers. [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials)

Show at most five related places. Use the scope rules in document 02, ordered by geodesic distance, then `updatedAt` descending and UUID. Related-place selection changes selection without changing scope.

## Adaptive map geometry and controls

The map and its overlays respond continuously to window size, scene geometry, safe-area changes and iPhone Duo pose changes. Recalculate map padding from the actual visible bars, sheet/panel, keyboard and each safe-area edge; do not assume symmetric insets. Full-bleed map content may extend behind system chrome, but annotations, selected content and custom interactive controls remain visible and reachable. If the SDK exposes a reserved fold/camera region, keep important content and controls clear of it without deriving a pose from model or orientation.

Use system navigation, toolbar, sheet, menu and alert components so bars and presentations can move around the iPhone Duo fold/curve and camera regions. When bars become vertical, actions retain concise labels and intentional priority; lower-priority actions move to usable overflow. Map controls remain operable by touch, hardware keyboard, trackpad/pointer, Voice Control and Switch Control, have VoiceOver labels/selected state and at least a 44-by-44-point target when custom. Dynamic Type may reduce simultaneous metadata or change the detail detent, but cannot remove the Save, Close, search, current-position, fit or navigation actions.

## Position, distance and directions

Request When In Use authorization at the first user action that needs device position, including the approved first actual Global Map activation above. Each request acquires one position through a CoreLocation adapter that exposes plain permission states and a typed asynchronous result to Domain. Accept the first geographically valid fix with valid metadata, including a finite timestamp that is not in the future, regardless of past age. Preserve the fix timestamp and finite, nonnegative horizontal accuracy; accept Reduced Accuracy and return authorization/accuracy state. Acquisition times out after 10 seconds if no usable fix arrives, starting only after authorization is granted; time waiting for the system permission prompt is excluded. End the one-shot request on the first accepted fix, failure, timeout or cancellation. Do not add a persistent position cache, background refresh or fallback to an old fix after timeout. Native visible-map user-location rendering may update independently.

Denied access returns a typed permission-denied error without requesting permission again. The incremental Global Map UI keeps initial/passive denial silent and shows an explanatory Settings/Cancel dialog immediately on an explicit current-position action, as specified in document 02. Services do not present dialogs or open Settings.

Handle reduced accuracy, denied/restricted access, invalid/future samples, no usable fix and cancellation. Invalid/future samples do not complete acquisition; wait for a valid fix only within the same bounded request. Show position age/accuracy when it affects usefulness and preserve the original timestamp; age alone does not invalidate a fix. For the first ETA in a map session, automatic mode uses walking at straight-line distance ≤1 km and driving otherwise. Display that mode next to the result and let the user select Walking or Driving for the active map session; the choice is not a hidden global preference. Offer route failure/unavailable state; never fabricate an ETA from straight-line distance. Label straight-line distance separately from route distance.

Key route requests by origin, destination coordinate or saved-record identity, mode and generation. Cancel/reject old requests on any key change, including manual pins without Place IDs. A nullable provider Place ID alone is not a sufficient change key. Changing distance units reformats the same metric value; it does not require a new directions request.

Directions handoff opens a destination even without ProjectAlpha location permission. The external app handles its own origin, permissions and offline support. Do not implement in-app turn-by-turn navigation in this scope.

## Loading and performance

Keep saved content visible during provider failures. Use cancellable asynchronous thumbnails and MapSnapshotter work with bounded caches. Avoid re-geocoding every record on each screen appearance. Optional address enrichment fills only missing values, checks current revisions and never prevents local rendering/saving.

Initial performance test dataset: 100 collections and 5,000 saved locations. This is a verification workload, not a product cap. Fetch efficient projection/count data, debounce invalidation, avoid one query per row, and profile map annotation behavior. If clustering or viewport loading is introduced for scale, Fit All still uses the complete logical scope and no location becomes inaccessible.
