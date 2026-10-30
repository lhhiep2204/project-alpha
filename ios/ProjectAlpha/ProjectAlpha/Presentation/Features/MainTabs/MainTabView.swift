//
//  MainTabView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI
import UIKit

/// Receives composed destinations without depending on App's DI containers.
struct MainTabView<Home: View, MapContent: View, Settings: View>: View {
    @Bindable var coordinator: SceneCoordinator
    @ViewBuilder let home: (HomeRoute, Binding<HomeRoute?>) -> Home
    @ViewBuilder let map: (MapRoute) -> MapContent
    @ViewBuilder let settings: (SettingsRoute) -> Settings

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            Tab(value: MainTab.home) {
                HomeNavigationView(router: coordinator.homeRouter, destination: home)
                    .background(TabBarIconAppearance())
            } label: {
                tabLabel(.home)
            }
            Tab(value: MainTab.map) {
                RouterView(router: coordinator.mapRouter, destination: map)
                    .background(TabBarIconAppearance())
            } label: {
                tabLabel(.map)
            }
            Tab(value: MainTab.settings) {
                RouterView(router: coordinator.settingsRouter, destination: settings)
                    .background(TabBarIconAppearance())
            } label: {
                tabLabel(.settings)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.primary)
        .environment(\.symbolVariants, .none)
    }

    private func tabLabel(_ tab: MainTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(uiImage: TabBarIconImages.image(for: tab, selected: coordinator.selectedTab == tab))
                .renderingMode(.template)
        }
    }
}

/// Raster templates preserve the chosen outline/fill shape when SwiftUI builds
/// native tab items. Symbol-backed UIImages can be automatically filled on launch.
@MainActor
private enum TabBarIconImages {
    private static let configuration = UIImage.SymbolConfiguration(pointSize: 23, weight: .regular)
    private static let images: [MainTab: (normal: UIImage, selected: UIImage)] =
        Dictionary(uniqueKeysWithValues: [MainTab.home, .map, .settings].map { tab in
            (tab, (render(tab.systemImage), render(tab.selectedSystemImage)))
        })

    static func image(for tab: MainTab, selected: Bool) -> UIImage {
        guard let images = images[tab] else { return UIImage() }
        return selected ? images.selected : images.normal
    }

    private static func render(_ symbol: String) -> UIImage {
        guard let image = UIImage(systemName: symbol, withConfiguration: configuration) else { return UIImage() }
        return UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(at: .zero)
        }.withRenderingMode(.alwaysTemplate)
    }
}

/// SwiftUI has no tab-bar modifier for the unselected icon tint.
/// Configure only this scene's native bar; dynamic label color follows its appearance.
private struct TabBarIconAppearance: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TabBarIconAppearanceController {
        TabBarIconAppearanceController()
    }

    func updateUIViewController(_ controller: TabBarIconAppearanceController, context: Context) {
        controller.updateIconColors()
    }
}

private final class TabBarIconAppearanceController: UIViewController {
    override func loadView() {
        view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        updateIconColors()
    }

    func updateIconColors() {
        guard let tabBar = tabBarController?.tabBar else { return }
        tabBar.tintColor = .label
        tabBar.unselectedItemTintColor = .label
    }
}

/// The same selected Home route drives the wide detail column and compact navigation.
/// The split view remains mounted while the system changes its column presentation.
private struct HomeNavigationView<Destination: View>: View {
    @Bindable var router: Router<HomeRoute>
    @ViewBuilder let destination: (HomeRoute, Binding<HomeRoute?>) -> Destination

    private var selection: Binding<HomeRoute?> {
        Binding(
            get: { router.paths.first },
            set: { route in
                if let route, router.paths.first == route { return }
                router.paths = route.map { [$0] } ?? []
            }
        )
    }

    private var detailPath: Binding<[HomeRoute]> {
        Binding(
            get: { Array(router.paths.dropFirst()) },
            set: { nested in
                guard let root = router.paths.first else { return }
                router.paths = [root] + nested
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            destination(.root, selection)
        } detail: {
            if let route = selection.wrappedValue {
                NavigationStack(path: detailPath) {
                    destination(route, selection)
                        .navigationDestination(for: HomeRoute.self) { nested in
                            destination(nested, selection)
                        }
                }
            } else {
                ContentUnavailableView(
                    LocalizedStringKey(CollectionKeys.selectCollection.rawValue),
                    systemImage: DSSystemIcon.folder.rawValue
                )
            }
        }
    }
}

#Preview {
    MainTabView(coordinator: SceneCoordinator()) { _, _ in
        Text(MainTab.home.title)
    } map: { _ in
        Text(MainTab.map.title)
    } settings: { _ in
        Text(MainTab.settings.title)
    }
}

#Preview {
    MainTabView(coordinator: SceneCoordinator()) { _, _ in
        Text(MainTab.home.title)
    } map: { _ in
        Text(MainTab.map.title)
    } settings: { _ in
        Text(MainTab.settings.title)
    }
    .preferredColorScheme(.dark)
}

#Preview {
    HomeNavigationView(router: Router(root: HomeRoute.root)) { route, selection in
        switch route {
        case .root:
            List(selection: selection) {
                NavigationLink(value: HomeRoute.collection(id: Collection.mock.id)) {
                    Text(CollectionKeys.defaultCollectionName)
                }
            }
        case .collection:
            Text(CollectionKeys.emptyCollectionTitle)
        case .collectionMap:
            Text(MainTab.map.title)
        }
    }
}
