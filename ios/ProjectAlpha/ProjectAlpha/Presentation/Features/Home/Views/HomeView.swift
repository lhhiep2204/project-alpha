//
//  HomeView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import SwiftUI

struct HomeView: View {
    @Environment(SceneCoordinator.self) private var coordinator
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: HomeViewModel
    @State private var editorTarget: CollectionEditorTarget?
    @State private var deleteTarget: CollectionSummary?
    @State private var showDeleteConfirmation = false
    @State private var showDeleteError = false
    @State private var showChangedCollection = false
    @State private var rowDateCache = CollectionRowDateCache()
    @Binding private var selection: HomeRoute?

    init(viewModel: HomeViewModel, selection: Binding<HomeRoute?>) {
        _viewModel = State(initialValue: viewModel)
        _selection = selection
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading where viewModel.collections.isEmpty:
                ProgressView()
            case .failed:
                ContentUnavailableView {
                    Label {
                        Text(CollectionKeys.storageUnavailable)
                    } icon: {
                        Image.appSystemIcon(.folder)
                    }
                } actions: {
                    Button(CollectionKeys.retry) { viewModel.retry() }
                }
            default:
                collectionList
            }
        }
        .navigationTitle(Text(CollectionKeys.title))
        .searchable(text: $viewModel.searchText, prompt: Text(CommonKeys.search))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = .create(id: UUID(), createdAt: .now)
                } label: {
                    Label {
                        Text(CollectionKeys.addCollection)
                    } icon: {
                        Image.appSystemIcon(.add)
                    }
                }
                .accessibilityLabel(Text(CollectionKeys.addCollection))
            }
        }
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                CollectionEditorView(
                    viewModel: CollectionEditorViewModel(
                        useCases: viewModel.useCases,
                        target: target
                    )
                )
            }
        }
        .alert(Text(CollectionKeys.deleteFailed), isPresented: $showDeleteError) {
            Button(CollectionKeys.retry) {
                if let deleteTarget { Task { await attemptDelete(deleteTarget) } }
            }
            Button(role: .cancel) {} label: { Text(CommonKeys.cancel) }
        }
        .alert(Text(CollectionKeys.conflictTitle), isPresented: $showChangedCollection) {
            Button(CollectionKeys.retry) {
                if let latest = viewModel.changedCollection {
                    deleteTarget = latest
                    viewModel.clearChangedCollection()
                    showDeleteConfirmation = true
                }
            }
            Button(role: .cancel) {
                viewModel.clearChangedCollection()
            } label: { Text(CommonKeys.cancel) }
        } message: {
            Text(CollectionKeys.collectionChanged)
        }
        .task(id: viewModel.observationID) {
            viewModel.setLocalizedDefaultCollectionName(
                LocalizationManager.localizedString(CollectionKeys.defaultCollectionName, locale: locale)
            )
            await viewModel.observe()
        }
        .onChange(of: locale) { _, newLocale in
            viewModel.setLocalizedDefaultCollectionName(
                LocalizationManager.localizedString(CollectionKeys.defaultCollectionName, locale: newLocale)
            )
            if case let .collection(id) = selection {
                coordinator.setCollectionTitleHint(
                    id: id,
                    name: displayName(for: id, locale: newLocale)
                )
            }
        }
    }

    private var collectionList: some View {
        let rowDates = rowDateCache.texts(
            for: viewModel.collections,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
        let listFormatter = ListFormatter()
        listFormatter.locale = locale
        let folderLabel = LocalizationManager.localizedString(CollectionKeys.folderSymbol, locale: locale)
        let layoutDirection = LocalizationManager.layoutDirection(for: preferences.language)
        return List(selection: collectionSelection) {
            ForEach(viewModel.visibleCollections) { summary in
                let creationDateText = summary.collection.isDefault ? String() : (rowDates[summary.id] ?? String())
                NavigationLink(value: HomeRoute.collection(id: summary.id)) {
                    CollectionItemView(
                        collection: summary.collection,
                        count: summary.locationCount,
                        creationDateText: creationDateText
                    )
                }
                .accessibilityLabel(Text(verbatim: accessibilitySummary(
                    for: summary,
                    createdDate: creationDateText,
                    formatter: listFormatter,
                    folderLabel: folderLabel
                )))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !summary.collection.isDefault {
                        deleteButton(for: summary)
                        editButton(for: summary)
                    }
                }
                .contextMenu {
                    if !summary.collection.isDefault {
                        editButton(for: summary)
                        deleteButton(for: summary)
                    }
                }
                .confirmationDialog(
                    Text(verbatim: deleteTitle),
                    isPresented: deleteConfirmation(for: summary.id),
                    presenting: deleteTarget
                ) { target in
                    Button(role: .destructive) {
                        Task { await attemptDelete(target) }
                    } label: {
                        Text(CommonKeys.delete)
                    }
                } message: { target in
                    Text(verbatim: CollectionKeys.deleteCollectionMessage(
                        name: target.collection.name,
                        count: Int64(target.locationCount),
                        locale: locale
                    ))
                }
            }
            if viewModel.visibleCollections.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .environment(\.layoutDirection, layoutDirection)
        .id(layoutDirection)
        .animation(reduceMotion ? nil : .default, value: viewModel.visibleCollections.map(\.id))
        .refreshable { await viewModel.reload() }
    }

    private var collectionSelection: Binding<HomeRoute?> {
        Binding(
            get: { selection },
            set: { route in
                if case let .collection(previousID) = selection, route != selection {
                    coordinator.clearCollectionTitleHint(for: previousID)
                }
                if let route, case let .collection(id) = route,
                   let summary = viewModel.collections.first(where: { $0.id == id }) {
                    coordinator.setCollectionTitleHint(
                        id: id,
                        name: summary.collection.isDefault
                            ? LocalizationManager.localizedString(CollectionKeys.defaultCollectionName, locale: locale)
                            : summary.collection.name
                    )
                }
                selection = route
            }
        )
    }

    private func editButton(for summary: CollectionSummary) -> some View {
        Button {
            editorTarget = .edit(summary.collection)
        } label: {
            Label {
                Text(CommonKeys.edit)
            } icon: {
                Image.appSystemIcon(.edit)
            }
        }
    }

    private func deleteButton(for summary: CollectionSummary) -> some View {
        Button {
            deleteTarget = summary
            showDeleteConfirmation = true
        } label: {
            Label {
                Text(CommonKeys.delete)
            } icon: {
                Image.appSystemIcon(.delete)
            }
        }
        .tint(.red)
    }

    private func deleteConfirmation(for collectionID: UUID) -> Binding<Bool> {
        Binding(
            get: { showDeleteConfirmation && deleteTarget?.id == collectionID },
            set: { isPresented in
                guard deleteTarget?.id == collectionID else { return }
                showDeleteConfirmation = isPresented
            }
        )
    }

    private var deleteTitle: String {
        CollectionKeys.deleteCollectionTitle(
            name: deleteTarget?.collection.name ?? String(),
            locale: locale
        )
    }

    private func accessibilitySummary(
        for summary: CollectionSummary,
        createdDate: String,
        formatter: ListFormatter,
        folderLabel: String
    ) -> String {
        let name = summary.collection.isDefault
            ? LocalizationManager.localizedString(CollectionKeys.defaultCollectionName, locale: locale)
            : summary.collection.name
        if summary.collection.isDefault {
            let count = CollectionKeys.locationCount(Int64(summary.locationCount), locale: locale)
            return formatter.string(from: [name, count, folderLabel]) ?? name
        }
        let summaryText = CollectionKeys.collectionRowSummary(
            name: name,
            count: Int64(summary.locationCount),
            createdDate: createdDate,
            locale: locale
        )
        return formatter.string(from: [summaryText, folderLabel]) ?? summaryText
    }

    private func displayName(for id: UUID, locale: Locale) -> String {
        guard let summary = viewModel.collections.first(where: { $0.id == id }) else { return String() }
        return summary.collection.isDefault
            ? LocalizationManager.localizedString(CollectionKeys.defaultCollectionName, locale: locale)
            : summary.collection.name
    }
}

