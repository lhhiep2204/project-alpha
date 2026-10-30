//
//  LocationCameraCapture.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/10/26.
//

import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import UIKit

struct LocationCameraPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    var originalCaptureTime: String?
    var captureOffset: String?
    var captureSubsecond: String?
}

/// The media service still owns validation, downsampling and draft staging.
nonisolated enum LocationCameraPhotoEncoder {
    @concurrent static func encode(_ image: UIImage, originalCaptureTime: String? = nil,
                                   captureOffset: String? = nil, captureSubsecond: String? = nil) async -> Data? {
        guard !Task.isCancelled, let raster = image.cgImage else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let orientation: Int
        switch image.imageOrientation {
        case .up: orientation = 1
        case .upMirrored: orientation = 2
        case .down: orientation = 3
        case .downMirrored: orientation = 4
        case .leftMirrored: orientation = 5
        case .right: orientation = 6
        case .rightMirrored: orientation = 7
        case .left: orientation = 8
        @unknown default: return nil
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
                                           kCGImageDestinationLossyCompressionQuality: 1]
        if let originalCaptureTime {
            var exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: originalCaptureTime]
            if let captureOffset { exif[kCGImagePropertyExifOffsetTimeOriginal] = captureOffset }
            if let captureSubsecond { exif[kCGImagePropertyExifSubsecTimeOriginal] = captureSubsecond }
            properties[kCGImagePropertyExifDictionary] = exif
        }
        CGImageDestinationAddImage(destination, raster, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination), !Task.isCancelled else { return nil }
        return output as Data
    }
}

struct LocationCameraCapture: View {
    private enum Status {
        case checking, authorized, denied, unavailable
    }

    @Environment(\.openURL) private var openURL
    @State private var status: Status = .checking
    var cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    let onCapture: (LocationCameraPhoto) -> Void
    let onCancel: () -> Void

    var body: some View {
        Group {
            switch status {
            case .authorized:
                LocationCameraPicker(onCapture: onCapture, onCancel: onCancel)
                    .ignoresSafeArea()
            case .checking:
                ProgressView()
            case .denied, .unavailable:
                NavigationStack {
                    VStack(spacing: 20) {
                        Text(status == .denied ? LocationKeys.cameraAccessDenied : .cameraUnavailable)
                            .multilineTextAlignment(.center)
                        if status == .denied {
                            DSButton(CommonKeys.settings) {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                    .padding()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            DSButton(CommonKeys.close, action: onCancel)
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                }
            }
        }
        .task {
            guard cameraAvailable else { status = .unavailable; return }
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            default: granted = false
            }
            guard !Task.isCancelled else { return }
            status = granted ? .authorized : .denied
        }
    }
}

private struct LocationCameraPicker: UIViewControllerRepresentable {
    let onCapture: (LocationCameraPhoto) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCapture: (LocationCameraPhoto) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (LocationCameraPhoto) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else { onCancel(); return }
            let metadata = info[.mediaMetadata] as? [CFString: Any]
            let exif = metadata?[kCGImagePropertyExifDictionary] as? [CFString: Any]
            onCapture(LocationCameraPhoto(image: image,
                originalCaptureTime: exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
                captureOffset: exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String,
                captureSubsecond: exif?[kCGImagePropertyExifSubsecTimeOriginal] as? String))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}

#Preview {
    LocationCameraCapture(cameraAvailable: false, onCapture: { _ in }, onCancel: {})
}

// LocationCameraPicker needs physical camera hardware and permission, so it cannot have
// a deterministic live preview. The wrapper preview above exercises its safe fallback.
