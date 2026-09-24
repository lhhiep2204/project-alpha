//
//  Logger.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 13/9/26.
//

import Foundation

/// Represents different levels of logging with associated emoji symbols for easy identification.
enum LogLevel: String {
    /// Debug logging - useful for debugging during development.
    case debug = "🟡"
    /// Info logging - general information about app execution.
    case info = "🔵"
    /// Warning logging - indicates potential issues that aren't necessarily errors.
    case warning = "🟠"
    /// Error logging - indicates critical issues that need attention.
    case error = "🔴"
}

/// A lightweight logger for debugging and tracking app execution.
///
/// This logger prints messages with metadata like **file name, line number, column, and function name**.
/// It only logs in **DEBUG, STAGING, or TEST** builds and automatically ignores logging in production.
///
/// ## Example Usage:
/// ```swift
/// Logger.debug("This is a debug message")
/// Logger.error("Something went wrong!", error.localizedDescription)
/// ```
///
/// The logs will be printed in the console like this:
/// ```
/// 🟡 Logger.swift: Line 45, Column: 10 ~ myFunction()
/// Debug message content...
/// ```
struct Logger {
    /// Prevents initialization since `Logger` is a static utility.
    private init() {}

    // swiftlint:disable function_parameter_count
    /// Writes a log message with the given log level.
    ///
    /// - Parameters:
    ///   - level: The severity level of the log (e.g., `.debug`, `.error`).
    ///   - file: The file where the log was called. Defaults to `#file`.
    ///   - line: The line number where the log was called. Defaults to `#line`.
    ///   - column: The column number where the log was called. Defaults to `#column`.
    ///   - function: The function name where the log was called. Defaults to `#function`.
    ///   - messages: The message(s) to be logged.
    private static func write(
        _ level: LogLevel,
        file: String,
        line: Int,
        column: Int,
        function: String,
        _ messages: Any...
    ) {
#if DEBUG
        let fileName = getFileName(file)
        let messageString = messages.map { "\($0)" }.joined(separator: "\n")

        print("""
            \(level.rawValue) \(AppInfoHelper.appName) - \(fileName): Line \(line), Column: \(column)
            - Function: \(function)
            - Messages:
            \(messageString)
            """)
#endif
    }
    // swiftlint:enable function_parameter_count

    /// Extracts the file name from a full file path.
    ///
    /// - Parameter file: The full file path.
    /// - Returns: The name of the file (e.g., `"Logger.swift"`).
    private static func getFileName(_ file: String) -> String {
        let fileURL = URL(fileURLWithPath: file)
        return fileURL.lastPathComponent
    }
}

// MARK: - Public Logging Methods
extension Logger {
    /// Logs a **debug** message.
    static func debug(
        file: String = #file,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
        _ messages: Any...
    ) {
        write(.debug, file: file, line: line, column: column, function: function, messages)
    }

    /// Logs an **info** message.
    static func info(
        file: String = #file,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
        _ messages: Any...
    ) {
        write(.info, file: file, line: line, column: column, function: function, messages)
    }

    /// Logs a **warning** message.
    static func warning(
        file: String = #file,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
        _ messages: Any...
    ) {
        write(.warning, file: file, line: line, column: column, function: function, messages)
    }

    /// Logs an **error** message.
    static func error(
        file: String = #file,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
        _ messages: Any...
    ) {
        write(.error, file: file, line: line, column: column, function: function, messages)
    }
}
