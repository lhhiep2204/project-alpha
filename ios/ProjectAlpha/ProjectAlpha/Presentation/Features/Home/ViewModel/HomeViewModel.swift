//
//  HomeViewModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation

@Observable
@MainActor
final class HomeViewModel {
    private let router: Router<HomeRoute>

    init(router: Router<HomeRoute>) {
        self.router = router
    }
}
