# Navigation, deep links and restoration

## Navigation model

```mermaid
flowchart TD
    Tabs[Scene: Home / Map / Settings]
    Tabs --> Home[Home: Collections]
    Home -->|Find Saved Places| FindGlobal[Global saved-place search]
    FindGlobal --> Coordinator[SceneCoordinator]
    Coordinator --> Global
    Home --> Collection[Collection Detail: Location list]
    Collection -->|Tap location| Focus[Collection Map: focus + detail]
    Collection -->|Show All| Fit[Collection Map: fit all, no detail]
    Tabs --> Global[Global Map: all saved locations]
    Tabs --> Settings[Settings]
    Widget[Widget location URL] --> Coordinator
    Coordinator -->|Select Map tab, resolve ID| Global
    Focus --> Editor[Location Editor sheet]
    Fit --> Editor
    Global --> Editor
    Editor --> Picker[Collection picker within editor flow]
```

One navigation stack per tab on compact layouts. Keep separate Home/Map/Settings route types. A wide layout may adapt content presentation without inventing a second competing navigation path for the same destination.

Conceptual route values (not copy-ready implementation):

```swift
enum HomeRoute: Hashable, Codable {
    case collection(id: UUID)
    case collectionMap(collectionID: UUID, entry: CollectionMapEntry)
}

enum CollectionMapEntry: Hashable, Codable {
    case all
    case location(id: UUID)
}

enum SettingsRoute: Hashable, Codable {
    case language
}
```

Tab roots do not have to be elements of a path. The existing `root` property may remain if useful. Global Map selection is its session state, not a pushed HomeRoute. Do not force an unused wrapper Route enum across all tabs merely because the scaffold has one.

Route values carry IDs and entry intent; they never carry a saved entity snapshot, closure, View, ViewModel, ModelContext or MapKit object. The selected location can change after entry without rewriting the path. SwiftUI supports programmatic paths for deep links and restoration. [Apple navigation guidance](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack)

## SceneCoordinator responsibilities

The coordinator owns selected tab, the three routers, modal ownership, pending external intent and navigation restoration. It references map-session presentation models through narrow interfaces. It does not own every form field or implement repository operations itself.

| Event | Result |
|---|---|
| Select Collection | Push its list in Home |
| Find Saved Places | Preserve Home path/filter; select Map tab and present Global Map search with `All Saved Places` scope |
| Select list Location | Push/activate that collection's map, focus ID and open detail |
| Show All | Push/activate that collection's map and issue fit-all camera intent |
| Back from Collection Map | Close map presentation and pop to list, preserving list query/scroll |
| Select another tab | Keep each tab's path and camera/session state |
| Widget Location | Select global Map, resolve latest record, focus and open detail |
| Selected Location deleted | Clear detail/selection, keep camera, show unavailable message if triggered externally |
| Scope Collection deleted | Trim Home path to nearest valid ancestor; typically Home |
| Selected Location moved | Collection Map removes selection if out of scope; Global Map keeps selection |

Hide the tab bar only while Collection Map is the visible Home destination. Restore it when returning to the list. Global Map does not explicitly hide the tab bar. Native modal sheets can temporarily cover underlying controls; Close remains available so users can return to tab navigation. Do not draw a second custom tab bar on top of a system sheet.

## Modal ownership

Use an explicit enum/session for mutually exclusive map presentation states: none, detail, search or editor. Read-only detail may adapt to an inspector on a wide iPad. A form flow may own an internal navigation stack for collection selection/new collection, avoiding a chain of sheet booleans.

Opening Search suspends detail presentation but remembers selection. Cancelling Search restores prior selection/detail. Choosing a result replaces selection. Home's Find Saved Places action uses this same Global Map search presentation; dismissing it does not modify Home's path/filter. Opening an editor suspends read-only detail; Save/Cancel restores the appropriate map session after the editor dismisses. Photo viewer/system share/camera is a child of the currently active presentation and must be dismissed before an unrelated external route is applied.

Only one presentation transition is in flight per scene. Drive follow-up transitions from actual dismissal completion (`onDismiss` or equivalent state acknowledgement), not an arbitrary sleep or `Task.yield()` used as a timing guarantee.

## Location-creation ownership

One stable `LocationDraft` belongs to the active creation flow. Candidate detail displays its destination and can commit quick capture directly; `Add Details`, destination picker and place selection all edit that same draft. Selecting a place while already inside a new-location editor fills the existing draft instead of presenting another editor. Replacing a candidate that would discard entered fields requires Keep Editing / Replace Place.

| Entry owner | Successful in-scope save | Successful out-of-scope save | Cancel |
|---|---|---|---|
| Collection Detail | Pop the creation presentation; refresh list/count and preserve query/scroll | Same return; confirmation names destination and offers View in Global Map | Return to the list and preserve state |
| Collection Map | Select committed record and focus when appropriate | Retain scope/camera; present committed receipt with explicit Open Saved Place | Restore previous selection/detail |
| Global Map | Select committed record globally | Not applicable because every collection is in scope | Restore previous selection/detail |

