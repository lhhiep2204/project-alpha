//
//  Router.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

@Observable @MainActor
final class Router<Route: Hashable> {
    var paths: [Route]
    var root: Route

    init(
        paths: [Route] = [],
        root: Route
    ) {
        self.paths = paths
        self.root = root
    }
}

extension Router {
    func push(_ route: Route) {
        paths.append(route)
    }

    func pop() {
        guard !paths.isEmpty else { return }
        paths.removeLast()
    }

    func popToRoot() {
        paths.removeAll()
    }

    func popTo(_ route: Route) {
        guard let index = paths.firstIndex(of: route) else {
            Logger.error("Error: Specified route not found in the navigation stack.")
            return
        }
        paths = Array(paths.prefix(upTo: index + 1))
    }

    func updateRoot(_ route: Route) {
        root = route
        popToRoot()
    }
}
