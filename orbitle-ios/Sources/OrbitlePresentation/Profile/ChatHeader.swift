import Foundation
import OrbitleDomain

/// То, что о чате меняется на лету и приходит из списка чатов: сеть, «печатает…», звук.
public struct ChatHeaderLive: Equatable, Sendable {
    public var isOnline: Bool
    public var isMuted: Bool
    public var isVerified: Bool
    /// Кто печатает прямо сейчас, по времени начала.
    public var typing: [TypingFormatter.Participant]

    public init(isOnline: Bool = false, isMuted: Bool = false, isVerified: Bool = false, typing: [TypingFormatter.Participant] = []) {
        self.isOnline = isOnline
        self.isMuted = isMuted
        self.isVerified = isVerified
        self.typing = typing
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
            // Тот же текст, что в строке списка, без «…»: точки рисует экран.
            let chatType: ChatType = kind == .group ? .group : .private
            if let text = TypingFormatter.headerText(chatType: chatType, participants: live.typing) {
                return .typing(text)
            }
            if kind == .user, live.isOnline || isOnline { return .accent("в сети") }
            // «Был(а) недавно» карточки в шапке со строчной.
            return .plain(subtitle.prefix(1).lowercased() + subtitle.dropFirst())
        }
    }
}
