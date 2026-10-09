//
//  MapPreviewFixtures.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 7/10/26.
//

import Foundation
import SwiftUI

/// Map previews intentionally render a local canvas instead of starting MapKit tile or
/// user-location services. The production view always uses the native Map/UserAnnotation.
@MainActor
enum MapPreviewFixtures {
    static func model() -> MapViewModel {
        MapViewModel(router: .init(root: .root), deviceLocationService: MapPreviewLocationService())
    }

    static func coordinator() -> SceneCoordinator {
        let coordinator = SceneCoordinator()
        coordinator.selectedTab = .map
        return coordinator
    }
}

private nonisolated struct MapPreviewLocationService: DeviceLocationService {
    func authorization() async -> LocationAuthorization {
        LocationAuthorization(status: .denied, accuracy: .full, servicesEnabled: true)
    }

    func currentPosition() async throws(LocationServiceError) -> DevicePosition {
        throw .permissionDenied
    }
}

struct MapPreviewCanvas: View {
    var body: some View {
        Canvas { context, size in
            let background = CGRect(origin: .zero, size: size)
            context.fill(Path(background), with: .color(.secondary.opacity(MapPreviewMetrics.backgroundOpacity)))
            var streets = Path()
            for column in 1..<MapPreviewMetrics.divisions {
                let x = size.width * CGFloat(column) / CGFloat(MapPreviewMetrics.divisions)
                streets.move(to: CGPoint(x: x, y: 0))
                streets.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 1..<MapPreviewMetrics.divisions {
                let y = size.height * CGFloat(row) / CGFloat(MapPreviewMetrics.divisions)
                streets.move(to: CGPoint(x: 0, y: y))
                streets.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(streets, with: .color(.white), lineWidth: MapPreviewMetrics.streetWidth)
        }
        .accessibilityHidden(true)
    }
}

private enum MapPreviewMetrics {
    static let backgroundOpacity = 0.12
    static let divisions = 5
    static let streetWidth: CGFloat = 8
}

#Preview {
    MapPreviewCanvas()
}
