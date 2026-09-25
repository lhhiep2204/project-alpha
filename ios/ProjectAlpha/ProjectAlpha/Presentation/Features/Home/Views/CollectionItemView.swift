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

    var body: some View {
        HStack(spacing: DSSpacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.xxLarge)
                    .fill(.gray.opacity(0.15))
                    .frame(width: DSSize.huge, height: DSSize.huge)

                Image.appSystemIcon(.folder)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                Text(collection.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(collection.createdAt.toString(style: .dayMonthYear, locale: locale))
                    .font(.caption)
            }

            Spacer()

            Text(verbatim: count.formatted(.number.locale(locale)))
                .font(.caption)
                .lineLimit(1)
        }
    }
}

#if DEBUG
#Preview {
    CollectionItemView(collection: .mock, count: 3)
        .padding()
}
#endif
