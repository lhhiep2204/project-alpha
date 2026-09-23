# Widget specification

## Product contract

Two Home Screen widgets: Favorites and Collection. Favorites needs no collection configuration. Collection uses an AppIntent configuration with an AppEntity picker. Support Small, Medium, Large and Extra Large where supported on iPad. No editing buttons, location updates, provider search, account access, Lock Screen widget or Siri/Shortcuts actions in v1.

| Interaction | Destination |
|---|---|
| Tap a saved location row | Global Map tab, latest record selected, detail open |
| Tap populated widget background/header | Global Map tab; retain valid map session state |
| Empty Favorites | Home root, with normal collection navigation |
| Empty selected Collection | Home → that Collection Detail if it exists |
| Collection not configured/deleted | Home root; widget explains Choose a Collection |

All location-row destinations obey U-14, regardless of widget kind. A changed favorite flag or collection membership does not make an existing Location UUID invalid.

## Data boundary

The app writes a versioned Codable snapshot to its own App Group; widgets read that projection only. No widget dependency on AppContainer, Domain use-case containers, ModelContext, full-resolution photos, or the app's live store. Shared contracts are compiled into both app and extension targets or extracted to an extension-safe local target.

Configure a ProjectAlpha-specific App Group shared only by the signed app and widget extension. The exact registered identifier is a release configuration value, not invented here.

Snapshot schema v1:

```text
schemaVersion: 1
libraryRevision: Int64
generatedAt: Date
localeIdentifier: String
collections: [{ id, title, locationCount, updatedAt }]
locations: [{ id, collectionID, title, address?, category?, isFavorite, updatedAt }]
```

Omit coordinates, notes, media and sharing/account fields because the widget does not need them. `locationCount` lets configuration distinguish same-titled collections without exposing private location details. Source data stays in the private app store; the shared snapshot is minimal. Store `generatedAt` for diagnostics, not as a reason to delete otherwise usable data.

The app must obtain collections and locations in one consistent store read/revision, avoiding a snapshot with a child whose parent was read before/after deletion. Publication encodes and writes atomically. Keep a last-known valid generation if a new read/decode fails; return a distinct unavailable state when no valid data exists. Do not show fabricated sample locations outside gallery previews.

## Publication and failure semantics

1. Successful writes emit a committed library revision.
2. One app integration publisher coalesces pending refreshes, reads the latest snapshot and encodes it outside UI work.
3. Serialize final writes and reject older revisions, so a slow revision N cannot replace N+1.
4. Atomically replace the snapshot, then request reload of affected widget kinds with WidgetCenter.
5. If projection or reload fails, the original CRUD operation is still successful. Keep a retry-needed state and reconcile on foreground/startup.

Publish after collection create/rename/delete, location create/update/move/delete, favorite change and language change. A language-only publication may have the same library revision; sequence publication requests with an independent generation counter and include the resolved locale. Do not ignore a new language simply because revision is unchanged.

Startup/foreground repair covers process death between database commit and snapshot publication. The widget may refresh its timeline on a conservative schedule, but it can only read the snapshot available to it. WidgetKit controls refresh timing; never promise instant visual refresh after `reloadTimelines`. [Apple: keeping widgets up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

## Configuration, order and missing data

Collection AppEntity queries read the shared snapshot. Support search by title, ID resolution and suggested entities. If titles collide, entity labels include the location count and, when still needed, the localized last-updated date; never silently select the first match. An unconfigured widget shows a choose-collection state. A deleted configured collection must **not** silently switch to the first remaining collection; show a missing-collection state instead.

Favorites filters all snapshot locations by `isFavorite`. Collection filters by exact collection UUID. Order each by localized title comparison, collection title for equal location titles and UUID as the final stable tie-breaker. This stable retrieval order does not move a shortcut merely because its notes were edited. If a record was moved or unfavorited after rendering, app-side URL resolution still opens it when it exists.

## Layout, accessibility and links

Small shows up to three readable rows; Medium/Large choose a row count from usable height rather than clipping a fixed count; Extra Large can use two columns. Treat family, proposed size and WidgetKit content margins as the available-space contract; do not infer device model, idiom, orientation or screen bounds. At large Dynamic Type, reduce rows while retaining the main action. Include collection/title context, short address and a provider-category symbol; do not use color alone to encode state.

Use exactly one `widgetURL` as the background destination and `Link` for row destinations supported by the target family. Current Apple deep-link guidance includes Small among multi-target families, while some older/general widget pages list only Medium and larger. The iOS 27 implementation must verify row hit targets on a real Small widget, not just a SwiftUI preview. If the runtime does not support per-row targets as documented, record the limitation and resolve the Small interaction design before marking its acceptance criteria complete. [Apple widget deep-link guidance](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)

Honor light/dark/tinted widget appearances, system content margins, Dynamic Type, VoiceOver, Voice Control, Switch Control, Reduce Motion/Transparency and RTL. Use the shared resolved language; localize configuration titles, entity labels and empty/error copy. Neither a hard-coded font size nor `.minimumScaleFactor` is a substitute for an accessible layout. Use native widget controls/links and targets with clear labels; no widget action may disappear only because the containing app window or iPhone Duo pose changed before launch.

## Verification requirements

Test snapshot encoding/decoding/version rejection, consistent parent/child data, revision ordering, locale-only updates, deleted configurations, missing/corrupt/unavailable App Group files, and retry after publication failure. Widget tests must never read or write the real production App Group.

Verify taps from Small/Medium/Large/Extra Large, cold launch, warm app, another selected tab and dirty editor. Include iPhone and iPad family/appearance variants, large text and RTL. Assertions belong to the navigation contract, not only URL parsing. Validate signed entitlements, extension target membership and privacy of snapshot contents before release.
