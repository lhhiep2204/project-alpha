//
//  LocalMediaImageEncoder.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Called only from the media actor, never from a View or MainActor task.
nonisolated enum LocalMediaImageEncoder {
    struct EncodedPhoto: Sendable {
        let data: Data
        let width: Int
        let height: Int
    }

    static func encode(_ data: Data, longestSide: Int, quality: Double) throws -> EncodedPhoto {
        try Task.checkCancellation()
        let image = try decodedImage(data, longestSide: longestSide)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw LocationMediaError.invalidImage }
        // A transformed raster plus fresh metadata preserves visual orientation
        // retaining only the original capture time, without GPS or unrelated EXIF.
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: 1
        ]
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let exif = sourceProperties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String, !original.isEmpty {
            var timestamp: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: original]
            for key in [kCGImagePropertyExifOffsetTimeOriginal, kCGImagePropertyExifSubsecTimeOriginal] {
                if let value = exif[key] as? String { timestamp[key] = value }
            }
            properties[kCGImagePropertyExifDictionary] = timestamp
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LocationMediaError.invalidImage }
        try Task.checkCancellation()
        return EncodedPhoto(data: output as Data, width: image.width, height: image.height)
    }

    static func validate(_ data: Data, longestSide: Int) throws {
        _ = try decodedImage(data, longestSide: longestSide)
    }

    private static func decodedImage(_ data: Data, longestSide: Int) throws -> CGImage {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete else {
            throw LocationMediaError.invalidImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LocationMediaError.invalidImage
        }
        return image
    }
}
