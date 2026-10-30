//
//  MapReadOnlyDetailSheet.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 11/10/26.
//

import SwiftUI

/// Read inputs for the shared location form; no mutable editor is required to view a place.
struct LocationDetailsReadContext {
    let place: MapQuickPlace
    var savedLocation: SavedLocation? = nil
    var collection: Collection? = nil
    var mediaService: (any LocationMediaService)? = nil
    var route: MapRouteModel? = nil
    var distanceUnit: DistanceUnit = .kilometre
    var onOpenInMaps: () -> Void = {}
    var actions: LocationDetailActionModel? = nil
    var onFavorite: (SavedLocation) async -> Void = { _ in }
    var onDelete: () async -> Bool = { false }
}

struct LocationReadPhotos: View {
    @Environment(\.locale) private var locale
    let assets: [LocalAssetReference]
    let mediaService: (any LocationMediaService)?
    let onView: (LocalAssetReference) -> Void

    var body: some View {
        if !assets.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: LocationPhotoLayout.spacing) {
                        ForEach(assets, id: \.assetID) { asset in
                            LocationPhotoTile(
                                asset: asset, mediaService: mediaService,
                                photoLabel: String(format: LocalizationManager.localizedString(LocationKeys.photoNumber, locale: locale),
                                                   locale: locale, Int64((assets.firstIndex(of: asset) ?? 0) + 1)),
                                removalDisabled: true, onView: { onView(asset) }
                            )
                            .frame(width: LocationPhotoLayout.photoSide, height: LocationPhotoLayout.photoSide)
                        }
                    }
                    .padding(.vertical, LocationPhotoLayout.verticalInset)
                }
                .scrollIndicators(.hidden)
                .listRowSeparator(.hidden)
            } header: { Text(LocationKeys.photos) }
        }
    }
}


#Preview {
    LocationDetailsEditor(model: LocationEditorPreview.model(), mode: .read,
        readContext: LocationDetailsReadContext(place: MapQuickPlacePreviewFixtures.searchPlace),
        rendersLiveMap: false, onBeginUpdate: { LocationEditorPreview.model() })
        .environment(DSToastManager())
}

#Preview {
    LocationDetailsEditor(mode: .read,
        readContext: LocationDetailsReadContext(place: MapQuickPlacePreviewFixtures.searchPlace,
            savedLocation: LocationEditorPreview.savedLocation, collection: .mock),
        rendersLiveMap: false, onBeginUpdate: { LocationEditorPreview.editModel() })
        .environment(DSToastManager())
}

#Preview {
    Form {
        LocationReadPhotos(assets: LocationEditorPreview.photoAssets,
            mediaService: LocationEditorPreview.photoService(), onView: { _ in })
    }
}
