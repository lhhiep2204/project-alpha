//
//  DeviceLocationService.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import Foundation

/// One app-owned broker. Construction and authorization reads do not start location work.
nonisolated protocol DeviceLocationService: Sendable {
    func authorization() async -> LocationAuthorization

    /// Call only for an explicit action needing position. Requests When In Use if undetermined,
    /// then acquires one valid fix within the approved timeout, even if its timestamp is old.
    /// Cancellation ends this consumer without cancelling another consumer. Reduced accuracy is
    /// accepted and returned unchanged.
    func currentPosition() async throws(LocationServiceError) -> DevicePosition
}

/// Wall time rejects future fix timestamps; cancellable elapsed-time sleep bounds acquisition.
nonisolated protocol ServiceClock: Sendable {
    func now() -> Date
    func sleep(for duration: Duration) async throws
}
