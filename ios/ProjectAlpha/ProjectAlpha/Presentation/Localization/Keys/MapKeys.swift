//
//  MapKeys.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 25/9/26.
//

import Foundation

enum MapKeys: String, CaseIterable, LocalizedKey {
    case title = "Map"
    case scaffoldMessage = "Map feature content will appear here."
    case currentLocation = "Get Current Location"
    case locating = "Getting Current Location"
    case locationPermissionTitle = "Location Access Needed"
    case locationPermissionMessage = "Allow location access in Settings to find your current location."
    case locationServicesDisabled = "Location Services are turned off. Turn them on in Settings and try again."
    case locationRestricted = "Location access is restricted on this device."
    case locationTimedOut = "Finding your location took too long. Please try again."
    case locationUnavailable = "Your current location is unavailable. Please try again."
    case locationSettingsUnavailable = "Settings could not be opened. Please open Settings to change location access."
}
