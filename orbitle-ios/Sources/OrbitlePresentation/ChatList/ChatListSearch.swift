import Foundation
import OrbitleDomain

/// Поиск по списку чатов: сравнение без регистра, диакритики и разницы «е»/«ё».
public enum ChatListSearch {
    /// Насколько хорошо заголовок подходит под запрос. `nil` — не подходит.
    /// 0 — заголовок начинается с запроса, 1 — с него начинается слово, 2 — запрос внутри слова.
    public static func rank(title: String, query: String) -> Int? {
        let needle = normalize(query)
        guard !needle.isEmpty else { return nil }
        let haystack = normalize(title)
        if haystack.hasPrefix(needle) { return 0 }
        let words = haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(needle) }) { return 1 }
        return haystack.contains(needle) ? 2 : nil
    }

    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .lowercased()
    }

    /// Чаты под запрос: лучшие совпадения первыми, внутри — порядок списка.
    public static func match(_ chats: [Chat], query: String, title: (Chat) -> String) -> [Chat] {
        chats.enumerated()
            .compactMap { index, chat in rank(title: title(chat), query: query).map { (chat, $0, index) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
}

/// Что показывает экран поиска.
public struct ChatSearchState: Equatable, Sendable {
    /// Недавние чаты из поиска (при пустом запросе).
    public var recent: [ChatListItem] = []
    /// Совпадения среди своих чатов.
    public var chats: [ChatListItem] = []
    /// Найдено на сервере, в списке этих чатов нет.
    public var global: [ChatSearchResult] = []
    /// Сообщения, найденные на сервере, в порядке ответа.
    public var messages: [ChatSearchMessage] = []
    public var isSearchingServer = false

    public init() {}

    public var isEmpty: Bool { chats.isEmpty && global.isEmpty && messages.isEmpty }
}

/// Строка найденного сообщения: чат, кусок текста одной строкой и время.
public struct ChatSearchMessage: Identifiable, Equatable, Sendable {
    public var id: String { "\(chatId)/\(messageId)" }
    public var chatId: String
    public var messageId: String
    public var chatTitle: String
    public var snippet: String
    /// Пусто, если время неизвестно.
    public var time: String
    /// Время сообщения: чат открывается на нём без отдельного запроса. `nil` — неизвестно.
    public var date: Date?

    public init(chatId: String, messageId: String, chatTitle: String, snippet: String, time: String, date: Date? = nil) {
        self.chatId = chatId
        self.messageId = messageId
        self.chatTitle = chatTitle
        self.snippet = snippet
        self.time = time
        self.date = date
    }

    /// Название чата, которого нет в списке.
    public static let unknownChatTitle = "Чат"
    static let snippetLength = 160

    /// Текст одной строкой и не длиннее строки списка.
    public static func snippet(_ text: String) -> String {
        let line = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard line.count > snippetLength else { return line }
        return String(line.prefix(snippetLength)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
