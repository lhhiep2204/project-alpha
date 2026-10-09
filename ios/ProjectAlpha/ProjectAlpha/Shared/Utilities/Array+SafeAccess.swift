//
//  Array+SafeAccess.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 23/9/26.
//

/// Bounds-checked element access for collection/map selection code.
extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
