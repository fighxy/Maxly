import SwiftUI

/// Отступы и размеры каркаса.
public enum MaxlyTheme {
    public static let pad: CGFloat = 16
    /// Высота трёхстрочной строки списка чатов.
    public static let row: CGFloat = 78
    /// Аватар строки чата.
    public static let avatar: CGFloat = 60
    /// Аватар контактов и звонков.
    public static let smallAvatar: CGFloat = 50
    public static let radius: CGFloat = 18
    /// Доля ширины ленты, которую занимает пузырь.
    public static let bubbleMax: CGFloat = 0.82
    /// Отступ разделителя строки: от начала текста, а не от края.
    public static let separatorInset: CGFloat = pad + avatar + 12
}

public enum AvatarInitials {
    public static func text(for name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        if !letters.isEmpty { return letters.uppercased() }
        return String(name.prefix(1)).uppercased()
    }
}
