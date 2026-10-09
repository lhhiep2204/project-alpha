//
//  CollectionItemView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 19/9/26.
//

import SwiftUI

struct CollectionItemView: View {
    @Environment(\.locale) private var locale
    let collection: Collection
    let count: Int
    let creationDateText: String

    var body: some View {
        HStack(spacing: DSSpacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.xxLarge)
                    .fill(.gray.opacity(0.15))
                    .frame(width: DSSpacing.huge + DSSpacing.xSmall, height: DSSpacing.huge + DSSpacing.xSmall)

                Image.appSystemIcon(.folder)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                Text(verbatim: displayName)
                    .font(.headline)
                    .lineLimit(1)
                if !collection.isDefault {
                    Text(verbatim: creationDateText)
                        .font(.caption)
                }
            }

            Spacer()

            Text(verbatim: count.formatted(.number.locale(locale)))
                .font(.caption)
                .lineLimit(1)
        }
        .frame(minHeight: DSSpacing.huge + DSSpacing.xSmall)
    }

    private var displayName: String {
        collection.isDefault
            ? LocalizationManager.localizedString(CollectionKeys.defaultCollectionName, locale: locale)
            : collection.name
    }
}

#Preview {
    CollectionItemView(
        collection: .mock,
        count: 3,
        creationDateText: Collection.mock.createdAt.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .omitted,
                locale: Locale(identifier: LanguageCode.english)
            )
        )
    )
    .padding()
    .environment(\.locale, Locale(identifier: LanguageCode.english))
}

#Preview {
    CollectionItemView(
        collection: Collection(
            id: CollectionItemPreviewFixture.defaultCollectionID,
            name: CollectionItemPreviewFixture.storedDefaultCollectionName,
            isDefault: true,
            createdAt: CollectionItemPreviewFixture.createdAt,
            updatedAt: CollectionItemPreviewFixture.createdAt,
            revision: CollectionItemPreviewFixture.revision
        ),
        count: CollectionItemPreviewFixture.defaultCollectionCount,
        creationDateText: CollectionItemPreviewFixture.ignoredCreationDateText
    )
    .padding()
    .environment(\.locale, Locale(identifier: LanguageCode.english))
}

private enum CollectionItemPreviewFixture {
    static let defaultCollectionID = UUID(uuidString: "A3B1A9C4-1028-4E6A-9E1F-6D7C2B584A10")!
    static let storedDefaultCollectionName = "Stored default name"
    static let createdAt = Date(timeIntervalSince1970: 0)
    static let revision: Int64 = 1
    static let defaultCollectionCount = 4
    static let ignoredCreationDateText = "Preview date hidden for the default collection"
}
