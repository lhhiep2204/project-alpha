//
//  MapPlaceSearchView.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 9/10/26.
//

import SwiftUI

struct MapPlaceSearchView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let model: MapPlaceSearchModel
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                switch model.phase {
                case .idle:
                    ContentUnavailableView {
                        Label { Text(MapKeys.searchPlacesTitle) } icon: { Image.appSystemIcon(.search) }
                    } description: {
                        Text(MapKeys.searchPlacesHint)
                    }
                case .debouncing, .loading:
                    HStack {
                        ProgressView()
                        Text(MapKeys.searchingPlaces)
                    }
                case .empty:
                    ContentUnavailableView {
                        Label { Text(MapKeys.noPlacesFound) } icon: { Image.appSystemIcon(.search) }
                    } description: {
                        Text(MapKeys.noPlacesFoundMessage)
                    }
                case let .failed(error):
                    MapSearchFailureView(message: error.searchMessage, retry: model.retry)
                case .results:
                    if model.resolutionError != nil {
                        MapSearchFailureView(message: .placeResolutionFailed, retry: model.retry)
                    }
                    ForEach(model.suggestions) { suggestion in
                        Button { model.select(suggestion) } label: {
                            MapSearchResultRow(
                                suggestion: suggestion,
                                isResolving: suggestion.id == model.resolvingSuggestionID
                            )
                        }
                        .disabled(model.resolvingSuggestionID != nil)
                        .accessibilityIdentifier(MapSearchAccessibility.result)
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(MapSearchAccessibility.screen)
            .navigationTitle(Text(MapKeys.searchPlacesTitle))
            .navigationBarTitleDisplayMode(.inline)
            // An inset native field keeps the app's title/Close visible while editing.
            // Searchable replaces this chrome with a system Cancel action when focused.
            .safeAreaInset(edge: .top, spacing: 0) {
                MapSearchQueryField(
                    query: Binding(get: { model.query }, set: model.updateQuery),
                    focus: $searchFocused,
                    reduceTransparency: reduceTransparency
                )
                .padding(.horizontal)
                .padding(.vertical, MapSearchLayout.headerPadding)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) { Text(CommonKeys.close) }
                        .accessibilityIdentifier(MapSearchAccessibility.close)
                }
            }
            .onAppear { searchFocused = true }
        }
    }

    private func close() {
        onClose()
    }
}

private struct MapSearchQueryField: View {
    @Binding var query: String
    let focus: FocusState<Bool>.Binding
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: MapSearchLayout.fieldSpacing) {
            Image.appSystemIcon(.search)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(text: $query, prompt: Text(MapKeys.searchPlacesPrompt)) {
                Text(MapKeys.searchPlacesPrompt)
            }
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused(focus)
            .submitLabel(.done)
            .onSubmit { focus.wrappedValue = false }
            .frame(minHeight: MapSearchLayout.minimumTarget)
            .accessibilityIdentifier(MapSearchAccessibility.field)

            if !query.isEmpty {
                Button(action: clearQuery) {
                    Image.appSystemIcon(.clearText)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: MapSearchLayout.minimumTarget, minHeight: MapSearchLayout.minimumTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(MapKeys.clearSearchQuery))
                .accessibilityIdentifier(MapSearchAccessibility.clear)
            }
        }
        .padding(.leading, MapSearchLayout.fieldPadding)
        .padding(.trailing, query.isEmpty ? MapSearchLayout.fieldPadding : 0)
        .background(
            reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
            in: Capsule()
        )
        .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: Capsule())
    }

    private func clearQuery() {
        query = MapSearchFieldConstants.emptyQuery
    }
}

private struct MapSearchResultRow: View {
    let suggestion: PlaceSuggestion
    let isResolving: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: MapSearchLayout.rowSpacing) {
                Text(suggestion.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle = suggestion.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(MapKeys.addressUnavailable)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isResolving { ProgressView() }
        }
        .padding(.vertical, MapSearchLayout.rowPadding)
        .frame(minHeight: MapSearchLayout.minimumTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct MapSearchFailureView: View {
    let message: MapKeys
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MapSearchLayout.errorSpacing) {
            Text(message)
                .foregroundStyle(.secondary)
            Button(action: retry) { Text(CommonKeys.retry) }
                .accessibilityIdentifier(MapSearchAccessibility.retry)
        }
        .padding(.vertical, MapSearchLayout.rowPadding)
    }
}

private extension PlaceServiceError {
    var searchMessage: MapKeys {
        switch self {
        case .networkUnavailable: .placeSearchNetworkUnavailable
        case .rateLimited: .placeSearchRateLimited
        default: .placeSearchUnavailable
        }
    }
}

private enum MapSearchAccessibility {
    static let screen = "map.placeSearch"
    static let close = "map.placeSearch.close"
    static let retry = "map.placeSearch.retry"
    static let result = "map.placeSearch.result"
    static let field = "map.placeSearch.field"
    static let clear = "map.placeSearch.clear"
}

private enum MapSearchLayout {
    static let rowSpacing: CGFloat = 4
    static let rowPadding: CGFloat = 6
    static let errorSpacing: CGFloat = 8
    static let minimumTarget: CGFloat = 44
    static let headerPadding: CGFloat = 8
    static let fieldSpacing: CGFloat = 8
    static let fieldPadding: CGFloat = 12
}

private enum MapSearchFieldConstants {
    static let emptyQuery = ""
}

#Preview {
    MapPlaceSearchView(model: MapPlaceSearchModel(service: nil), onClose: {})
}

#Preview {
    @Previewable @FocusState var focused: Bool
    MapSearchQueryField(query: .constant(MapSearchPreviewFixtures.suggestion.title), focus: $focused, reduceTransparency: false)
        .padding()
}

#Preview {
    @Previewable @FocusState var focused: Bool
    MapSearchQueryField(query: .constant(MapSearchPreviewFixtures.suggestion.title), focus: $focused, reduceTransparency: true)
        .padding()
}

#Preview {
    MapSearchResultRow(suggestion: MapSearchPreviewFixtures.suggestion, isResolving: false)
        .padding()
}

#Preview {
    MapSearchFailureView(message: .placeSearchNetworkUnavailable, retry: {})
        .padding()
}
