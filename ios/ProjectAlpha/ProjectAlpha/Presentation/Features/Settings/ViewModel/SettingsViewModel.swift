//
//  SettingsViewModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation

@Observable
@MainActor
final class SettingsViewModel {
    private let router: Router<SettingsRoute>

    init(router: Router<SettingsRoute>) {
        self.router = router
    }
}
