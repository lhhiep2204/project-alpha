//
//  DSMetrics.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 19/9/26.
//

import Foundation

/// Common spacing constants for layout and padding.
enum DSSpacing {
    /// xSmall: 4 - For fine details or tight layouts
    static let xSmall = 4.0
    /// small: 8 - Standard spacing between small UI elements
    static let small = 8.0
    /// medium: 12 - Spacing between grouped elements
    static let medium = 12.0
    /// large: 16 - Common container padding (Apple recommended)
    static let large = 16.0
    /// xLarge: 24 - For wide separation or section spacing
    static let xLarge = 24.0
    /// xxLarge: 32 - For extra spacious layouts
    static let xxLarge = 32.0
    /// huge: 40 - Hero sections or large vertical gaps
    static let huge = 40.0
}

/// Corner radius constants for rounded UI components.
enum DSRadius {
    /// small: 4 - Subtle rounding for controls
    static let small = 4.0
    /// medium: 8 - Standard for buttons and fields
    static let medium = 8.0
    /// large: 12 - Cards or accent panels
    static let large = 12.0
    /// xLarge: 16 - Extra large, prominent elements
    static let xLarge = 16.0
    /// xxLarge: 20 - Extra-extra large
    static let xxLarge = 20.0
    /// huge: 28 - Very large, pill-shaped buttons or containers
    static let huge = 28.0
}
