//
//  LocationDetailsEditor.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import MapKit
import PhotosUI
import Observation
import SwiftUI

enum LocationDetailsMode {
    case read
    case update
}

/// A detail sheet returns to reading after an in-place update; standalone editors close.
@Observable @MainActor
final class LocationDetailsPresentation {
    private(set) var model: LocationCaptureModel?
    private(set) var mode: LocationDetailsMode
    private(set) var isDiscarding = false
    var showDiscard = false
    private let returnsToRead: Bool
    private let editingOwnerID = UUID()

    init(model: LocationCaptureModel? = nil, mode: LocationDetailsMode, returnsToRead: Bool) {
        self.model = model
        self.mode = mode
        self.returnsToRead = returnsToRead
    }

    func beginEditing() {
        if mode == .update { model?.beginEditing(ownerID: editingOwnerID) }
    }

    func beginUpdate(_ updated: LocationCaptureModel) {
        guard !isDiscarding, mode == .read, !updated.isCancelled, updated.commit == nil else { return }
        model = updated
        mode = .update
        beginEditing()
    }

    /// True asks the sheet owner to dismiss; false retains this presentation.
    func requestClose() -> Bool {
        guard !isDiscarding, model?.isSaving != true else { return false }
        if mode == .update, returnsToRead || model?.isDirty == true {
            showDiscard = true
            return false
        }
        model?.endEditing(ownerID: editingOwnerID)
        return true
    }

    func discardUpdate() async -> Bool {
        guard !isDiscarding, mode == .update, model?.isSaving != true, model?.commit == nil else { return false }
        isDiscarding = true
        defer { isDiscarding = false }
        await model?.discardDetails()
        showDiscard = false
        if returnsToRead { mode = .read }
        return !returnsToRead
    }

    func completeSave(toastManager: DSToastManager? = nil, dismissedToastManager: DSToastManager? = nil) -> Bool {
        guard !isDiscarding, mode == .update, model?.commit != nil else { return false }
        model?.endEditing(ownerID: editingOwnerID)
        showDiscard = false
        if returnsToRead { mode = .read }
        (returnsToRead ? toastManager : dismissedToastManager)?.show(LocationKeys.saveSucceeded)
        return !returnsToRead
    }

    func savedLocation(fallback: SavedLocation?) -> SavedLocation? {
        guard let committed = model?.commit?.location else { return fallback }
        if let fallback, fallback.id == committed.id, fallback.revision > committed.revision { return fallback }
        return committed
    }
}

/// Child presentation state is retained by the editor, never by a recycled Form row.
@Observable @MainActor
final class LocationPhotoPresentation {
    var showCamera = false
    var showPhotoLibrary = false
    var selectedPhotos: [PhotosPickerItem] = []
    var capturedPhoto: LocationCameraPhoto?
}

/// One sheet and form own both reading and updating a location.
struct LocationDetailsEditor: View {
    @Environment(DSToastManager.self) private var parentToastManager
    @State private var toastManager = DSToastManager()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var presentation: LocationDetailsPresentation
    @State private var showPicker = false
    @State private var pendingSavedID: UUID?
    @State private var viewingPhoto: LocationPhotoSelection?
    @State private var photoPresentation: LocationPhotoPresentation
    private let readContext: LocationDetailsReadContext?
    private let rendersLiveMap: Bool
    private let onBeginUpdate: (() -> LocationCaptureModel?)?
    private let onOpenSaved: ((UUID) -> Void)?

    init(model: LocationCaptureModel? = nil, mode: LocationDetailsMode = .update,
         readContext: LocationDetailsReadContext? = nil, rendersLiveMap: Bool = true,
         onBeginUpdate: (() -> LocationCaptureModel?)? = nil,
         onOpenSaved: ((UUID) -> Void)? = nil,
         photoPresentation: LocationPhotoPresentation = LocationPhotoPresentation()) {
        _photoPresentation = State(initialValue: photoPresentation)
        _presentation = State(initialValue: LocationDetailsPresentation(
            model: model, mode: mode, returnsToRead: readContext != nil))
        self.readContext = readContext
        self.rendersLiveMap = rendersLiveMap
        self.onBeginUpdate = onBeginUpdate
        self.onOpenSaved = onOpenSaved
    }

