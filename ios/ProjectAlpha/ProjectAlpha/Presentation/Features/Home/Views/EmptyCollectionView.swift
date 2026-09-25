//
//  EmptyCollectionView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 19/9/26.
//

import SwiftUI

private enum EmptyCollectionPreview {
    static let logMessage = "Add collection tapped"
}

struct EmptyCollectionView: View {
    let onAddCollection: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(CollectionKeys.noCollections)
                    .font(.title3)
            } icon: {
                Image.appSystemIcon(.emptyList)
            }
        } description: {
            Text(CollectionKeys.noCollectionsMessage)
                .font(.body)
        } actions: {
            Button(CommonKeys.add) {
                onAddCollection()
            }
            .buttonStyle(.glass)
        }
    }
}

#Preview {
    EmptyCollectionView {
        Logger.info(EmptyCollectionPreview.logMessage)
    }
}
