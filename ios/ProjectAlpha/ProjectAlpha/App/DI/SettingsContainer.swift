//
//  SettingsContainer.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

@MainActor
final class SettingsContainer {
    func makeSettingsView(
        router: Router<SettingsRoute>
    ) -> SettingsView {
        SettingsView(
            viewModel: SettingsViewModel(
                router: router
            )
        )
    }
}