    var body: some View {
        @Bindable var photoPresentation = photoPresentation
        @Bindable var presentation = presentation
        NavigationStack {
            Form {
                LocationDetailsCollectionSection(mode: mode, model: model,
                    collection: readCollection, isSaved: savedLocation != nil,
                    onChoose: { showPicker = true })
                if let coordinate {
                    LocationDetailsFields(name: name, address: address, coordinate: coordinate,
                        rendersLiveMap: rendersLiveMap,
                        showsDisplayName: mode == .update || !displayName.isEmpty,
                        showsNotes: mode == .update || !notes.isEmpty,
                        routeState: mode == .read && readContext?.place.isCurrentPosition == false
                            ? readContext?.route?.state ?? .noOrigin : .idle,
                        distanceUnit: readContext?.distanceUnit ?? .kilometre,
                        detailActions: detailActions) {
                        if mode == .update, let model {
                            @Bindable var model = model
                            TextField(LocalizedStringKey(LocationKeys.displayName.rawValue), text: $model.displayName)
                        } else { Text(displayName).textSelection(.enabled) }
                    } notes: {
                        if mode == .update, let model {
                            @Bindable var model = model
                            TextField(LocalizedStringKey(LocationKeys.notes.rawValue), text: $model.notes, axis: .vertical)
                                .lineLimit(4...12)
                        } else { Text(notes).textSelection(.enabled) }
                    }
                }
                if mode == .update, let model {
                    LocationPhotoControls(model: model, photoPresentation: photoPresentation, onViewPhoto: viewPhoto)
                    LocationSaveFeedback(model: model, onOpenSaved: openSaved,
                                         onChooseCollection: { showPicker = true })
                } else {
                    LocationReadPhotos(assets: assets, mediaService: photoService, onView: viewPhoto)
                    if let saved = savedLocation, let onOpenSaved {
                        Section { DSButton(LocationKeys.openSaved) { onOpenSaved(saved.id) } }
                    }
                }
            }
            .listSectionSpacing(mode == .read ? .custom(Metrics.readSectionSpacing) : .default)
            .disabled(model?.isSaving == true || presentation.isDiscarding)
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DSButton(mode == .read ? CommonKeys.close : CommonKeys.cancel, action: close)
                        .disabled(model?.isSaving == true || presentation.isDiscarding)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if mode == .update {
                        DSButton(CommonKeys.save) { Task { await model?.save() } }
                            .disabled(model?.canSave != true || presentation.isDiscarding)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        DSButton(savedLocation == nil ? CommonKeys.add : CommonKeys.edit, action: beginUpdate)
                            .disabled(onBeginUpdate == nil || readContext?.actions?.isPerformingAction == true)
                            .accessibilityIdentifier(savedLocation == nil
                                ? LocationDetailsAccessibility.add : LocationDetailsAccessibility.edit)
                    }
                }
            }
        }
        .modifier(LocationDetailMutationFeedback(actions: readContext?.actions, locationID: savedLocation?.id,
            onFavorite: favorite, onDelete: deleteLocation))
        .onAppear { presentation.beginEditing() }
        .interactiveDismissDisabled(mode == .update && (presentation.isDiscarding || model?.isDirty == true || model?.isSaving == true || model?.isImportingPhoto == true))
        .confirmationDialog(Text(LocationKeys.discardTitle), isPresented: $presentation.showDiscard) {
            DSButton(role: .destructive) { Task { await discard() } } label: { Text(LocationKeys.discard) }
            DSButton(role: .cancel) { pendingSavedID = nil } label: { Text(LocationKeys.keepEditing) }
        } message: { Text(LocationKeys.discardMessage) }
        .fullScreenCover(item: $viewingPhoto) { selection in
            LocationPhotoViewer(assets: assets, selectedID: selection.id, mediaService: photoService)
        }
        .sheet(isPresented: $showPicker) {
            if let model { LocationCollectionPicker(model: model) }
        }
        .photosPicker(isPresented: $photoPresentation.showPhotoLibrary, selection: $photoPresentation.selectedPhotos,
                      maxSelectionCount: max(1, model?.remainingPhotoCapacity ?? 0), matching: .images)
        .fullScreenCover(isPresented: $photoPresentation.showCamera) {
            LocationCameraCapture { photo in
                photoPresentation.capturedPhoto = photo
                photoPresentation.showCamera = false
            } onCancel: { photoPresentation.showCamera = false }
        }
        .task(id: photoPresentation.capturedPhoto?.id) {
            guard let model, let capturedPhoto = photoPresentation.capturedPhoto, let generation = model.beginPhotoSelection() else { return }
            defer {
                model.finishPhotoSelection(generation: generation)
                photoPresentation.capturedPhoto = nil
            }
            let data = await LocationCameraPhotoEncoder.encode(capturedPhoto.image,
                originalCaptureTime: capturedPhoto.originalCaptureTime,
                captureOffset: capturedPhoto.captureOffset, captureSubsecond: capturedPhoto.captureSubsecond)
            guard !Task.isCancelled, model.acceptsPhotoSelection(generation: generation) else { return }
            if let data { await model.importPhoto(data: data, selectionGeneration: generation) }
            else { model.reportPhotoImportFailure() }
        }
        .task(id: photoPresentation.selectedPhotos) {
            guard let model, !photoPresentation.selectedPhotos.isEmpty, let generation = model.beginPhotoSelection() else { return }
            defer { model.finishPhotoSelection(generation: generation) }
            let selection = photoPresentation.selectedPhotos
            for item in selection {
                guard !Task.isCancelled, model.acceptsPhotoSelection(generation: generation) else { return }
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        guard !Task.isCancelled, model.acceptsPhotoSelection(generation: generation) else { return }
                        await model.importPhoto(data: data, selectionGeneration: generation)
                    }
                    else { model.reportPhotoImportFailure() }
                } catch { model.reportPhotoImportFailure() }
            }
            photoPresentation.selectedPhotos.removeAll()
        }
        .task(id: model?.collectionObservationRequestID) { await model?.observeCollections() }
        .onChange(of: model?.commit) { _, value in
            if value != nil, presentation.completeSave(
                toastManager: toastManager, dismissedToastManager: parentToastManager) { dismiss() }
        }
        .dsToast(manager: toastManager)
        .environment(toastManager)
    }

    private var model: LocationCaptureModel? { presentation.model }
    private var mode: LocationDetailsMode { presentation.mode }
    private var savedLocation: SavedLocation? { presentation.savedLocation(fallback: readContext?.savedLocation) }
    private var readCollection: Collection? {
        guard let savedLocation else { return nil }
        if let collection = readContext?.collection, collection.id == savedLocation.collectionID { return collection }
        return model?.collections.first { $0.id == savedLocation.collectionID }?.collection
    }
    private var title: LocalizedStringKey {
        if mode == .read { return LocalizedStringKey(MapKeys.viewDetails.rawValue) }
        return LocalizedStringKey((model?.isEditingSavedLocation == true ? LocationKeys.editLocation : .addLocation).rawValue)
    }
    private var name: String? {
        mode == .read ? savedLocation?.name ?? readContext?.place.name : model?.candidate.name
    }
    private var address: String? {
        mode == .read ? savedLocation?.address ?? readContext?.place.address : model?.candidate.address
    }
    private var coordinate: Coordinate? {
        mode == .read ? savedLocation?.coordinate ?? readContext?.place.coordinate : model?.candidate.coordinate
    }
    private var displayName: String {
        if mode == .read { return savedLocation?.displayName ?? String() }
        return model?.displayName ?? String()
    }
    private var notes: String {
        if mode == .read { return savedLocation?.notes ?? String() }
        return model?.notes ?? String()
    }
    private var assets: [LocalAssetReference] {
        if mode == .read { return savedLocation?.assets ?? [] }
        return model?.assets ?? []
    }
    private var photoService: (any LocationMediaService)? { model?.photoService ?? readContext?.mediaService }

    private var detailActions: LocationDetailActionsView? {
        guard mode == .read, let context = readContext, let coordinate else { return nil }
        return LocationDetailActionsView(
            payload: LocationDetailPayload(name: displayName.isEmpty
                ? name ?? LocalizationManager.localizedString(MapKeys.myLocation, locale: locale) : displayName,
                address: address, coordinate: coordinate, notes: notes),
            isSaved: savedLocation != nil, isFavorite: savedLocation?.isFavorite == true,
            canUpdate: false, canMutate: context.actions?.canMutate == true,
            onUpdate: beginUpdate, onOpenInMaps: context.onOpenInMaps,
            onFavorite: favorite, onDelete: requestDelete,
            onCopied: { toastManager.show($0) })
    }

    private enum Metrics { static let readSectionSpacing: CGFloat = 16 }

    private func favorite() {
        guard let savedLocation, let context = readContext else { return }
        Task { await context.onFavorite(savedLocation) }
    }
    private func requestDelete() {
        guard let savedLocation else { return }
        readContext?.actions?.requestDelete(savedLocation)
    }
    private func deleteLocation() {
        guard let context = readContext else { return }
        // The map owner closes only the deleted selection; a newer detail stays intact.
        Task { _ = await context.onDelete() }
    }
    private func beginUpdate() {
        guard mode == .read, let updated = onBeginUpdate?() else { return }
        presentation.beginUpdate(updated)
    }
    private func close() {
        if presentation.requestClose() { dismiss() }
    }
    private func openSaved(_ id: UUID) {
        if model?.isDirty == true { pendingSavedID = id; presentation.showDiscard = true }
        else { onOpenSaved?(id) }
    }
    private func discard() async {
        if let id = pendingSavedID {
            pendingSavedID = nil
            await model?.cancel()
            onOpenSaved?(id)
        } else {
            if await presentation.discardUpdate() { dismiss() }
        }
    }
    private func viewPhoto(_ asset: LocalAssetReference) { viewingPhoto = LocationPhotoSelection(asset: asset) }
}

