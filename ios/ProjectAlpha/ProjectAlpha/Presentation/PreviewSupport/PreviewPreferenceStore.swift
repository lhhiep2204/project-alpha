//
//  PreviewPreferenceStore.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/9/26.
//

@MainActor
final class PreviewPreferenceStore: PreferenceStore {
    var language: Language = .system
    var theme: AppTheme = .system
    var mapType: MapType = .standard
    var distanceUnit: DistanceUnit = .kilometre

    init(language: Language = .system) { self.language = language }
}
