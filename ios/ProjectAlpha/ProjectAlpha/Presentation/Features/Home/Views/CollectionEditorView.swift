//
//  CollectionEditorView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 25/9/26.
//

import SwiftUI

struct CollectionEditorView: View {
    private enum FocusedElement: Hashable {
        case name
        case clearName
    }

    @Environment(DSToastManager.self) private var toastManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var viewModel: CollectionEditorViewModel
    @State private var showDiscardConfirmation = false
    @State private var showReloadConfirmation = false
    @State private var showConflict = false
    @State private var showSaveFailure = false
    @FocusState private var focusedElement: FocusedElement?

    init(viewModel: CollectionEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            nameSection
        }
        .navigationTitle(Text(verbatim: LocalizationManager.localizedString(
            viewModel.isCreating ? CollectionKeys.addCollection : CollectionKeys.updateCollection,
            locale: locale
        )))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                DSButton(CommonKeys.cancel) { cancel() }
                    .disabled(viewModel.isSaving)
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                DSButton(CommonKeys.save) {
                    Task { await save() }
                }
                .disabled(viewModel.isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .interactiveDismissDisabled(viewModel.isDirty || viewModel.isSaving)
        .confirmationDialog(
            Text(CollectionKeys.discardChangesTitle),
            isPresented: $showDiscardConfirmation
        ) {
            DSButton(role: .destructive) {
                discardAndDismiss()
            } label: {
                Text(CollectionKeys.discardChanges)
            }
            DSButton(role: .cancel) {} label: { Text(CollectionKeys.keepEditing) }
        } message: {
            Text(CollectionKeys.discardChangesMessage)
        }
        .alert(Text(CollectionKeys.conflictTitle), isPresented: $showConflict) {
            DSButton(CollectionKeys.reload) { showReloadConfirmation = true }
            DSButton(CollectionKeys.reapply) {
                Task {
                    if await viewModel.reapply() { finishSave() }
                    else { presentSaveResult() }
                }
            }
            DSButton(role: .cancel) {} label: { Text(CommonKeys.cancel) }
        } message: {
            if let latest = viewModel.latestConflict {
                Text(verbatim: CollectionKeys.conflictComparisonMessage(
                    draftName: viewModel.name,
                    latestName: latest.name,
                    locale: locale
                ))
            } else {
                Text(CollectionKeys.conflictMessage)
            }
        }
        .confirmationDialog(
            Text(CollectionKeys.discardChangesTitle),
            isPresented: $showReloadConfirmation
        ) {
            DSButton(role: .destructive) { viewModel.reloadFromConflict() } label: {
                Text(CollectionKeys.reload)
            }
            DSButton(role: .cancel) {} label: { Text(CollectionKeys.keepEditing) }
        } message: {
            Text(CollectionKeys.discardChangesMessage)
        }
        .alert(Text(saveFailureTitle), isPresented: $showSaveFailure) {
            if viewModel.saveError == .failed {
                DSButton(CollectionKeys.retry) { Task { await save() } }
            }
            DSButton(role: .cancel) {} label: { Text(CommonKeys.cancel) }
        }
    }

    private var nameSection: some View {
        Section {
            TextField(
                LocalizedStringKey(CollectionKeys.collectionNamePlaceholder.rawValue),
                text: $viewModel.name
            )
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($focusedElement, equals: .name)
            .disabled(viewModel.isSaving)
            .padding(.trailing, focusedElement != nil && !viewModel.name.isEmpty ? 44 : 0)
            .overlay(alignment: .trailing) {
                if focusedElement != nil && !viewModel.name.isEmpty {
                    DSButton {
                        focusedElement = .name
                        viewModel.name.removeAll()
                    } label: {
                        Image.appSystemIcon(.clearText)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($focusedElement, equals: .clearName)
                    .accessibilityLabel(Text(CollectionKeys.clearCollectionName))
                    .disabled(viewModel.isSaving)
                }
            }
        } header: {
            Text(CollectionKeys.collectionName)
        } footer: {
            if let error = viewModel.saveError,
               error == .nameRequired || error == .nameTooLong {
                Text(verbatim: validationMessage(error))
                    .foregroundStyle(.red)
            }
        }
    }

    private var saveFailureTitle: CollectionKeys {
        switch viewModel.saveError {
        case .missing: .collectionUnavailable
        default: .saveFailed
        }
    }

    private func validationMessage(_ error: CollectionEditorViewModel.SaveError) -> String {
        switch error {
        case .nameRequired:
            LocalizationManager.localizedString(CollectionKeys.nameRequired, locale: locale)
        case .nameTooLong:
            CollectionKeys.nameTooLong(
                maximum: Int64(CollectionNamePolicy.maximumGraphemeClusters),
                locale: locale
            )
        default:
            LocalizationManager.localizedString(CollectionKeys.saveFailed, locale: locale)
        }
    }

    private func cancel() {
        guard !viewModel.isSaving else { return }
        if viewModel.isDirty { showDiscardConfirmation = true }
        else { discardAndDismiss() }
    }

    private func discardAndDismiss() {
        guard !viewModel.isSaving else { return }
        dismiss()
    }

    private func save() async {
        if await viewModel.save() { finishSave() }
        else { presentSaveResult() }
    }

    private func finishSave() {
        toastManager.show(CollectionKeys.saveSucceeded)
        dismiss()
    }

    private func presentSaveResult() {
        if viewModel.latestConflict != nil { showConflict = true }
        else if viewModel.saveError == .failed || viewModel.saveError == .missing {
            showSaveFailure = true
        }
    }
}

#Preview {
    let repository = PreviewCollectionRepository()
    NavigationStack {
        CollectionEditorView(viewModel: CollectionEditorViewModel(
            useCases: CollectionUseCases(repository: repository),
            target: .edit(.mock)
        ))
        .environment(DSToastManager())
    }
}
