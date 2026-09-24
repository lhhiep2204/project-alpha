import SwiftUI

protocol LocalizedKey: RawRepresentable where RawValue == String {}

extension Text {
    init(_ key: some LocalizedKey) {
        self.init(LocalizedStringKey(key.rawValue))
    }
}

extension Button where Label == Text {
    init(_ key: some LocalizedKey, action: @escaping () -> Void) {
        self.init(LocalizedStringKey(key.rawValue), action: action)
    }
}

extension Language {
    var layoutDirection: LayoutDirection { isRTL ? .rightToLeft : .leftToRight }
}
