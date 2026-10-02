import Foundation
import OrbitleDomain

/// То, что о чате меняется на лету и приходит из списка чатов: сеть, «печатает…», звук.
public struct ChatHeaderLive: Equatable, Sendable {
    public var isOnline: Bool
    public var isMuted: Bool
    public var isVerified: Bool
    /// Сколько человек печатает прямо сейчас.
    public var typingCount: Int

    public init(isOnline: Bool = false, isMuted: Bool = false, isVerified: Bool = false, typingCount: Int = 0) {
        self.isOnline = isOnline
        self.isMuted = isMuted
        self.isVerified = isVerified
        self.typingCount = typingCount
    }
}

/// Вторая строка шапки чата: «печатает…» с точками, «в сети» цветом акцента,
/// остальное серым. У «Избранного» строки нет.
public enum ChatHeaderStatus: Equatable, Sendable {
    case none
    case plain(String)
    case accent(String)
    case typing(String)

    public var text: String? {
        switch self {
        case .none: nil
        case .plain(let text), .accent(let text), .typing(let text): text
        }
    }

    /// `subtitle` — подпись карточки (статус, участники, подписчики); живые данные её перекрывают.
    /// `isOnline` — сеть по карточке, `live.isOnline` — по списку чатов.
    public static func make(kind: ChatProfile.Kind, subtitle: String, isOnline: Bool, live: ChatHeaderLive) -> ChatHeaderStatus {
        switch kind {
        case .saved:
            return .none
        case .channel:
            return .plain(subtitle)
        case .user, .bot, .group:
            if live.typingCount > 0 {
                let text = ChatListFormatter.typingText(count: live.typingCount, type: kind == .group ? .group : .private)
                // Точки рисует экран, в тексте их нет.
                return .typing(text.hasSuffix("…") ? String(text.dropLast()) : text)
            }
            if kind == .user, live.isOnline || isOnline { return .accent("в сети") }
            // «Был(а) недавно» карточки в шапке со строчной.
            return .plain(subtitle.prefix(1).lowercased() + subtitle.dropFirst())
        }
    }
}
