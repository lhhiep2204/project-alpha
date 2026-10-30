//
//  MapSavedPin.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import SwiftUI

struct MapSavedPinRecord: Identifiable, Equatable {
    let id: UUID
    let title: String
    let collectionName: String?
    let createdAt: Date
    var collectionIsDefault = false
    var collectionLocationCount = 0
}

struct MapSavedAnnotationGroup: Identifiable, Equatable {
    let id: UUID
    let coordinate: Coordinate
    let records: [MapSavedPinRecord]
}

/// A native menu keeps coincident independent records reachable by touch and assistive input.
struct MapSavedPin: View {
    // The glyph sits at the bottom of the full interaction frame. Anchor its
    // center to the coordinate so the native title has the minimap's spacing.
    static let annotationAnchor = UnitPoint(
        x: 0.5,
        y: 1 - MapSavedPinConstants.symbolSize / (2 * MapSavedPinConstants.minimumTarget)
    )

    @Environment(\.locale) private var locale
    let group: MapSavedAnnotationGroup
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    private var isSelected: Bool { group.records.contains { $0.id == selectedID } }

    var body: some View {
        Group {
            if group.records.count == 1, let record = group.records.first {
                DSButton { onSelect(record.id) } label: { marker }
                    .accessibilityLabel(Text(verbatim: record.title))
            } else {
                Menu {
                    ForEach(group.records) { record in
                        DSButton { onSelect(record.id) } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: record.title)
                                Text(verbatim: collectionName(for: record))
                                Text(verbatim: CollectionKeys.locationCount(Int64(record.collectionLocationCount), locale: locale))
                                Text(record.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                            }
                        }
                    }
                } label: { marker }
                    .accessibilityLabel(Text(LocationKeys.overlappingPlaces))
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(verbatim: group.records.map { record in
            [record.title, collectionName(for: record),
             CollectionKeys.locationCount(Int64(record.collectionLocationCount), locale: locale),
             record.createdAt.formatted(.dateTime.year().month().day().hour().minute().second().locale(locale))]
                .joined(separator: MapSavedPinConstants.separator)
        }.joined(separator: MapSavedPinConstants.separator)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func collectionName(for record: MapSavedPinRecord) -> String {
        record.collectionIsDefault
            ? LocalizationManager.localizedString(CollectionKeys.defaultCollectionName, locale: locale)
            : record.collectionName ?? String()
    }

    private var marker: some View {
        Image.appIcon(.marker)
            .resizable()
            .scaledToFit()
            .frame(width: MapSavedPinConstants.symbolSize, height: MapSavedPinConstants.symbolSize)
            .foregroundStyle(.primary)
            .frame(minWidth: MapSavedPinConstants.minimumTarget, minHeight: MapSavedPinConstants.minimumTarget,
                   alignment: .bottom)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if group.records.count > 1 {
                    Text(group.records.count, format: .number)
                        .font(.caption2.bold())
                        .padding(4)
                        .background(.background, in: Circle())
                }
            }
    }

}

private enum MapSavedPinConstants {
    static let symbolSize: CGFloat = 24
    static let separator = ", "
    static let minimumTarget: CGFloat = 44
    static let previewName = "Saved Place"
    static let previewCollectionName = "My Places"
    static let previewID = UUID(uuidString: "31ECF4D1-EC66-470E-A8F5-599DDA13CE87")!
}

#Preview {
    MapSavedPin(group: MapSavedAnnotationGroup(
        id: MapSavedPinConstants.previewID,
        coordinate: MapQuickPlacePreviewFixtures.searchPlace.coordinate,
        records: [MapSavedPinRecord(id: MapSavedPinConstants.previewID, title: MapSavedPinConstants.previewName,
                                   collectionName: MapSavedPinConstants.previewCollectionName,
                                   createdAt: Date(timeIntervalSince1970: 0))]
    ), selectedID: MapSavedPinConstants.previewID, onSelect: { _ in })
}
