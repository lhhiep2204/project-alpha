//
//  AppInfoHelper.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation

/// Provides information about the app from Info.plist.
enum AppInfoHelper {
    private enum Value {
        static let displayNameKey = "CFBundleDisplayName"
        static let bundleNameKey = "CFBundleName"
        static let marketingVersionKey = "CFBundleShortVersionString"
        static let buildNumberKey = "CFBundleVersion"
        static let unknownApp = "UnknownApp"
        static let unknownBundle = "UnknownBundle"
        static let unavailableVersion = "-"
        static let versionDescriptionFormat = "%@ (%@)"
    }

    /// The display name of the app.
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: Value.displayNameKey) as? String ??
        Bundle.main.object(forInfoDictionaryKey: Value.bundleNameKey) as? String ??
        Bundle.main.bundleIdentifier ??
        Value.unknownApp
    }

    /// The marketing version (e.g., "1.0").
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: Value.marketingVersionKey) as? String ?? Value.unavailableVersion
    }

    /// The internal build number (e.g., "42").
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: Value.buildNumberKey) as? String ?? Value.unavailableVersion
    }

    /// Combined version string (e.g., "1.0 (42)").
    static var appVersionDescription: String {
        String(format: Value.versionDescriptionFormat, appVersion, buildNumber)
    }

    /// The bundle identifier (e.g., "com.example.myapp").
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? Value.unknownBundle
    }
}