private enum LocationDetailsAccessibility {
    static let openInMaps = "map.detailOpenInMaps"
    static let add = "map.detailAdd"
    static let edit = "map.detailEdit"
}

private struct LocationDetailsCollectionSection: View {
    let mode: LocationDetailsMode
    let model: LocationCaptureModel?
    let collection: Collection?
    let isSaved: Bool
    let onChoose: () -> Void

    var body: some View {
        if mode == .update, let model {
            Section {
                DSButton(action: onChoose) {
                    LabeledContent {
                        HStack {
                            LocationDestinationLabel(model: model)
                            Image.appSystemIcon(.expandPicker).font(.caption)
                        }
                    } label: { Text(CollectionKeys.collection) }
                }
                .buttonStyle(.automatic)
            }
        } else if isSaved, let collection {
            Section {
                LabeledContent {
                    HStack {
                        Image.appSystemIcon(.folder)
                        if collection.isDefault { Text(CollectionKeys.defaultCollectionName) }
                        else { Text(collection.name) }
                    }
                } label: { Text(CollectionKeys.collection) }
            }
        }
    }
}

/// Map preview and immutable facts retain their identity when the mode changes.
struct LocationDetailsFields<DisplayName: View, Notes: View>: View {
    let name: String?
    let address: String?
    let coordinate: Coordinate
    var rendersLiveMap = true
    var showsDisplayName = true
    var showsNotes = true
    var routeState: MapRouteState = .idle
    var distanceUnit: DistanceUnit = .kilometre
    var detailActions: LocationDetailActionsView? = nil
    @ViewBuilder let displayName: DisplayName
    @ViewBuilder let notes: Notes

