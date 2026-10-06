//
//  SettingsView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

struct SettingsView: View {
    private enum AccessibilityID {
        static let language = "settings.language"
        static let theme = "settings.theme"
    }

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.locale) private var locale
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var preferences = preferences

        List {
            Section {
                Picker(selection: $preferences.language) {
                    ForEach(Language.allCases, id: \.rawValue) { language in
                        if language == .system {
                            Text(SettingsKeys.system).tag(language)
                        } else {
                            Text(languageName(for: language)).tag(language)
                        }
                    }
                } label: {
                    Text(SettingsKeys.language)
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier(AccessibilityID.language)
            }

            Section {
                Picker(selection: $preferences.theme) {
                    Text(SettingsKeys.system).tag(AppTheme.system)
                    Text(SettingsKeys.light).tag(AppTheme.light)
                    Text(SettingsKeys.dark).tag(AppTheme.dark)
                } label: {
                    Text(SettingsKeys.theme)
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier(AccessibilityID.theme)
            } header: {
                Text(SettingsKeys.appearance)
            }

            Section {
                LabeledContent {
                    Text(AppInfoHelper.appVersionDescription)
                } label: {
                    Text(SettingsKeys.version)
                }
            } header: {
                Text(SettingsKeys.application)
            }
        }
        .id(preferences.language)
        .navigationTitle(Text(verbatim: LocalizationManager.localizedString(CommonKeys.settings, locale: locale)))
    }

    private func languageName(for language: Language) -> String {
        Locale(identifier: language.code).localizedString(forIdentifier: language.code)
        ?? language.rawValue
    }
}

#Preview {
    NavigationStack {
        SettingsView(viewModel: .init(router: .init(root: .root)))
    }
    .environment(AppPreferences(store: PreviewPreferenceStore()))
    .environment(\.locale, Locale(identifier: Language.english.code))
    .preferredColorScheme(.light)
}
