//
//  Date+Extension.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 19/9/26.
//

import Foundation

extension Date {
    /// Converts the date into a string for user-facing display.
    ///
    /// - Parameter style: The format style to use (e.g. `.dayMonthYear`).
    /// - Returns: A string formatted with the user’s current locale and time zone.
    func toString(style: DateFormat, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = style.rawValue
        formatter.locale = locale
        formatter.timeZone = timeZone
        return formatter.string(from: self)
    }

    /// Converts the date into a machine-safe string for API or logs.
    ///
    /// - Parameter style: The format style to use (e.g. `.isoDateTime`).
    /// - Returns: A string formatted with a fixed POSIX locale and UTC time zone.
    func toAPIString(style: DateFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = style.rawValue
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: self)
    }
}
