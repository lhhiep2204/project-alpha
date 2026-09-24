#if DEBUG
import Foundation

extension Collection {
    static let mock = Collection(
        id: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!,
        name: "Food",
        icon: .symbol(name: "folder"),
        isDefault: false,
        createdAt: Date(timeIntervalSince1970: 1697059200),
        updatedAt: Date(timeIntervalSince1970: 1697059200),
        revision: 1
    )
}
#endif
