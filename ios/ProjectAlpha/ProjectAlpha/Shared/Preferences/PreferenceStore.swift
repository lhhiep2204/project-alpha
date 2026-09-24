/// Small app-preference boundary, not a business-domain repository.
/// Access is serialized on MainActor; background work receives copied values.
@MainActor
protocol PreferenceStore: AnyObject {
    var language: Language { get set }
    var theme: AppTheme { get set }
    var mapType: MapType { get set }
    var distanceUnit: DistanceUnit { get set }
}
