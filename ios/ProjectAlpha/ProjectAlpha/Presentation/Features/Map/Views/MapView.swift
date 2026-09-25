//
//  MapView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

struct MapView: View {
    @Environment(\.locale) private var locale
    @State private var viewModel: MapViewModel

    init(viewModel: MapViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ContentUnavailableView(
            LocalizedStringKey(MapKeys.title.rawValue),
            systemImage: DSSystemIcon.mapFill.rawValue,
            description: Text(MapKeys.scaffoldMessage)
        )
        .navigationTitle(Text(verbatim: LocalizationManager.localizedString(MapKeys.title, locale: locale)))
    }
}

#Preview {
    NavigationStack {
        MapView(viewModel: .init(router: .init(root: .root)))
    }
    .environment(\.locale, Locale(identifier: Language.arabic.code))
}
