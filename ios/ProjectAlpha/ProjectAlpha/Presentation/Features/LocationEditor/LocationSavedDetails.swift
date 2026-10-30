//
//  LocationSavedDetails.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import ImageIO
import SwiftUI
import UIKit


struct LocationPhotoSelection: Identifiable {
    let asset: LocalAssetReference
    var id: UUID { asset.assetID }
}

/// Media has already downsampled the JPEG; its final image decode also avoids the UI actor.
struct LocationPhotoImage: View {
    let asset: LocalAssetReference
    let mediaService: (any LocationMediaService)?
    let thumbnail: Bool
    var zoomable = false
    var isActive = true
    var onCaptureTime: ((LocationPhotoTimestamp?) -> Void)?
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                if zoomable {
                    LocationPhotoZoomView(image: image, isActive: isActive)
                } else {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: thumbnail ? .fill : .fit)
                }
            } else if failed {
                Label { Text(LocationKeys.photoUnavailable) } icon: { Image.appSystemIcon(.photo) }
                    .font(.caption)
            } else {
                ProgressView()
            }
        }
        .task(id: asset) {
            image = nil
            failed = false
            do {
                guard let mediaService else { failed = true; return }
                let data = try await mediaService.photoData(for: asset, thumbnail: thumbnail)
                let decoded = await LocationPhotoDecoder.decode(data, readsTimestamp: !thumbnail)
                guard !Task.isCancelled else { return }
                image = decoded.image
                failed = decoded.image == nil
                onCaptureTime?(decoded.timestamp)
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }
}

private enum LocationPhotoDecoder {
    @concurrent nonisolated static func decode(_ data: Data, readsTimestamp: Bool) async
        -> (image: CGImage?, timestamp: LocationPhotoTimestamp?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return (nil, nil) }
        let image = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        return (image, readsTimestamp ? LocationPhotoTimestamp.read(from: source) : nil)
    }
}

