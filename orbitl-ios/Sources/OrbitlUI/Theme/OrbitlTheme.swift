import SwiftUI

/// Отступы и размеры каркаса. Это не копия Komet, только общая сетка экранов.
public enum OrbitlTheme {
    public static let pad: CGFloat = 16
    public static let row: CGFloat = 76
    public static let avatar: CGFloat = 52
    public static let radius: CGFloat = 18
}

public enum AvatarInitials {
    public static func text(for name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        if !letters.isEmpty { return letters.uppercased() }
        return String(name.prefix(1)).uppercased()
    }
}