    var body: some View {
        Section {
            LocationEditorMapPreview(name: name, coordinate: coordinate, rendersLiveMap: rendersLiveMap)
                .id(coordinate)
                .listRowInsets(EdgeInsets())
        }
        switch routeState {
        case .idle, .noOrigin: EmptyView()
        default:
            Section {
                MapRouteSummaryView(state: routeState, distanceUnit: distanceUnit)
            }
        }
        if let detailActions {
            Section {
                detailActions
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        Section {
            if showsDisplayName {
                LabeledContent { displayName } label: { Text(LocationKeys.displayName) }
            }
            LabeledContent {
                if let name, !name.isEmpty { Text(name).textSelection(.enabled) }
                else { Text(MapKeys.myLocation) }
            } label: { Text(MapKeys.name) }
            if let address, !address.isEmpty {
                LabeledContent { Text(address).textSelection(.enabled) } label: { Text(MapKeys.address) }
            }
            LabeledContent {
                HStack {
                    Text(coordinate.latitude, format: .number.precision(.fractionLength(6)))
                    Text(coordinate.longitude, format: .number.precision(.fractionLength(6)))
                }
                .font(MapPlaceTypography.fact)
                .textSelection(.enabled)
                .environment(\.layoutDirection, .leftToRight)
            } label: { Text(MapKeys.coordinates) }
        }
        if showsNotes { Section { notes } header: { Text(LocationKeys.notes) } }
    }
}

private struct LocationEditorMapPreview: View {
    private enum Metric {
        static let markerSide: CGFloat = 24
    }

    let name: String?
    let coordinate: Coordinate
    let rendersLiveMap: Bool

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Group {
            if rendersLiveMap {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))), interactionModes: []) {
                    Annotation(coordinate: coordinate) {
                        marker
                    } label: {
                        markerTitle
                    }
                    .annotationTitles(.visible)
                }
                .mapControlVisibility(.hidden)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        VStack(spacing: 4) {
                            marker
                            markerTitle.font(.caption.weight(.semibold))
                        }
                    }
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityHidden(true)
    }

    private var marker: some View {
        Image.appIcon(.marker)
            .resizable()
            .scaledToFit()
            .frame(width: Metric.markerSide, height: Metric.markerSide)
            .foregroundStyle(.primary)
    }

    private var markerTitle: some View {
        Group {
            if let name { Text(name) }
            else { Text(MapKeys.myLocation) }
        }
    }
}

