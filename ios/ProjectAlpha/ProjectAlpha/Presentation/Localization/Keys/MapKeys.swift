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
    case searchPlacesTitle = "Search Places"
    case searchPlacesPrompt = "Place name or address"
    case clearSearchQuery = "Clear Search"
    case searchPlacesHint = "Enter a place name or address to search Apple Maps."
    case searchingPlaces = "Searching Places"
    case noPlacesFound = "No Places Found"
    case noPlacesFoundMessage = "Try another place name or address."
    case placeSearchUnavailable = "Place search is unavailable. Please try again."
    case placeSearchNetworkUnavailable = "Check your internet connection and try searching again."
    case placeSearchRateLimited = "Too many search requests. Please wait a moment and try again."
    case placeResolutionFailed = "This place could not be opened. Please try again."
    case addressUnavailable = "Address unavailable"
    case myLocation = "My Location"
    case viewDetails = "View Details"
    case coordinates = "Coordinates"
    case horizontalAccuracy = "Horizontal Accuracy"
    case positionTimestamp = "Position Time"
    case name = "Name"
    case address = "Address"
}
