//
//  Route.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation

enum HomeRoute: Hashable {
    case root
    case collection(id: UUID)
}

enum MapRoute: Hashable {
    case root
}

enum SettingsRoute: Hashable {
    case root
}
