//
//  CollectionKeys.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 19/9/26.
//

import Foundation

nonisolated enum CollectionKeys: String, CaseIterable, LocalizedKey {
    // MARK: - A
    case addCollection = "New Collection"

    // MARK: - C
    case clearCollectionName = "Clear collection name"
    case collection = "Collection"
    case collectionName = "Name"
    case collectionNamePlaceholder = "Collection name"
    case collectionRowSummary = "%1$@, %2$lld locations, created %3$@"
    case collectionUnavailable = "This collection is no longer available."
    case collectionChanged = "This collection changed before deletion. Review the latest details and try again."
    case conflictTitle = "Collection Changed"
    case conflictMessage = "This collection changed elsewhere. Reload the latest version or reapply your edits."

    // MARK: - D
    case defaultCollectionName = "My Places"
    case deleteCollectionTitle = "Delete \"%@\"?"
    case deleteCollectionMessage = "Delete \"%1$@\" and its %2$lld locations? This cannot be undone."
    case deleteFailed = "Couldn’t delete the collection. Try again."
    case discardChangesTitle = "Discard Changes?"
    case discardChangesMessage = "Your changes to this collection will be lost."

    // MARK: - E
    case emptyCollectionTitle = "No Locations"
    case emptyCollectionMessage = "Add a place to this collection."

    // MARK: - I
    case folderSymbol = "Folder"

    // MARK: - K
    case keepEditing = "Keep Editing"

    // MARK: - L
    case locationCount = "%lld locations"

    // MARK: - M
    case nameRequired = "Enter a collection name."
    case nameTooLong = "Collection name must be %lld characters or fewer."

    // MARK: - N
    case noSearchResults = "No Results"
    case noSearchResultsMessage = "No collections match \"%@\"."
    case noMatchingCollections = "No matching collections"

    // MARK: - R
    case reapply = "Reapply Edits"
    case reload = "Reload"
    case retry = "Retry"

    // MARK: - S
    case saveFailed = "Couldn’t save the collection. Try again."
    case storageUnavailable = "Your collections are unavailable. Retry to load them."

    // MARK: - T
    case title = "My Collections"

    // MARK: - U
    case updateCollection = "Edit Collection"

    // MARK: - V
    case discardChanges = "Discard Changes"

    // MARK: - S
    case selectCollection = "Select a Collection"
}

@MainActor
extension CollectionKeys {
    static func locationCount(_ count: Int64, locale: Locale) -> String {
        formatted(.locationCount, locale: locale, arguments: [count])
    }

    static func deleteCollectionTitle(name: String, locale: Locale) -> String {
        formatted(.deleteCollectionTitle, locale: locale, arguments: [name])
    }

    static func deleteCollectionMessage(name: String, count: Int64, locale: Locale) -> String {
        formatted(.deleteCollectionMessage, locale: locale, arguments: [name, count])
    }

    static func collectionRowSummary(name: String, count: Int64, createdDate: String, locale: Locale) -> String {
        formatted(.collectionRowSummary, locale: locale, arguments: [name, count, createdDate])
    }

    static func nameTooLong(maximum: Int64, locale: Locale) -> String {
        formatted(.nameTooLong, locale: locale, arguments: [maximum])
    }

    private static func formatted(_ key: CollectionKeys, locale: Locale, arguments: [CVarArg]) -> String {
        String(
            format: LocalizationManager.localizedString(key, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }
}
