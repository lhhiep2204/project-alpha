//
//  LocationPhotoTimestamp.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/10/26.
//

import Foundation
import ImageIO

/// Display the camera's wall-clock time, retaining its offset when the source supplies one.
/// An offset-free EXIF time stays offset-free in meaning; UTC only anchors its components.
nonisolated struct LocationPhotoTimestamp: Equatable, Sendable {
    let date: Date
    let timeZone: TimeZone

    private enum Format {
        static let locale = "en_US_POSIX"
        static let date = "yyyy:MM:dd HH:mm:ss"
        static let offsetDate = "yyyy:MM:dd HH:mm:ssxxx"
    }

    static func read(from source: CGImageSource) -> Self? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
        return parse(original: original, offset: offset)
    }

    static func parse(original: String, offset: String?) -> Self? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Format.locale)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        formatter.dateFormat = Format.date
        guard let wallTime = formatter.date(from: original), formatter.string(from: wallTime) == original else { return nil }
        if let offset {
            formatter.dateFormat = Format.offsetDate
            if let instant = formatter.date(from: original + offset) {
                let seconds = Int(wallTime.timeIntervalSince(instant))
                if let zone = TimeZone(secondsFromGMT: seconds) {
                    return Self(date: instant, timeZone: zone)
                }
            }
        }
        return Self(date: wallTime, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
}
