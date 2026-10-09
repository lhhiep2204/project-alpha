//
//  Collection+Preview.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/9/26.
//

import Foundation

extension Collection {
    private enum Fixture {
        nonisolated static let id = "123e4567-e89b-12d3-a456-426614174000"
        nonisolated static let name = "Food"
    }

    nonisolated static let mock = Collection(
        id: UUID(uuidString: Fixture.id)!,
        name: Fixture.name,
        isDefault: false,
        createdAt: Date(timeIntervalSince1970: 1697059200),
        updatedAt: Date(timeIntervalSince1970: 1697059200),
        revision: 1
    )
}
