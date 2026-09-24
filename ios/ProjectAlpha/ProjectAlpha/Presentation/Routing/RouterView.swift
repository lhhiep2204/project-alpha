//
//  RouterView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

struct RouterView<Route: Hashable, Destination: View>: View {
    @Bindable private var router: Router<Route>
    private let destination: (Route) -> Destination

    init(
        router: Router<Route>,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self.router = router
        self.destination = destination
    }

    var body: some View {
        NavigationStack(path: $router.paths) {
            destination(router.root)
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
    }
}