struct LocationDestinationLabel: View {
    let model: LocationCaptureModel
    var body: some View {
        HStack {
            Image.appSystemIcon(.folder)
            if model.destinationIsDefault { Text(CollectionKeys.defaultCollectionName) }
            else if let name = model.destinationName { Text(name) }
            else { Text(LocationKeys.chooseCollection) }
        }
    }
}

struct LocationSaveFeedback: View {
    let model: LocationCaptureModel
    var onOpenSaved: (UUID) -> Void = { _ in }
    var onChooseCollection: () -> Void = {}
    @State private var showReloadConfirmation = false

    var body: some View {
        Section {
            if let error = model.saveError {
                Text(message(error)).foregroundStyle(.red)
                switch error {
                case .blockingDuplicate(let id, _):
                    DSButton(LocationKeys.openSaved) { onOpenSaved(id) }
                    DSButton(LocationKeys.chooseCollection, action: onChooseCollection)
                case .possibleDuplicates(let ids, _):
                    ForEach(ids, id: \.self) { id in
                        DSButton { onOpenSaved(id) } label: {
                            VStack(alignment: .leading) {
                                Text(LocationKeys.openSaved)
                                if let match = model.duplicateMatches.first(where: { $0.id == id }) {
                                    Text(match.displayName ?? match.name)
                                    if let address = match.address { Text(address).font(.caption) }
                                }
                            }
                        }
                    }
                    DSButton(LocationKeys.saveAnyway) { Task { await model.acknowledgeWarningAndSave() } }
                    DSButton(CommonKeys.cancel) { model.clearError() }
                case .editConflict(let latest):
                    LabeledContent { Text(model.displayName.isEmpty ? model.candidate.name : model.displayName) }
                    label: { Text(LocationKeys.yourVersion) }
                    Text(model.notes)
                    if let name = model.destinationName { Text(name).foregroundStyle(.secondary) }
                    LabeledContent { Text(model.assets.count, format: .number) }
                    label: { Text(LocationKeys.photos) }
                    LabeledContent { Text(latest.displayName ?? latest.name) }
                    label: { Text(LocationKeys.latestVersion) }
                    if let notes = latest.notes { Text(notes) }
                    if let collection = model.collections.first(where: { $0.id == latest.collectionID })?.collection {
                        if collection.isDefault { Text(CollectionKeys.defaultCollectionName).foregroundStyle(.secondary) }
                        else { Text(collection.name).foregroundStyle(.secondary) }
                    }
                    LabeledContent { Text(latest.assets.count, format: .number) }
                    label: { Text(LocationKeys.photos) }
                    DSButton(CollectionKeys.reload) { showReloadConfirmation = true }
                    DSButton(CollectionKeys.reapply) { Task { await model.reapplyConflict() } }
                case .destinationMissing:
                    DSButton(LocationKeys.chooseCollection, action: onChooseCollection)
                case .storageFailure, .storageUnavailable:
                    DSButton(CommonKeys.retry) { Task { await model.save() } }
                default: EmptyView()
                }
            }
        }
        .disabled(model.isSaving)
        .alert(Text(LocationKeys.discardTitle), isPresented: $showReloadConfirmation) {
            DSButton(role: .destructive) { Task { await model.reloadConflict() } } label: { Text(CollectionKeys.reload) }
            DSButton(role: .cancel) {} label: { Text(CommonKeys.cancel) }
        } message: { Text(LocationKeys.discardMessage) }
    }

