//
//  LocationCameraPhotoTests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/10/26.
//

import ImageIO
import Testing
import UIKit
@testable import ProjectAlpha

@MainActor
struct LocationCameraPhotoTests {
    /// Camera rasters may carry orientation separately; the normal media pipeline must retain it.
    @Test func cameraOrientationSurvivesImportEncoding() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8), format: format)
        let raster = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
        let cgImage = try #require(raster.cgImage)
        let cameraImage = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
        let data = try #require(await LocationCameraPhotoEncoder.encode(cameraImage))
        let imported = try LocalMediaImageEncoder.encode(data, longestSide: 1600, quality: 0.78)
        #expect(imported.width == 8)
        #expect(imported.height == 12)
        let source = try #require(CGImageSourceCreateWithData(imported.data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func invalidCameraImageReportsEncodingFailure() async {
        #expect(await LocationCameraPhotoEncoder.encode(UIImage()) == nil)
    }

    private var format: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return format
    }
}