A committed receipt carries the saved UUID, destination ID and committed revision separately from the original candidate. It must not expose Save as though the completed operation were still pending. Opening its record re-resolves latest data and follows normal dirty-draft protection.

## External-intent contract

Working scheme: `projectalpha`; host/version: `v1`. This is the design contract for the independent app, not a claim it is registered already. Centralize the scheme in app/extension configuration and register it with the target before testing.

| URL pattern | Intent |
|---|---|
| `projectalpha://v1/home` | Open Home root |
| `projectalpha://v1/collections/{collectionUUID}` | Open Home → Collection Detail |
| `projectalpha://v1/map` | Open Global Map, retaining valid session camera/selection |
| `projectalpha://v1/map/location/{locationUUID}?source=widget-favorites` | Open Global Map and select the current saved record |
| `projectalpha://v1/map/location/{locationUUID}?source=widget-collection&collectionID={collectionUUID}` | Same destination; collectionID is context/diagnostic hint, not record authority |

`source` and `collectionID` are optional metadata. Missing or unrecognized source must not prevent a valid location ID from opening. Parser accepts known path shapes and UUIDs, rejects malformed/duplicate known query keys, extra path components, unsupported versions and inputs exceeding 8,192 UTF-8 bytes. Reject user-info, ports and fragments; they are not part of this contract. Ignore unknown query keys for forward compatibility. Use URLComponents; do not hand-concatenate unescaped user text.

The custom scheme is an entry point, not authentication. It only navigates; it cannot create/delete data, resolve file paths, run arbitrary commands or import untrusted entities. Universal Links are FUTURE because no ProjectAlpha web domain/association contract has been selected.

## Deep-link state machine

```mermaid
stateDiagram-v2
    [*] --> Parsed: receive URL at scene root
    Parsed --> Ignored: invalid or unsupported
    Parsed --> WaitingForStore: valid intent
    WaitingForStore --> Resolve: library ready
    WaitingForStore --> Recovery: storage failure
    Resolve --> ProtectDraft: resolved destination or missing-target fallback
    ProtectDraft --> Queued: dirty editor or write in flight
    ProtectDraft --> DismissPresentation: clean presentation
    Queued --> DismissPresentation: user discards / write completes safely
    Queued --> Cancelled: user keeps editing
    DismissPresentation --> ApplyIntent: dismissal acknowledged, target exists
    DismissPresentation --> Fallback: dismissal acknowledged, target missing
    ApplyIntent --> [*]
    Fallback --> [*]
```

1. Receive at scene root using the system URL lifecycle; do not attach the only handler to a conditional Home screen.
2. Parse to a Foundation intent. Wait for bootstrap; keep the latest queued navigation intent while bootstrapping.
3. Fetch the latest Location by UUID. Provider identity and widget cached collection name are not substitutes for the local UUID.
4. If an editor is dirty, show Keep Editing / Discard Changes. Keep Editing cancels the intent. Discard performs draft cleanup, waits for dismissal, re-resolves the target, then navigates. Do not silently save a draft. If a commit is already in flight, wait for its result before deciding.
5. Dismiss clean presentations using their lifecycle, then select Map and update Global Map's selection/camera/detail. Leave Home's path/session intact.
6. Recheck target validity when applying the intent because data may change while a dialog is open.
7. Use an intent-generation token: a slower earlier fetch cannot overwrite a newer requested destination. Repeated delivery of the same intent should focus once without growing a path.

Malformed URLs leave current UI unchanged. A missing location from a valid URL opens Global Map with no selected detail and a localized unavailable message, after respecting dirty-draft protection. A storage failure shows recovery and retains the pending intent for retry; it is not a "location deleted" result.

A location moved to a different collection still opens by its current UUID. A favorite removed after widget rendering still opens if the location exists. Widget navigation resolves the current record rather than trusting stale projected attributes. Refresh stale widget data afterwards.

## iPad and scene behavior

Navigation and drafts belong to a scene, never an app-global singleton. Shared persistence changes propagate to every active scene. A URL is consumed by the scene chosen by the system; other scenes do not all navigate in response. No new-window command is in v1 scope.

On resize, detail moves between a sheet and adjacent panel without changing route, selected Location or map scope. Use one detail content model and one selected ID; do not retain duplicate compact and regular presentation owners. Back/Close behavior remains the same with touch, keyboard and VoiceOver.

## Restoration

Use a versioned Codable scene-navigation snapshot for selected tab, valid Home/Settings paths, saved selection IDs and last camera geometry per map session. Persist compact values, not whole entity arrays. Scope to scene identity and debounce writes.

Restore after bootstrap, validating each ID against storage. Prune missing descendants, clear invalid selections and show a valid ancestor; do not recreate deleted collections. Restore global and collection cameras independently. A new deep link supersedes stale restoration work.

Do not restore an open camera/share sheet, unresolved provider suggestion, confirmation dialog or unfinished editor UI. Local staged media is reconciled by draft recovery; v1 does not promise automatic form recovery after process termination. Language changes must not force root `.id(...)` replacement that destroys active navigation/drafts.
