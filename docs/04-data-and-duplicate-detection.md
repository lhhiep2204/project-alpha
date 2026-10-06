# Data, duplicate detection and media

## Domain values

All values crossing isolation boundaries are `Sendable`. UUIDs identify saved records; Apple Place IDs identify provider places. They are not interchangeable.

| Value | Required fields / meaning |
|---|---|
| Collection | `id: UUID`, `name: String`, `isDefault: Bool` (system-controlled), `createdAt`, `updatedAt`, `revision: Int64`. No icon or cover field; Presentation displays the fixed folder symbol for every collection. |
| SavedLocation | `id`, `collectionID`, `placeIdentity?`, `source`, `name`, optional `displayName`, optional `address`, `coordinate`, optional `category`, optional `notes`, ordered `[LocalAssetReference]`, `isFavorite`, timestamps, revision |
| Coordinate | Finite latitude `[-90,90]`, longitude `[-180,180]`; absence is optional, never encoded as `(0,0)` |
| PlaceIdentity | `provider = appleMaps`, nonempty opaque `primaryID`, set of nonempty `alternateIDs`; no lowercasing/semantic parsing of provider IDs |
| PlaceCandidate | Draft identifier, source, resolved coordinate, provider identity if trustworthy, name/address/category; no collection ownership |
| PlaceSuggestion | Opaque suggestion/session ID, title/subtitle; must resolve before saving |
| LocationDraft | Stable candidate or existing location ID, destinationCollectionID, editable fields/assets, expected revision for edits, duplicate-warning acknowledgement |
| DevicePosition | Coordinate, timestamp, horizontal accuracy and authorization state, not a saved Location |
| RouteEstimate | Distance in metres, duration, mode, computedAt and origin/destination identity |
| LocalAssetReference | App-managed asset UUID and relative file token; no absolute sandbox path or remote URL |

Existing ProjectAlpha `Collection.visibility` and `share` fields are scaffold artifacts. They are not v1 behavior. During implementation, remove unused sharing models/references or keep them only outside the v1 persistent schema; never expose public/private/account controls without the future feature specification.

## Invariants

| ID | Invariant |
|---|---|
| INV-01 | Exactly one default collection exists after successful bootstrap. User commands cannot edit its fields, including its name and default flag, or delete it. |
| INV-02 | Every saved location references one existing collection. Unresolved candidates never enter persistent location storage. |
| INV-03 | Same known place cannot be inserted twice into the same collection; cross-collection copies are independent records. Apply the identity limits below honestly. |
| INV-04 | Deleting a collection and its locations is one database commit. No partial child deletion on failure. |
| INV-05 | Success is emitted only after persistence succeeds. Failed operations emit no committed-data event. |
| INV-06 | Never delete a file referenced by committed data before the database successfully removes that reference. |
| INV-07 | IDs and `createdAt` are stable; each successful mutation advances record and library revisions and sets `updatedAt`. |
| INV-08 | Draft cancellation does not mutate existing records/photos. New draft assets are recoverably cleaned up. |
| INV-09 | Resizing, multitasking, display/pose changes or adaptive presentation changes never alter the logical route, selected record, map scope/camera/search, draft identity/fields/staged media or available functionality. |

## Duplicate policy

### What is being compared

Evaluate only existing locations in the **destination collection** and exclude the edited/moved record's own UUID. Resolve provider suggestions before evaluation. A button-level check improves feedback but does not replace the serialized persistence check.

For an Apple place, construct `identitySet = {primaryID} ∪ alternateIDs`. If it intersects an existing record's known Apple identity set, return a blocking duplicate with that record's ID. An exact primary-ID-only database constraint is insufficient.

