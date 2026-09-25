//
//  MainTab.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

enum MainTab: Hashable {
    case home
    case map
    case settings

    var title: LocalizedStringKey {
        switch self {
        case .home: LocalizedStringKey(HomeKeys.title.rawValue)
        case .map: LocalizedStringKey(MapKeys.title.rawValue)
        case .settings: LocalizedStringKey(CommonKeys.settings.rawValue)
        }
    }

    var systemImage: String {
        switch self {
        case .home: DSSystemIcon.home.rawValue
        case .map: DSSystemIcon.map.rawValue
        case .settings: DSSystemIcon.settingsTab.rawValue
        }
    }
}
