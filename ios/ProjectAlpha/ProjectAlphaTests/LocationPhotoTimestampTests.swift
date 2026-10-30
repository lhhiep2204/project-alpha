//
//  LocationPhotoTimestampTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/10/26.
//

import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import ProjectAlpha

@MainActor
struct LocationPhotoTimestampTests {
    private enum Fixture {
        static let original = "2026:10:23 07:11:30"
        static let offset = "+07:00"
        static let subsecond = "125"
        static let invalidDate = "2026:02:30 07:11:30"
        static let cameraOwner = "Private camera owner"
    }

    @Test func originalTimeAndOffsetSurviveSanitizationWithoutPrivateMetadata() async throws {
        let cameraBytes = try #require(await LocationCameraPhotoEncoder.encode(image(),
            originalCaptureTime: Fixture.original, captureOffset: Fixture.offset, captureSubsecond: Fixture.subsecond))
        let inputSource = try #require(CGImageSourceCreateWithData(cameraBytes as CFData, nil))
        let input = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(input, UTType.jpeg.identifier as CFString, 1, nil))
        let originalProperties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 10.7],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: Fixture.original,
                kCGImagePropertyExifOffsetTimeOriginal: Fixture.offset,
                kCGImagePropertyExifSubsecTimeOriginal: Fixture.subsecond,
                kCGImagePropertyExifCameraOwnerName: Fixture.cameraOwner
            ]
        ]
        CGImageDestinationAddImageFromSource(destination, inputSource, 0, originalProperties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let stored = try LocalMediaImageEncoder.encode(input as Data, longestSide: 1600, quality: 0.78)
        let source = try #require(CGImageSourceCreateWithData(stored.data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == Fixture.original)
        #expect(exif[kCGImagePropertyExifOffsetTimeOriginal] as? String == Fixture.offset)
        #expect(exif[kCGImagePropertyExifSubsecTimeOriginal] as? String == Fixture.subsecond)
        #expect(exif[kCGImagePropertyExifCameraOwnerName] == nil)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let parsed = try #require(LocationPhotoTimestamp.read(from: source))
        let expected = try #require(LocationPhotoTimestamp.parse(original: Fixture.original, offset: Fixture.offset))
        #expect(parsed == expected)
        #expect(parsed.timeZone.secondsFromGMT(for: parsed.date) == 7 * 3600)
    }

    @Test func missingOrInvalidCaptureTimeNeverInventsADate() async throws {
        let data = try #require(await LocationCameraPhotoEncoder.encode(image()))
        let stored = try LocalMediaImageEncoder.encode(data, longestSide: 1600, quality: 0.78)
        let source = try #require(CGImageSourceCreateWithData(stored.data as CFData, nil))
        #expect(LocationPhotoTimestamp.read(from: source) == nil)
        #expect(LocationPhotoTimestamp.parse(original: Fixture.invalidDate, offset: nil) == nil)
        #expect(LocationPhotoTimestamp.parse(original: String(), offset: nil) == nil)
    }

    @Test func captureWallTimeStaysTheSameWithOrWithoutAnOffset() throws {
        let withOffset = try #require(LocationPhotoTimestamp.parse(original: Fixture.original, offset: Fixture.offset))
        let withoutOffset = try #require(LocationPhotoTimestamp.parse(original: Fixture.original, offset: nil))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = withOffset.timeZone
        let local = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: withOffset.date)
        calendar.timeZone = withoutOffset.timeZone
        #expect(local == calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: withoutOffset.date))
        #expect(local.hour == 7)
        #expect(local.minute == 11)
    }

    @Test(arguments: [UIImage.Orientation.up, .upMirrored, .down, .downMirrored, .leftMirrored, .right, .rightMirrored, .left])
    func cameraOrientationAndCaptureTimeSurviveTogether(_ orientation: UIImage.Orientation) async throws {
        let raster = try #require(image().cgImage)
        let image = UIImage(cgImage: raster, scale: 1, orientation: orientation)
        let bytes = try #require(await LocationCameraPhotoEncoder.encode(image, originalCaptureTime: Fixture.original))
        let stored = try LocalMediaImageEncoder.encode(bytes, longestSide: 1600, quality: 0.78)
        let rotated = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        #expect(stored.width == (rotated ? 80 : 120))
        #expect(stored.height == (rotated ? 120 : 80))
        let source = try #require(CGImageSourceCreateWithData(stored.data as CFData, nil))
        #expect(LocationPhotoTimestamp.read(from: source) != nil)
    }

    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
    }
}