    private func message(_ error: LocationWriteError) -> LocationKeys {
        switch error {
        case .editConflict: .editConflict
        case .locationMissing: .locationMissing
        case .blockingDuplicate: .hardDuplicate
        case .possibleDuplicates: .possibleDuplicates
        case .destinationMissing: .destinationMissing
        case .invalidAssets: .invalidAssets
        case .validation(let validation):
            switch validation {
            case .nameRequired: .nameRequired
            case .manualNameTooLong, .displayNameTooLong: .nameTooLong
            case .notesTooLong: .notesTooLong
            case .tooManyPhotos: .photoLimit
            default: .saveFailed
            }
        default: .saveFailed
        }
    }
}

nonisolated enum LocationPhotoLayout {
    static let photoSide: CGFloat = 150
    static let spacing: CGFloat = 12
    static let verticalInset: CGFloat = 4
}

struct LocationPhotoControls: View {
    @Environment(\.locale) private var locale
    let model: LocationCaptureModel
    @Bindable var photoPresentation: LocationPhotoPresentation
    let onViewPhoto: (LocalAssetReference) -> Void
    @State private var pendingRemoval: LocalAssetReference?

    private var isLoadingPhotos: Bool {
        model.isImportingPhoto || model.isLoadingPhotoSelection
    }

    init(model: LocationCaptureModel, photoPresentation: LocationPhotoPresentation = LocationPhotoPresentation(),
         onViewPhoto: @escaping (LocalAssetReference) -> Void = { _ in }) {
        self.model = model
        self.photoPresentation = photoPresentation
        self.onViewPhoto = onViewPhoto
    }

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: LocationPhotoLayout.spacing) {
                    LazyHStack(spacing: LocationPhotoLayout.spacing) {
                        ForEach(model.assets, id: \.assetID) { asset in
                            LocationPhotoTile(
                                asset: asset, mediaService: model.photoService,
                                photoLabel: photoLabel(for: asset),
                                removalDisabled: model.isSaving || model.isImportingPhoto || model.isLoadingPhotoSelection,
                                onView: { onViewPhoto(asset) },
                                onRemove: { pendingRemoval = asset }
                            )
                            .frame(width: LocationPhotoLayout.photoSide, height: LocationPhotoLayout.photoSide)
                        }
                        if model.remainingPhotoCapacity > 0 || isLoadingPhotos {
                            Menu {
                                DSButton(LocationKeys.takePhoto) { photoPresentation.showCamera = true }
                                DSButton(LocationKeys.photoLibrary) { photoPresentation.showPhotoLibrary = true }
                            } label: {
                                Group {
                                    if isLoadingPhotos {
                                        ProgressView()
                                    } else {
                                        Image.appSystemIcon(.add)
                                            .font(.largeTitle)
                                    }
                                }
                                .frame(width: LocationPhotoLayout.photoSide, height: LocationPhotoLayout.photoSide)
                                .background(.quaternary, in: .rect(cornerRadius: 20))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(LocationKeys.addPhotos))
                            .disabled(!model.canImportPhotos || model.isLoadingPhotoSelection)
                        }
                    }
                    .padding(.vertical, LocationPhotoLayout.verticalInset)
                }
            }
            .scrollIndicators(.hidden)
            .listRowSeparator(.hidden)
            if model.photoImportFailed { Text(LocationKeys.photoImportFailed).foregroundStyle(.red) }
        } header: { Text(LocationKeys.photos) }
        .alert(Text(LocationKeys.removePhotoTitle), isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            DSButton(role: .cancel) { pendingRemoval = nil } label: { Text(CommonKeys.cancel) }
            DSButton(role: .destructive) {
                guard let asset = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await model.removePhoto(asset) }
            } label: { Text(LocationKeys.removePhoto) }
        } message: { Text(LocationKeys.removePhotoMessage) }
    }

    private func photoLabel(for asset: LocalAssetReference) -> String {
        String(format: LocalizationManager.localizedString(LocationKeys.photoNumber, locale: locale),
               locale: locale, Int64((model.assets.firstIndex(of: asset) ?? 0) + 1))
    }
}

struct LocationPhotoTile: View {
    private enum Metric {
        static let cornerRadius: CGFloat = 20
        static let buttonSide: CGFloat = 32
        static let hitSide: CGFloat = 44
        static let buttonInset: CGFloat = 4
    }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let asset: LocalAssetReference
    let mediaService: (any LocationMediaService)?
    let photoLabel: String
    let removalDisabled: Bool
    let onView: () -> Void
    var onRemove: (() -> Void)? = nil