struct LocationPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let assets: [LocalAssetReference]
    let mediaService: (any LocationMediaService)?
    @State private var selectedID: UUID?
    @State private var captureTimes: [UUID: LocationPhotoTimestamp] = [:]

    init(assets: [LocalAssetReference], selectedID: UUID, mediaService: (any LocationMediaService)?) {
        self.assets = assets
        self.mediaService = mediaService
        _selectedID = State(initialValue: selectedID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(assets, id: \.assetID) { asset in
                                LocationZoomablePhoto(asset: asset, mediaService: mediaService,
                                                      isActive: selectedID == asset.assetID) { timestamp in
                                    captureTimes[asset.assetID] = timestamp
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .id(asset.assetID)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $selectedID)
                }
                // Only the image viewport extends behind the bars. Controls retain safe-area layout.
                .ignoresSafeArea(.container)
                .accessibilityLabel(photoTitle)
                .background {
                    DSButton(CommonKeys.back) { movePhoto(by: -1) }
                        .keyboardShortcut(.leftArrow, modifiers: []).hidden()
                    DSButton(CommonKeys.next) { movePhoto(by: 1) }
                        .keyboardShortcut(.rightArrow, modifiers: []).hidden()
                }
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: movePhoto(by: 1)
                    case .decrement: movePhoto(by: -1)
                    @unknown default: break
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if assets.count > 1 {
                    LocationPhotoPageControl(assets: assets, selectedID: $selectedID)
                        .fixedSize()
                        .padding(.bottom, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    LocationPhotoCloseButton { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) {
                    if let selectedID, let timestamp = captureTimes[selectedID] {
                        LocationPhotoTimestampTitle(timestamp: timestamp)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func movePhoto(by offset: Int) {
        guard let index = assets.firstIndex(where: { $0.assetID == selectedID }),
              assets.indices.contains(index + offset) else { return }
        selectedID = assets[index + offset].assetID
    }

    private var photoTitle: String {
        String(format: LocalizationManager.localizedString(LocationKeys.photoNumber, locale: locale),
               locale: locale, Int64((assets.firstIndex { $0.assetID == selectedID } ?? 0) + 1))
    }
}

private struct LocationPhotoCloseButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let close: () -> Void

    var body: some View {
        DSButton(action: close) {
            Image.appSystemIcon(.close)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .background {
            if reduceTransparency { Circle().fill(Color(uiColor: .darkGray)) }
        }
        .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: .circle)
        .accessibilityLabel(Text(CommonKeys.close))
        .keyboardShortcut(.cancelAction)
    }
}

/// Use the platform page control for taps, scrubbing, VoiceOver and pointer input.
/// Its frame belongs to the safe-area overlay, independent of the full-screen image viewport.
struct LocationPhotoPageControl: UIViewRepresentable {
    let assets: [LocalAssetReference]
    @Binding var selectedID: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.backgroundStyle = .prominent
        control.allowsContinuousInteraction = true
        control.hidesForSinglePage = true
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        context.coordinator.parent = self
        control.numberOfPages = assets.count
        control.currentPage = assets.firstIndex { $0.assetID == selectedID } ?? 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPageControl, context: Context) -> CGSize? {
        let size = uiView.size(forNumberOfPages: assets.count)
        return CGSize(width: max(44, size.width), height: max(44, size.height))
    }

    final class Coordinator: NSObject {
        var parent: LocationPhotoPageControl

        init(parent: LocationPhotoPageControl) { self.parent = parent }

        @objc func changed(_ control: UIPageControl) {
            guard parent.assets.indices.contains(control.currentPage) else { return }
            parent.selectedID = parent.assets[control.currentPage].assetID
        }
    }
}

#Preview {
    LocationPhotoCloseButton(close: {}).padding().background(.black).preferredColorScheme(.dark)
}

#Preview {
    LocationPhotoPageControl(assets: LocationEditorPreview.photoAssets,
                            selectedID: .constant(LocationEditorPreview.photoAssets[1].assetID))
        .fixedSize().padding().background(.black).preferredColorScheme(.dark)
}

private struct LocationZoomablePhoto: View {
    let asset: LocalAssetReference
    let mediaService: (any LocationMediaService)?
    var isActive = true
    var onCaptureTime: ((LocationPhotoTimestamp?) -> Void)?

    var body: some View {
        LocationPhotoImage(asset: asset, mediaService: mediaService, thumbnail: false,
                           zoomable: true, isActive: isActive, onCaptureTime: onCaptureTime)
    }
}

private struct LocationPhotoTimestampTitle: View {
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let timestamp: LocationPhotoTimestamp

    var body: some View {
        VStack(spacing: 1) {
            ViewThatFits(in: .horizontal) {
                Text(timestamp.date, format: Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: timestamp.timeZone))
                Text(timestamp.date, format: Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timestamp.timeZone))
                Text(timestamp.date, format: Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, timeZone: timestamp.timeZone))
            }
            .font(.subheadline.weight(.semibold))
            Text(timestamp.date, format: Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timestamp.timeZone))
                .font(.caption).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, 16).padding(.vertical, 5)
        .background {
            if reduceTransparency { Capsule().fill(.black) }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LocationPhotoTimestampTitle(timestamp: LocationPhotoTimestamp(
        date: LocationEditorPreview.date, timeZone: .gmt))
        .preferredColorScheme(.dark)
}

#Preview {
    LocationPhotoImage(asset: LocationPhotoPreview.asset, mediaService: nil, thumbnail: true).frame(width: 80, height: 80)
}
#Preview {
    LocationPhotoViewer(assets: [LocationPhotoPreview.asset], selectedID: LocationPhotoPreview.asset.assetID, mediaService: nil)
}
#Preview { LocationZoomablePhoto(asset: LocationPhotoPreview.asset, mediaService: nil) }
#Preview {
    LocationPhotoViewer(assets: LocationEditorPreview.photoAssets,
                        selectedID: LocationEditorPreview.photoAssets[1].assetID,
                        mediaService: LocationEditorPreview.photoService())
}

private enum LocationPhotoPreview {
    private static let token = "photos/preview.jpg"
    static let asset = try! LocalAssetReference(
        assetID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)), relativeFileToken: token
    )
}
