import Foundation

/// Запись истории звонков.
public struct CallRecord: Identifiable, Hashable, Sendable {
    public enum Direction: Hashable, Sendable {
        case outgoing
        case incoming
    }

    public enum Outcome: Hashable, Sendable {
        /// Разговор состоялся.
        case answered
        /// Входящий, на который не ответили.
        case missed
        /// Звонящий сбросил сам до ответа.
        case cancelled
        /// Собеседник отклонил.
        case declined
    }

    public let id: String
    /// Собеседник: id пользователя или группового чата.
    public var peerId: String
    public var title: String
    public var avatarURL: URL?
    public var isGroup: Bool
    /// Чат, который открывается по нажатию на звонок.
    public var chatId: String?
    public var direction: Direction
    public var outcome: Outcome
    public var isVideo: Bool
    public var date: Date
    public var duration: TimeInterval?

    public init(
        id: String,
        peerId: String,
        title: String,
        avatarURL: URL? = nil,
        isGroup: Bool = false,
        chatId: String? = nil,
        direction: Direction,
        outcome: Outcome,
        isVideo: Bool = false,
        date: Date,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.peerId = peerId
        self.title = title
        self.avatarURL = avatarURL
        self.isGroup = isGroup
        self.chatId = chatId
        self.direction = direction
        self.outcome = outcome
        self.isVideo = isVideo
        self.date = date
        self.duration = duration
    }

    /// Пропущенный входящий: такие звонки выделяются красным и попадают в «Пропущенные».
    public var isMissed: Bool { direction == .incoming && outcome == .missed }
}
