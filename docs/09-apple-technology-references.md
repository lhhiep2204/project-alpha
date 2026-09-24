# Apple technology baseline and references

Platform references reviewed on 2026-09-24; local toolchain and SDK evidence verified on 2026-09-23. Product baseline is iOS/iPadOS 27. Use current Apple-native capabilities when they serve the requirements; an API need not have been introduced in iOS 27 to be the correct choice. Apple's current Human Interface Guidelines and iPhone Duo guidance are product-design authority, while the selected installed SDK remains the authority for symbols that can compile.

## Local toolchain evidence

Read-only commands returned:

```text
xcodebuild -version
Xcode 27.0
Build version 27A266a

xcodebuild -showsdks
iOS 27.0 / iOS Simulator 27.0 present

xcrun swift --version
Apple Swift version 6.4 (swiftlang-6.4.0.34.1)
```

ProjectAlpha currently sets deployment target 27.0 and `SWIFT_VERSION = 6.0` for app and test targets. Compiler version and Swift language mode are different settings; do not set `SWIFT_VERSION = 6.4` merely because the compiler reports 6.4. The project also sets `TARGETED_DEVICE_FAMILY = "1,2"` for iPhone/iPad. These current-state facts were verified in the untracked `project.pbxproj` and agree with document 10.

The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency. This matters when evaluating inferred isolation throughout ProjectAlpha. The design requires explicit Domain/storage boundaries instead of assuming every type is nonisolated.

Headers inspected under the installed `iPhoneOS27.0.sdk` verify:

| SDK header | Verified declaration |
|---|---|
| `MapKit.framework/Headers/MKMapItem.h:24–25` | Primary identifier and `alternateIdentifiers`, available since iOS 18 |
| `MapKit.framework/Headers/MKMapItem.h:50` | `init(location:address:)` Objective-C counterpart, available since iOS 26 |
| `MapKit.framework/Headers/MKReverseGeocodingRequest.h:13,25–27` | Reverse-geocoding request and asynchronous map-item result, available since iOS 26 |
| `MapKit.framework/Headers/MKMapItemRequest.h:22–33` | Requests by identifier/feature annotation and deprecated older feature-annotation accessor |

These are symbol/availability checks, not a compiled prototype or runtime verification. The web release-notes landing page was reachable but returned a JavaScript-only body in this research tool, so no unverified iOS 27-specific behavior is asserted from that page.

Apple's current iPhone Duo guidance describes Xcode 27.1 Device Hub, full-screen Duo behavior, reserved regions and arrangement views. This machine currently has Xcode/iPhoneOS SDK 27.0. A read-only declaration search found no public SwiftUI `ReservedRegion` or `ArrangementView` declaration in that installed SDK. Therefore the specification records the required behavior but does not claim those symbol names compile locally. Before using them, install/select an SDK that declares them, verify exact spelling and availability, and compile a focused use. Do not invent compatibility shims under guessed API names or silently raise/change the deployment target. Standard safe areas, size classes, scene geometry and native containers remain the required 27.0-compatible foundation.

## Technology decisions and official sources

