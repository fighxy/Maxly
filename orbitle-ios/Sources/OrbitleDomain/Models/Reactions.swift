import Foundation

/// Реакции сообщения от сервера: ответ на свою реакцию, загрузка истории, запрос
/// `MSG_GET_REACTIONS` или пуш об изменении (docs/reactions.md).
public struct ReactionUpdate: Equatable, Sendable {
    public struct Counter: Equatable, Sendable {
        public var emoji: String
        public var count: Int

        public init(emoji: String, count: Int) {
            self.emoji = emoji
            self.count = count
        }
    }

    /// В порядке сервера.
    public var counters: [Counter]
    /// Своя реакция. Смотрится, только когда `mineKnown`.
    public var mine: String?
    /// `false`, если сервер не сказал, какая реакция своя: пуш несёт одни счётчики.
    public var mineKnown: Bool

    public init(counters: [Counter], mine: String?, mineKnown: Bool) {
        self.counters = counters
        self.mine = mine
        self.mineKnown = mineKnown
    }

    /// Реакций нет, своей тоже.
    public static let none = ReactionUpdate(counters: [], mine: nil, mineKnown: true)

    /// Реакции после обновления. Неизвестная своя реакция остаётся прежней, пока её счётчик
    /// есть в обновлении. Пустые и повторные счётчики отбрасываются.
    public func applied(to current: [MessageReaction]) -> [MessageReaction] {
        let own = mineKnown ? mine : current.first(where: \.mine)?.emoji
        var seen = Set<String>()
        return counters.compactMap { counter in
            guard counter.count > 0, !counter.emoji.isEmpty, seen.insert(counter.emoji).inserted else { return nil }
            return MessageReaction(emoji: counter.emoji, count: counter.count, mine: counter.emoji == own)
        }
    }
}

extension Array where Element == MessageReaction {
    /// Своя реакция, если есть. У аккаунта она одна на сообщение.
    public var mine: String? { first(where: \.mine)?.emoji }

    /// Всего реакций под сообщением.
    public var total: Int { reduce(0) { $0 + $1.count } }
}

/// Кто поставил реакцию (`MSG_GET_DETAILED_REACTIONS`).
public struct ReactionUser: Hashable, Sendable, Identifiable {
    public var userId: String
    /// Пустое, если профиль не загрузился.
    public var name: String
    public var avatarURL: URL?
    public var emoji: String

    public var id: String { userId }

    public init(userId: String, name: String, avatarURL: URL?, emoji: String) {
        self.userId = userId
        self.name = name
        self.avatarURL = avatarURL
        self.emoji = emoji
    }
}
