//
//  DSIcon.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 19/9/26.
//

import SwiftUI

/// A design system enum that defines custom icons used in the app.
enum DSIcon: String {
    // MARK: - M
    case marker = "ic.marker"
}

/// A design system enum that defines system-provided SF Symbols used in the app.
enum DSSystemIcon: String {
    // MARK: - A
    case add = "plus"

    // MARK: - B
    case back = "chevron.backward"

    // MARK: - C
    case camera = "camera"
    case copy = "document.on.document"
    case clearText = "multiply.circle.fill"
    case close = "xmark"
    case checkmark = "checkmark"

    // MARK: - D
    case delete = "trash"

    // MARK: - E
    case edit = "pencil.line"
    case emptyList = "folder.badge.plus"
    case expandPicker = "chevron.down"

    // MARK: - F
    case favorite = "heart.fill"
    case favoriteEmpty = "heart"
    case folder = "folder"
    case forward = "chevron.forward"
    case home = "house"
    case homeFill = "house.fill"

    // MARK: - L
    case list = "list.bullet"
    case location = "location"

    // MARK: - M
    case map = "map"
    case mapFill = "map.fill"
    case more = "ellipsis"

    // MARK: - N
    case note = "note.text"

    // MARK: - P
    case photo = "photo"
    case passwordShown = "eye"
    case passwordHidden = "eye.slash"

    // MARK: - S
    case search = "magnifyingglass"
    case settings = "gear"
    case settingsTab = "gearshape"
    case share = "square.and.arrow.up"

    // MARK: - W
    case wifi = "wifi"
    case wifiSlash = "wifi.slash"
}

extension Image {
    /// Retrieves a custom app image icon.
    ///
    /// - Parameter icon: The `DSIcon` case representing the custom icon name.
    /// - Returns: An `Image` instance initialized with the specified custom icon name.
    static func appIcon(_ icon: DSIcon) -> Self {
        .init(icon.rawValue)
    }

    /// Retrieves a system SF Symbol icon.
    ///
    /// - Parameter icon: The `DSSystemIcon` case representing the SF Symbol name.
    /// - Returns: An `Image` instance initialized with the specified system icon name.
    static func appSystemIcon(_ icon: DSSystemIcon) -> Self {
        .init(systemName: icon.rawValue)
    }
}
