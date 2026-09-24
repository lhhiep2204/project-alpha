//
//  AppInfoHelper.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation

/// Provides information about the app from Info.plist.
enum AppInfoHelper {
    /// The display name of the app.
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ??
        Bundle.main.bundleIdentifier ??
        "UnknownApp"
    }

    /// The marketing version (e.g., "1.0").
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    /// The internal build number (e.g., "42").
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    /// Combined version string (e.g., "1.0 (42)").
    static var appVersionDescription: String {
        "\(appVersion) (\(buildNumber))"
    }

    /// The bundle identifier (e.g., "com.example.myapp").
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "UnknownBundle"
    }
}
