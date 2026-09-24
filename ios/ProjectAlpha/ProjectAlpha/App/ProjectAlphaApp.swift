//
//  ProjectAlphaApp.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 12/9/26.
//

import SwiftUI

@main
struct ProjectAlphaApp: App {
    @State private var container = AppContainer(
        preferenceStore: UserDefaultsPreferenceStore(defaults: .standard)
    )

    var body: some Scene {
        WindowGroup {
            AppRootView(container: container)
        }
    }
}
