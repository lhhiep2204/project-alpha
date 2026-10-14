//
//  MapCurrentLocationButton.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 11/10/26.
//

import SwiftUI

struct MapCurrentLocationButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let isLocating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLocating {
                    ProgressView()
                        .tint(symbolColor)
                } else {
                    Image(systemName: MapCurrentLocationSymbols.currentLocation)
                }
            }
            .foregroundStyle(symbolColor)
            .frame(width: MapCurrentLocationMetrics.buttonSize, height: MapCurrentLocationMetrics.buttonSize)
            .background(
                reduceTransparency ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.clear),
                in: Circle()
            )
            .glassEffect(
                reduceTransparency ? .identity : .regular.interactive(!isLocating),
                in: .circle
            )
        }
        .buttonStyle(.plain)
        .disabled(isLocating)
        .accessibilityLabel(Text(isLocating ? MapKeys.locating : MapKeys.currentLocation))
        .accessibilityIdentifier(MapCurrentLocationAccessibility.button)
        .help(Text(MapKeys.currentLocation))
        .keyboardShortcut(KeyEquivalent(MapCurrentLocationKeyboardShortcut.key), modifiers: [.command, .shift])
    }

    private var symbolColor: Color {
        colorScheme == .dark ? .white : .black
    }
}

private enum MapCurrentLocationMetrics {
    static let buttonSize: CGFloat = 44
}

private enum MapCurrentLocationSymbols {
    static let currentLocation = "location.fill"
}

private enum MapCurrentLocationAccessibility {
    static let button = "map.currentLocation"
}

private enum MapCurrentLocationKeyboardShortcut {
    static let key: Character = "l"
}

#Preview {
    MapCurrentLocationButton(isLocating: false) {}
        .padding()
        .preferredColorScheme(.light)
}

#Preview {
    MapCurrentLocationButton(isLocating: false) {}
        .padding()
        .preferredColorScheme(.dark)
}

#Preview {
    MapCurrentLocationButton(isLocating: true) {}
        .padding()
}
