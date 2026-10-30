//
//  LocationCollectionPicker.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import SwiftUI

struct LocationCollectionPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var model: LocationCaptureModel
    @State private var editingOwnerID = UUID()
    @State private var query = String()
    @State private var newCollection: CollectionEditorViewModel?
    @State private var newCollectionID: UUID?

    init(model: LocationCaptureModel) { _model = State(initialValue: model) }

    var body: some View {
        NavigationStack {
            List {
                if model.collectionLoadFailed {
                    Text(LocationKeys.collectionLoadFailed)
                    DSButton(CommonKeys.retry, action: model.retryCollectionObservation)
                }
                ForEach(matchingCollections) { summary in
                    DSButton {
                        guard !model.isSaving else { return }
                        model.destinationCollectionID = summary.id
                        model.endEditing(ownerID: editingOwnerID)
                        dismiss()
                    } label: {
                        HStack {
                            Image.appSystemIcon(.folder)
                            VStack(alignment: .leading) {
                                if summary.collection.isDefault { Text(CollectionKeys.defaultCollectionName) }
                                else { Text(summary.collection.name) }
                                if !summary.collection.isDefault {
                                    Text(summary.collection.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(CollectionKeys.locationCount(Int64(summary.locationCount), locale: locale))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if summary.id == model.destinationCollectionID {
                                Image.appSystemIcon(.checkmark)
                                    .accessibilityLabel(Text(LocationKeys.selectedCollection))
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: Text(CollectionKeys.selectCollection))
            .navigationTitle(Text(LocationKeys.chooseCollection))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DSButton(CommonKeys.cancel) { model.endEditing(ownerID: editingOwnerID); dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    DSButton(LocationKeys.newCollection) {
                        let id = UUID()
                        newCollectionID = id
                        newCollection = CollectionEditorViewModel(
                            useCases: CollectionUseCases(repository: model.collectionRepository),
                            target: .create(id: id, createdAt: .now)
                        )
                    }
                    .disabled(model.isSaving)
                }
            }
        }
        .sheet(isPresented: Binding(get: { newCollection != nil }, set: { if !$0 { newCollection = nil } }), onDismiss: selectCreatedCollection) {
            if let newCollection { NavigationStack { CollectionEditorView(viewModel: newCollection) } }
        }
        .onAppear { model.beginEditing(ownerID: editingOwnerID) }
        .onChange(of: model.collections) { _, _ in
            if newCollection == nil { selectCreatedCollection() }
        }
    }
    private var matchingCollections: [CollectionSummary] {
        model.collections.filter { summary in
            let name = summary.collection.isDefault
                ? LocalizationManager.localizedString(CollectionKeys.defaultCollectionName, locale: locale)
                : summary.collection.name
            return query.isEmpty || name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
        }
    }

    private func selectCreatedCollection() {
        guard let id = newCollectionID, model.collections.contains(where: { $0.id == id }) else { return }
        model.destinationCollectionID = id
        newCollectionID = nil
        model.endEditing(ownerID: editingOwnerID)
        dismiss()
    }
}

#Preview {
    LocationCollectionPicker(model: LocationEditorPreview.model())
        .environment(DSToastManager())
}
