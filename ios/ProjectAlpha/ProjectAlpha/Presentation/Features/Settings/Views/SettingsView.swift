//
//  SettingsView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section("Application") {
                LabeledContent("Version", value: AppInfoHelper.appVersionDescription)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView(viewModel: .init(router: .init(root: .root)))
}
