import SwiftUI

struct CollectionEditorView: View {
    private enum FocusedElement: Hashable {
        case name
        case clearName
    }

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
        .navigationTitle(Text(viewModel.isCreating ? CollectionKeys.addCollection : CollectionKeys.updateCollection))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(CommonKeys.cancel) { cancel() }
                    .disabled(viewModel.isSaving)
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(CommonKeys.save) {
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
            Button(role: .destructive) {
                discardAndDismiss()
            } label: {
                Text(CollectionKeys.discardChanges)
            }
            Button(role: .cancel) {} label: { Text(CollectionKeys.keepEditing) }
        } message: {
            Text(CollectionKeys.discardChangesMessage)
        }
        .alert(Text(CollectionKeys.conflictTitle), isPresented: $showConflict) {
            Button(CollectionKeys.reload) { showReloadConfirmation = true }
            Button(CollectionKeys.reapply) {
                Task {
                    if await viewModel.reapply() { dismiss() }
                    else { presentSaveResult() }
                }
            }
            Button(role: .cancel) {} label: { Text(CommonKeys.cancel) }
        } message: {
            Text(CollectionKeys.conflictMessage)
        }
        .confirmationDialog(
            Text(CollectionKeys.discardChangesTitle),
            isPresented: $showReloadConfirmation
        ) {
            Button(role: .destructive) { viewModel.reloadFromConflict() } label: {
                Text(CollectionKeys.reload)
            }
            Button(role: .cancel) {} label: { Text(CollectionKeys.keepEditing) }
        } message: {
            Text(CollectionKeys.discardChangesMessage)
        }
        .alert(Text(saveFailureTitle), isPresented: $showSaveFailure) {
            if viewModel.saveError == .failed {
                Button(CollectionKeys.retry) { Task { await save() } }
            }
            Button(role: .cancel) {} label: { Text(CommonKeys.cancel) }
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
            .padding(.trailing, focusedElement != nil && !viewModel.name.isEmpty ? 44 : 0)
            .overlay(alignment: .trailing) {
                if focusedElement != nil && !viewModel.name.isEmpty {
                    Button {
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
        if await viewModel.save() { dismiss() }
        else { presentSaveResult() }
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
    }
}
