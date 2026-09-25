//
//  HomeView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.locale) private var locale
    @State private var viewModel: HomeViewModel

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ContentUnavailableView(
            LocalizedStringKey(HomeKeys.title.rawValue),
            systemImage: DSSystemIcon.homeFill.rawValue,
            description: Text(HomeKeys.scaffoldMessage)
        )
        .navigationTitle(Text(verbatim: LocalizationManager.localizedString(HomeKeys.title, locale: locale)))
    }
}

#Preview {
    HomeView(viewModel: .init(router: .init(root: .root)))
        .environment(\.locale, Locale(identifier: Language.english.code))
}
