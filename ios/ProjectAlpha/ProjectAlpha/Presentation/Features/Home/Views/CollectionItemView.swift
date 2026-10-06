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
                Text(collection.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(verbatim: creationDateText)
                    .font(.caption)
            }

            Spacer()

            Text(verbatim: count.formatted(.number.locale(locale)))
                .font(.caption)
                .lineLimit(1)
        }
        .frame(minHeight: DSSpacing.huge + DSSpacing.xSmall)
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
