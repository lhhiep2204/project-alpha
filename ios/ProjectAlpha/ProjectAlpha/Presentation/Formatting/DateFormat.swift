//
//  DateFormat.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 19/9/26.
//

import Foundation

/// Preset format for displaying or serializing Date objects.
/// Use with `Date.toLocalizedString(style:)` or `Date.toAPISafeString(style:)`.
enum DateFormat: String {
    // MARK: - API-safe formats (en_US_POSIX, UTC)

    /// ISO 8601 date format. Example: `2022-09-03`
    case isoDate = "yyyy-MM-dd"

    /// ISO 8601 date & time. Example: `2022-09-03T15:14:00Z`
    case isoDateTime = "yyyy-MM-dd'T'HH:mm:ssZ"

    /// Full date & time with milliseconds. Example: `2022-09-03T15:14:00.000Z`
    case isoDateTimeWithMillis = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

    // MARK: - User-facing formats

    /// Day, abbreviated month, full year. Example: `03 Sep 2022`
    case dayMonthYear = "dd MMM yyyy"

    /// Full day with weekday. Example: `Saturday, Sep 03, 2022
    case fullWeekdayDate = "EEEE, MMM d, yyyy"

    /// Short numeric format. Example: `03/09/2022`
    case daySlashMonthYear = "dd/MM/yyyy"

    /// Time only, 24-hour. Example: `15:14`
    case hourMinute = "HH:mm"

    /// Time with seconds. Example: `15:14:00`
    case timeWithSeconds = "HH:mm:ss"

    /// Day, Month, Year and Time. Example: `03 Sep 2022 at 15:14`
    case dateAndTime = "dd MMM yyyy 'at' HH:mm"
}
