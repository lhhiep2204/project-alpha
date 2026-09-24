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
        case .home: "Home"
        case .map: "Map"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .map: "map"
        case .settings: "gearshape"
        }
    }
}