    var body: some View {
        DSButton(action: onView) {
            Color.clear
                .overlay {
                    LocationPhotoImage(asset: asset, mediaService: mediaService, thumbnail: true)
                }
                .background(.quaternary)
                .clipShape(.rect(cornerRadius: Metric.cornerRadius))
                .contentShape(.rect(cornerRadius: Metric.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photoLabel)
        .overlay(alignment: .topTrailing) {
            if let onRemove {
                DSButton(role: .destructive, action: onRemove) {
                    Image.appSystemIcon(.close)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: Metric.buttonSide, height: Metric.buttonSide)
                        .background {
                            if reduceTransparency { Circle().fill(.background) }
                        }
                        .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: .circle)
                        .frame(width: Metric.hitSide, height: Metric.hitSide)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocationKeys.removePhoto))
                .accessibilityValue(photoLabel)
                .disabled(removalDisabled)
                .padding(Metric.buttonInset)
            }
        }
    }
}

#Preview { LocationDetailsEditor(model: LocationEditorPreview.model(), rendersLiveMap: false).environment(DSToastManager()) }
#Preview { LocationDestinationLabel(model: LocationEditorPreview.model()) }
#Preview { Form { LocationSaveFeedback(model: LocationEditorPreview.model()) } }
#Preview { Form { LocationPhotoControls(model: LocationEditorPreview.model()) } }
#Preview(traits: .modifier(LocationPhotoControlsPreviewData())) {
    LocationPhotoControlsPreview()
}
#Preview(traits: .modifier(LocationPhotoControlsLoadingPreviewData())) {
    LocationPhotoControlsPreview()
}
#Preview {
    LocationPhotoTile(asset: LocationEditorPreview.photoAssets[0], mediaService: LocationEditorPreview.photoService(),
                      photoLabel: LocationEditorPreview.photoLabel, removalDisabled: false, onView: {}, onRemove: {})
        .frame(width: 150, height: 150).padding()
}
#Preview(traits: .modifier(LocationPhotoControlsPreviewData())) {
    LocationPhotoControlsPreview()
        .environment(\.layoutDirection, .rightToLeft)
}

private struct LocationPhotoControlsPreview: View {
    @Environment(LocationCaptureModel.self) private var model

    var body: some View { Form { LocationPhotoControls(model: model) } }
}

private struct LocationPhotoControlsPreviewData: PreviewModifier {
    static func makeSharedContext() async throws -> LocationCaptureModel {
        let model = LocationEditorPreview.photoModel()
        await LocationEditorPreview.addPhotos(to: model)
        return model
    }

    func body(content: Content, context: LocationCaptureModel) -> some View {
        content.environment(context)
    }
}

private struct LocationPhotoControlsLoadingPreviewData: PreviewModifier {
    static func makeSharedContext() async throws -> LocationCaptureModel {
        let model = try await LocationPhotoControlsPreviewData.makeSharedContext()
        _ = model.beginPhotoSelection()
        return model
    }

    func body(content: Content, context: LocationCaptureModel) -> some View {
        content.environment(context)
    }
}

#Preview { LocationEditorMapPreview(name: LocationEditorPreview.candidate.name, coordinate: LocationEditorPreview.candidate.coordinate, rendersLiveMap: false).padding() }

#Preview { LocationDetailsEditor(model: LocationEditorPreview.editModel(), rendersLiveMap: false).environment(DSToastManager()) }

#Preview {
    Form {
        LocationDetailsFields(name: LocationEditorPreview.candidate.name, address: LocationEditorPreview.candidate.address,
                              coordinate: LocationEditorPreview.candidate.coordinate, rendersLiveMap: false,
                              routeState: MapRoutePreviewFixtures.available) {
            Text(LocationKeys.displayName)
        } notes: { Text(LocationKeys.notes) }
    }
}

#Preview {
    LocationDetailsEditor(mode: .read,
        readContext: LocationDetailsReadContext(place: MapQuickPlacePreviewFixtures.searchPlace,
            savedLocation: LocationEditorPreview.savedLocation, collection: .mock),
        rendersLiveMap: false, onBeginUpdate: { LocationEditorPreview.editModel() })
        .environment(DSToastManager())
}

#Preview {
    Form {
        LocationDetailsCollectionSection(mode: .read, model: nil, collection: .mock, isSaved: true, onChoose: {})
    }
}