Apple documents that aliases are nonexhaustive: different IDs can still refer to one real-world place. The app guarantees the policy over available identity data, not perfect recognition of every physical place. Persist known aliases and use authoritative resolution results when available. Do not require online lookup to save an offline manual pin. [Apple: identifying places and alternate IDs](https://developer.apple.com/documentation/mapkit/identifying-unique-locations-with-place-ids)

### No-ID fallback approved by the user

Engineering constants for v1:

- Coordinate normalization: integer microdegrees, `round(value × 1_000_000, ties away from zero)`; convert negative zero to zero and normalize longitude +180 to -180 for comparison only. Preserve the original valid coordinate for rendering.
- Name normalization: Unicode NFC; trim leading/trailing Unicode whitespace; collapse each internal whitespace run to ASCII space; apply Unicode default full case folding (not the locale-specific Turkic variant); finish with NFC. Do not remove diacritics or punctuation or use the display language's locale. Centralize this policy and test composed/decomposed accents, non-ASCII whitespace and case variants; changing normalization later requires compatibility tests against existing records.
- Identity name is the provider/manual `name`, not the optional custom display name. A nameless manual pin uses a stable internal `dropped-pin` marker, localized only for display.
- Nearby-warning threshold: geodesic distance ≤20 metres. This is a warning threshold, not proof of sameness or a forbidden save radius.

Evaluation order:

1. Intersecting provider IDs/aliases → **block**.
2. If at least one side has no usable provider identity, same normalized coordinate **and** same normalized identity name → **block**.
3. Otherwise, coordinate distance ≤20 m → **possible duplicate warning**. Different provider IDs alone cannot prove distinctness because alias sets may be incomplete.
4. Otherwise → allow.

The same normalized name at a remote coordinate does not warn by itself. Two businesses in the same building can be saved after the proximity warning. A custom display-name change does not bypass a provider-ID match. Empty IDs are absent, never shared identifiers.

Coordinates near a rounding boundary may not match exactly; the distance warning catches this as a possible duplicate. No fuzzy match silently merges records or discards notes/photos.

### Result and interaction contract

Conceptual result:

```text
allowed
blockingDuplicate(existingLocationID, reason)
possibleDuplicates(candidateIDs, evaluationToken)
```

Blocking result offers Open Saved Place, Choose Another Collection or return to the draft. No Save Anyway for a hard duplicate. A warning offers Open Saved Place, Save Anyway or Cancel. If multiple matches exist, show a list including name and address.

An acknowledgement is scoped to the draft identity, destination and matched record revisions. Save Anyway re-evaluates inside the store; a newly discovered hard duplicate always blocks. If relevant data or destination changes, show a new warning. Never hold an actor/database transaction open while waiting for user input.

Idempotence is separate from place equivalence: allocate a stable draft Location UUID once. Repeating a successful create for that same draft returns its committed result instead of inserting a second row. A retry never overwrites an existing row; changed content must use the revision-checked update command, and an unrelated UUID collision returns a conflict. Disabling Save alone is not enough.

### Required examples

| Candidate vs existing in destination | Result |
|---|---|
| Apple primary A vs primary A | Block |
| Apple primary B, aliases {A} vs primary A | Block |
| Known alias intersection without equal primaries | Block |
| Same Apple place in a different collection | Allow there |
| Editing a record, matching its own ID | Exclude self; do not block |
| Move into collection already containing its place | Block; keep original owner |
| No-ID pin, same microdegrees and normalized name | Block |
| Same name at coordinates farther than 20 m apart | Allow when no provider/alias or exact fallback rule blocks it |
| Different names at nearby coordinates | Warn; allow explicit Save Anyway |
| Two different known IDs at same building | Warn, do not automatically merge |
| `(0,0)` pin with no address | Valid; normal duplicate policy |
| Two concurrent creates of the same known place | One commit; other returns duplicate |

## SwiftData schema v1

| Model | Persistence responsibility |
|---|---|
| CollectionLocal | Unique UUID, name, system-controlled default flag, timestamps/revision; no icon or cover column |
| LocationLocal | Unique UUID, collectionID, provider/primary/alias fields, source, name/display name/address, latitude/longitude, category/notes, ordered asset IDs, favorite, timestamps/revision |
| AssetLocal | Unique asset UUID, relative file token, content type, dimensions and creation time; owner reference maintained by serialized writes |
| LibraryMetadataLocal | Single metadata key, schema-related application metadata and monotonically increasing library revision |
| MediaCleanupLocal | File token, retry metadata for post-commit deletion; local maintenance, not a remote sync outbox |

Use `VersionedSchema` and `SchemaMigrationPlan` from the first release. Store only local application data, with CloudKit synchronization explicitly disabled. The widget does not open this store.

Domain exposes `collectionID`. For v1, persistence also uses a scalar collection UUID and explicit transactional cascade. This keeps the ownership contract simple and avoids mixing scalar and relationship sources of truth. All writes are private to LibraryStore, which enforces existence/cascade; no other context may insert a LocationLocal directly. Query/index collectionID, primary identity and revision fields as justified by profiling. Any future switch to SwiftData relationships requires a schema migration and invariant tests.

UUID uniqueness is a persistence guard, not the duplicate-place policy. SwiftData uniqueness/upsert behavior must not be used to silently overwrite another location's user content. Explicitly fetch/check before insertion.

### Bootstrap

Open/migrate the store before navigation consumes data. Inside the store actor, fetch default collections; if none exists, create one with the localized initial title for the language in effect at creation (English source: “My Places”) and commit. Persist the resulting text as the default collection's fixed name: later language changes do not rename it, and user commands cannot edit it. If exactly one default exists, keep it and its current name. User-facing create/update commands cannot set/unset `isDefault`; user-facing update/delete commands reject the default collection without changing records. Sequential bootstrap calls are idempotent. Multiple defaults from corruption or a future migration trigger a recoverable diagnostic, never a destructive reset. The single writer ensures concurrent scene startup cannot create two defaults.

### Atomic mutation contract

1. Complete asynchronous provider/media preparation outside the write critical section.
2. Within the serialized store method, load the latest affected records and validate destination, protected-default rules, expected revisions and duplicates.
3. Apply changes and increment revisions; enqueue obsolete media tokens for cleanup in the same database operation.
4. Save once. If any step fails, call rollback and throw; retain the editor draft.
5. Publish the committed revision; run media cleanup and widget projection afterwards. Those failures do not turn an already committed save into a reported save failure.

Delete Collection loads and deletes its child locations/assets plus the parent in this one operation. Do not chain repository methods that each save. Move Location patches the owner only after duplicate validation. SetFavorite patches the latest stored favorite flag; it must not overwrite notes with a stale whole-entity snapshot.

Editors carry the revision they began with. If another scene changes that record, reject stale editor commit with an edit-conflict result and let the user reload/reapply their draft. Internal metadata enrichment only fills still-empty fields and rechecks identity; it must not restore stale data or automatically merge a new identity collision.

The conflict result carries the latest immutable domain value while retaining the user's local draft. Presentation shows both versions and offers Reload or Reapply. Reload confirms before discarding dirty local fields. Reapply creates a new revision-checked command against current data and repeats validation/duplicate checks; it is never a blind overwrite.

## Media lifecycle

Location photos are local files in Application Support, referenced by stable tokens. A location supports at most five images; collections have no media assets. Expose remaining location-photo capacity before selection and reject a sixth asset before staging. Use PhotosPicker for selected library assets and a camera adapter when available. Camera absence on simulator/iPad configurations is handled gracefully. Report import/decode failures per asset while retaining the rest of the draft for retry/removal.

Stage selected media under a draft ID. Validate and downsample off the UI actor; use a 1600-pixel longest side and JPEG quality 0.78 as tunable encoding defaults. Use ImageIO downsampling rather than loading a full-resolution photo simply to make a thumbnail. Preserve orientation; explicitly strip unnecessary GPS metadata. User-visible thumbnails load asynchronously with a bounded cache.

Before database commit, finalize new files atomically under stable final tokens. If database commit fails, keep new files tracked by the draft for retry/cancel; they must not become untracked leaks. Old files remain untouched. After commit, schedule removed files for deletion using MediaCleanupLocal, then retire staged ownership. Database and filesystem changes are not one ACID transaction: this ordering favors recoverable orphan files over lost user photos.

On cancellation delete only the location draft's uncommitted assets. On startup reconcile abandoned location-photo drafts and unreferenced finalized files against current ownership. Never delete active draft assets or a file still referenced by another record; recheck ownership and references immediately before deletion. Cleanup retries failures. Photo viewers show a placeholder for missing/corrupt files without crashing.

## Recovery and future changes

Storage errors remain visible and retryable. Never automatically delete/reset a failed store. Back up/check the store before a destructive future migration. There is no data-import flow or account-based media policy in v1.

Later cloud sync must introduce separate remote identity, revision/conflict and asset-transfer concepts. Do not overload today's `updatedAt`, UUID or cleanup queue as a complete synchronization protocol.
