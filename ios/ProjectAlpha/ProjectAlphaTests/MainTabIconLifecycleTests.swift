//
//  MainTabIconLifecycleTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 15/10/26.
//

import SwiftUI
import UIKit
import XCTest
@testable import ProjectAlpha

private enum TabIconTestValue {
    static let tabBarReady = "Native tab bar installed its initial items"
    static let selectionRendered = "Native tab bar rendered the selected destination"
    static let viewport = CGSize(width: 390, height: 844)
    static let tabs: [MainTab] = [.home, .map, .settings]
    static let configuration = UIImage.SymbolConfiguration(pointSize: 23, weight: .regular)
}

/// U-03: exercise actual SwiftUI-to-UIKit tab construction without live destinations.
@MainActor
final class MainTabIconLifecycleTests: XCTestCase {
    func testInitialIconsAndSelectionChangesInLightAndDarkAppearances() async throws {
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let coordinator = SceneCoordinator()
            let host = UIHostingController(rootView: MainTabView(coordinator: coordinator) { _, _ in
                Text(MainTab.home.title)
            } map: { _ in
                Text(MainTab.map.title)
            } settings: { _ in
                Text(MainTab.settings.title)
            })
            host.overrideUserInterfaceStyle = appearance
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousKeyWindow = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            window.frame.size = TabIconTestValue.viewport
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }

            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.tabController(in: host)?.tabBar.items?.count == TabIconTestValue.tabs.count
            }, object: nil)
            ready.expectationDescription = TabIconTestValue.tabBarReady
            await fulfillment(of: [ready], timeout: 5)
            let tabs = try XCTUnwrap(tabController(in: host))

            // No selection mutation precedes this assertion: it catches first-launch filling.
            try assertIcons(in: tabs.tabBar, selected: .home)
            for selection in [MainTab.map, .settings, .home] {
                coordinator.selectedTab = selection
                let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    guard let index = TabIconTestValue.tabs.firstIndex(of: selection),
                          tabs.selectedIndex == index,
                          let items = tabs.tabBar.items else { return false }
                    return zip(items, TabIconTestValue.tabs).allSatisfy { item, tab in
                        item.image?.pngData() == self.expectedImage(for: tab, selected: selection).pngData()
                    }
                }, object: nil)
                rendered.expectationDescription = TabIconTestValue.selectionRendered
                await fulfillment(of: [rendered], timeout: 5)
                try assertIcons(in: tabs.tabBar, selected: selection)
                XCTAssertEqual(coordinator.selectedTab, selection)
            }
        }
    }

    private func assertIcons(in bar: UITabBar, selected: MainTab) throws {
        let items = try XCTUnwrap(bar.items)
        XCTAssertEqual(items.count, TabIconTestValue.tabs.count)
        for (item, tab) in zip(items, TabIconTestValue.tabs) {
            let image = try XCTUnwrap(item.image)
            XCTAssertEqual(image.pngData(), expectedImage(for: tab, selected: selected).pngData())
        }
        XCTAssertEqual(bar.tintColor.resolvedColor(with: bar.traitCollection),
                       UIColor.label.resolvedColor(with: bar.traitCollection))
        XCTAssertEqual(bar.unselectedItemTintColor?.resolvedColor(with: bar.traitCollection),
                       UIColor.label.resolvedColor(with: bar.traitCollection))
    }

    private func expectedImage(for tab: MainTab, selected: MainTab) -> UIImage {
        let symbol = tab == selected ? tab.selectedSystemImage : tab.systemImage
        let image = UIImage(systemName: symbol, withConfiguration: TabIconTestValue.configuration)!
        return UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
    }

    private func tabController(in controller: UIViewController) -> UITabBarController? {
        if let tabs = controller as? UITabBarController { return tabs }
        return controller.children.lazy.compactMap { self.tabController(in: $0) }.first
    }
}