@MainActor
private final class CollectionRowDateCache {
    private var collections: [CollectionSummary] = []
    private var locale: Locale?
    private var calendar: Calendar?
    private var timeZone: TimeZone?
    private var rowDates: [UUID: String] = [:]

    func texts(
        for collections: [CollectionSummary],
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> [UUID: String] {
        if self.collections != collections || self.locale != locale ||
            self.calendar != calendar || self.timeZone != timeZone {
            self.collections = collections
            self.locale = locale
            self.calendar = calendar
            self.timeZone = timeZone
            rowDates = CollectionRowDatePresentation.texts(
                for: collections,
                locale: locale,
                calendar: calendar,
                timeZone: timeZone
            )
        }
        return rowDates
    }
}

/// One date string feeds both the visible row and its spoken label.
enum CollectionRowDatePresentation {
    private struct DisambiguationKey: Hashable {
        let name: String
        let locationCount: Int
        let date: String
    }

    static func texts(
        for collections: [CollectionSummary],
        locale: Locale,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [UUID: String] {
        let dayStyle = Date.FormatStyle(
            date: .abbreviated, time: .omitted,
            locale: locale, calendar: calendar, timeZone: timeZone
        )
        let timeStyle = Date.FormatStyle(
            date: .abbreviated, time: .complete,
            locale: locale, calendar: calendar, timeZone: timeZone
        )
        let keys = collections.map { summary in
            DisambiguationKey(
                name: summary.collection.name,
                locationCount: summary.locationCount,
                date: summary.collection.createdAt.formatted(dayStyle)
            )
        }
        let counts = Dictionary(
            zip(collections, keys)
                .filter { !$0.0.collection.isDefault }
                .map { ($0.1, 1) },
            uniquingKeysWith: +
        )
        return Dictionary(uniqueKeysWithValues: zip(collections, keys).map { summary, key in
            guard !summary.collection.isDefault else { return (summary.id, String()) }
            let date = counts[key, default: 0] > 1
            ? summary.collection.createdAt.formatted(timeStyle)
            : key.date
            return (summary.id, date)
        })
    }

    static func text(
        for summary: CollectionSummary,
        among collections: [CollectionSummary],
        locale: Locale,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard !summary.collection.isDefault else { return String() }
        return texts(for: collections, locale: locale, calendar: calendar, timeZone: timeZone)[summary.id] ??
        summary.collection.createdAt.formatted(
            Date.FormatStyle(
                date: .abbreviated, time: .omitted,
                locale: locale, calendar: calendar, timeZone: timeZone
            )
        )
    }
}

extension HomeView {
    private func attemptDelete(_ summary: CollectionSummary) async {
        await viewModel.delete(summary)
        if viewModel.deletionError {
            viewModel.clearDeletionError()
            showDeleteError = true
        } else if viewModel.changedCollection != nil {
            showChangedCollection = true
        }
    }
}

#Preview {
    let repository = PreviewCollectionRepository()
    HomeView(
        viewModel: .init(
            router: .init(root: .root),
            repository: repository,
            useCases: CollectionUseCases(repository: repository)
        ),
        selection: .constant(nil)
    )
    .environment(AppPreferences(store: PreviewPreferenceStore(language: .english)))
    .environment(\.locale, Locale(identifier: Language.english.code))
    .environment(\.calendar, Calendar(identifier: .gregorian))
    .environment(\.timeZone, .gmt)
    .environment(SceneCoordinator())
}
