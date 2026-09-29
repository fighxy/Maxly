import Foundation

/// Личный диалог, которого ещё может не быть на сервере.
///
/// В Max id личного чата — исключающее «или» id двух собеседников, а отдельного запроса
/// «создать диалог» нет: сервер заводит чат с первым сообщением. Черновик несёт то, что
/// нужно, чтобы показать такой чат до первого сообщения и сразу после него.
public struct DialogDraft: Hashable, Sendable {
    public let chatId: String
    public let peerId: String
    public let title: String
    public let avatarURL: URL?

    public init(chatId: String, peerId: String, title: String, avatarURL: URL? = nil) {
        self.chatId = chatId
        self.peerId = peerId
        self.title = title
        self.avatarURL = avatarURL
    }

    /// Черновик диалога с `peerId` для пользователя `me`. `nil`, если id не числовые.
    public static func with(peerId: String, me: String, title: String, avatarURL: URL? = nil) -> DialogDraft? {
        guard let mine = Int64(me), let other = Int64(peerId), mine != other else { return nil }
        return DialogDraft(chatId: String(mine ^ other), peerId: peerId, title: title, avatarURL: avatarURL)
    }
}
