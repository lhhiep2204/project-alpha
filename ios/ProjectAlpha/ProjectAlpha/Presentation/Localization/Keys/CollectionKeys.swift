//
//  CollectionKeys.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 19/9/26.
//

import Foundation

enum CollectionKeys: String, CaseIterable, LocalizedKey {
    // MARK: - A
    case addCollection = "New Collection"

    // MARK: - C
    case collection = "Collection"
    case collectionName = "Name"

    // MARK: - N
    case noCollections = "No Collections"
    case noCollectionsMessage = "Add your first collection to organize your locations"
    case noSearchResults = "No Results"
    case noSearchResultsMessage = "No collections match \"%@\"."

    // MARK: - T
    case title = "My Collections"

    // MARK: - U
    case updateCollection = "Edit Collection"

    // MARK: - S
    case selectCollection = "Select a Collection"
}