| Area | Decision | Primary reference |
|---|---|---|
| Platform design baseline | Follow current Apple HIG with standard, consistent, adaptable UI | [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines) |
| Settings and app appearance | Provide an in-app settings area when people need to customize the overall app experience; use SwiftUI's preferred color-scheme mechanism to apply an app appearance through its presentation hierarchy | [Settings HIG](https://developer.apple.com/design/human-interface-guidelines/settings), [preferredColorScheme(_:)](https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme%28_%3A%29) |
| Adaptive layout | Respond to traits, safe areas, resizing, Dynamic Type and locale; test iPad halves, thirds and quadrants | [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) |
| iPhone Duo design | One resizable experience across displays/poses; preserve hierarchy/functionality and avoid fixed screen metrics | [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/) |
| iPhone Duo implementation | Use size classes/local scene geometry, native adaptive navigation, asymmetric safe areas and verified reserved-region APIs | [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/) |
| iPhone Duo bars | Let standard navigation/tool/tab bars adapt vertically; label, prioritize and retain overflow actions | [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/) |
| Fold-aware layouts | Keep important content/controls clear of reserved regions; use arrangement APIs only after SDK verification | [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/) |
| Duo resizing/scenes | Treat side-by-side and video/app layouts as scene-geometry changes; preserve scene-local state | [Leverage multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/) |
| SwiftUI state | Observation with appropriate State/Bindable/Environment ownership | [Managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app) |
| Navigation | Typed paths, ID-based destinations, scene restoration | [Understanding the navigation stack](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack) |
| Adaptive hierarchy | Stack on compact space; use system split/adjacent columns where wider hierarchy benefits | [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) |
| Top-level destinations | Preserve Home/Map/Settings while allowing system tab/sidebar adaptation | [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) |
| Native design | Standard controls and restrained Liquid Glass | [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) |
| Search UX | One clear global retrieval entry plus visibly scoped local search | [Searching](https://developer.apple.com/design/human-interface-guidelines/searching) |
| Data entry UX | Quick capture with optional details and explicit validation | [Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data) |
| Privacy UX | Deliberate note inclusion and transparent local-storage limits | [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) |
| Adaptive detail | Inspector/panel on wide layouts, sheet on compact | [Inspectors in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10161/) |
| Map interaction behind detail | Explicit sheet background interaction policy | [presentationBackgroundInteraction](https://developer.apple.com/documentation/swiftui/view/presentationbackgroundinteraction(_:)) |
| Map camera | Bindable camera position and explicit focus/fit intents | [MapCameraPosition](https://developer.apple.com/documentation/mapkit/mapcameraposition) |
| Place identity | Persist opaque IDs plus known aliases; document incomplete alias knowledge | [Identifying unique locations with Place IDs](https://developer.apple.com/documentation/mapkit/identifying-unique-locations-with-place-ids) |
| Place resolution | Resolve the selected feature/provider identifier | [MKMapItemRequest](https://developer.apple.com/documentation/mapkit/mkmapitemrequest) |
| Map metadata | Current location/address APIs instead of deprecated placemark-only construction | [MKMapItem](https://developer.apple.com/documentation/mapkit/mkmapitem) |
| Local storage | Isolated context with explicit commits and rollback | [ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext), [transaction](https://developer.apple.com/documentation/swiftdata/modelcontext/transaction(block:)) |
| Persistence isolation | One actor boundary for local store operations | [ModelActor](https://developer.apple.com/documentation/swiftdata/modelactor) |
| Schema evolution | Versioned schema and explicit migration plan | [SchemaMigrationPlan](https://developer.apple.com/documentation/swiftdata/schemamigrationplan) |
| Device location | Async CoreLocation adapter, on-demand authorization/lifetime | [CLLocationUpdate](https://developer.apple.com/documentation/corelocation/cllocationupdate) |
| Widget navigation | Widget URLs and row links delivered through app URL lifecycle | [Linking to app scenes](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity) |
| Widget freshness | Publish committed snapshots and request reload without real-time guarantee | [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date) |

## Decisions that come from ProjectAlpha, not Apple

Collection-scoped duplicates, the 20-metre proximity warning, microdegree rounding, five photos, three tabs, quick-capture placement, notes-off-by-default sharing, default collection protection, widget destination, draft interruption policy and local-only scope are product/engineering contracts in this specification. Do not attribute them to Apple documentation.

Clean Architecture, MVVM-style presentation models, a single app store writer and an App Group snapshot projection are engineering choices justified by this app's testability and ownership requirements. Apple frameworks support these choices but do not require this architecture.

## SDK verification during implementation

Before adopting a symbol suggested by an article/search snippet, HIG page or Tech Talk, verify its declaration and availability in the installed SDK and compile a focused use. In particular validate SwiftUI MapFeature request overloads, async cancellation behavior, the store actor's execution behavior, inspector adaptation, Small widget row interactions, iPhone Duo reserved-region/arrangement APIs and vertical-bar customization. Prefer current nondeprecated APIs; do not invent a new iOS 27/27.1 API name to satisfy the phrase "latest technologies".

The architecture contains no requirement for AI features, background location, Live Activities, CloudKit, a third-party maps SDK or server push. Add these only through explicit future product scope.
