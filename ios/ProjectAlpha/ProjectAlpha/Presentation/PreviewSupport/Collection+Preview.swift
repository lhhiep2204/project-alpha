#if DEBUG
import Foundation

extension Collection {
    private enum Fixture {
        static let id = "123e4567-e89b-12d3-a456-426614174000"
        static let name = "Food"
    }

    static let mock = Collection(
        id: UUID(uuidString: Fixture.id)!,
        name: Fixture.name,
        icon: .symbol(name: DSSystemIcon.folder.rawValue),
        isDefault: false,
        createdAt: Date(timeIntervalSince1970: 1697059200),
        updatedAt: Date(timeIntervalSince1970: 1697059200),
        revision: 1
    )
}
#endif
