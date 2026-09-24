//
//  MapViewModel.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation

@Observable
@MainActor
final class MapViewModel {
    private let router: Router<MapRoute>

    init(router: Router<MapRoute>) {
        self.router = router
    }
}
