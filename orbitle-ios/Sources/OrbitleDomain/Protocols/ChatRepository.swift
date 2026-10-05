import Foundation

/// Действия со списком чатов, которые умеет конкретный источник данных.
/// Экран показывает только то, что входит в набор, поэтому без поддержки ядра
/// кнопка просто не появляется.
public struct ChatListCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Закрепить и открепить чат.
    public static let pin = ChatListCapabilities(rawValue: 1 << 0)
    /// Поменять порядок закреплённых.
    public static let reorderPins = ChatListCapabilities(rawValue: 1 << 1)
    /// Пометить прочитанный чат непрочитанным.
    public static let markUnread = ChatListCapabilities(rawValue: 1 << 2)
    /// Выключить и включить уведомления.
    public static let mute = ChatListCapabilities(rawValue: 1 << 3)
    /// Убрать в архив и вернуть.
    public static let archive = ChatListCapabilities(rawValue: 1 << 4)
    /// Удалить чат (для себя или для всех).
    public static let delete = ChatListCapabilities(rawValue: 1 << 5)
    /// Поиск чатов и людей на сервере.
    public static let serverSearch = ChatListCapabilities(rawValue: 1 << 6)
    /// Догрузка следующей страницы списка с сервера.
    public static let paging = ChatListCapabilities(rawValue: 1 << 7)
}

/// Найденный на сервере чат или человек, которого ещё нет в списке.
public struct ChatSearchResult: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String?
    public var type: ChatType
    public var avatarURL: URL?

    public init(id: String, title: String, subtitle: String? = nil, type: ChatType, avatarURL: URL? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.avatarURL = avatarURL
    }
}

/// Участник чата для подсказок `@`.
public struct ChatMemberRef: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Команда бота для подсказок `/`.
public struct BotCommandRef: Hashable, Sendable {
    public var name: String
    public var summary: String

    public init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }
}

/// Сообщение, найденное поиском на сервере по всем чатам.
public struct FoundMessage: Hashable, Sendable {
    public var chatId: String
    public var messageId: String
    public var senderId: String
    public var text: String
    /// `nil` — сервер не прислал время.
    public var date: Date?

    public init(chatId: String, messageId: String, senderId: String = "", text: String, date: Date? = nil) {
        self.chatId = chatId
        self.messageId = messageId
        self.senderId = senderId
        self.text = text
        self.date = date
    }
}

/// Список чатов. Сначала отдаёт кэш, потом обновляет его с сервера.
public protocol ChatRepository: Sendable {
    /// Чаты по убыванию `updatedAt`. Первое значение сразу из кэша.
    func chats() -> AsyncStream<[Chat]>
    /// Обновить список с сервера.
    func refresh() async throws(OrbitleError)
    /// Обновить один чат с сервера.
    func refresh(chatId: String) async throws(OrbitleError)
    /// Сбросить непрочитанные локально и на сервере. При ошибке сервера
    /// локальное изменение остаётся, а ошибка пробрасывается.
    func markAsRead(chatId: String) async throws(OrbitleError)

    /// Что из необязательных действий доступно.
    var capabilities: ChatListCapabilities { get }
    /// Закрепить (`true`) или открепить чат. Новый закреплённый встаёт первым.
    func setPinned(_ pinned: Bool, chatId: String) async throws(OrbitleError)
    /// Новый порядок закреплённых чатов сверху вниз.
    func reorderPinned(_ chatIds: [String]) async throws(OrbitleError)
    /// Ручная пометка «непрочитано». Снимается при открытии чата.
    func setMarkedUnread(_ unread: Bool, chatId: String) async throws(OrbitleError)
    /// Чат снова непрочитан на сервере начиная с сообщения, отправленного в `date`: сервер
    /// ставит отметку прочтения перед ним, пометку видят и другие устройства.
    func markUnread(chatId: String, from date: Date) async throws(OrbitleError)
    func setMuted(_ muted: Bool, chatId: String) async throws(OrbitleError)
    func setArchived(_ archived: Bool, chatId: String) async throws(OrbitleError)
    func delete(chatId: String, forEveryone: Bool) async throws(OrbitleError)
    /// Очистить переписку (`CHAT_CLEAR` 54). Чат остаётся, сообщения пропадают.
    func clearHistory(chatId: String, forEveryone: Bool) async throws(OrbitleError)
    /// Следующая страница списка. `false`, если страниц больше нет.
    func loadMoreChats() async throws(OrbitleError) -> Bool
    func search(query: String) async throws(OrbitleError) -> [ChatSearchResult]
    /// Сообщения во всех чатах по тексту.
    func searchMessages(query: String) async throws(OrbitleError) -> [FoundMessage]
    /// Серверные папки. Пустой массив — папок нет.
    func folders() -> AsyncStream<[ChatFolder]>
    /// Кто сейчас печатает: id чата → id пользователей.
    func typing() -> AsyncStream<[String: [String]]>
    /// Запомнить диалог, которого может не быть в списке: с первым своим сообщением в нём
    /// строка чата появится сразу, не дожидаясь сервера.
    func prepareDialog(_ draft: DialogDraft) async
    /// Новая группа (`MSG_SEND` 64, `chatType: CHAT`). `nil` — в ответе нет чата.
    func createGroup(title: String, memberIds: [String]) async throws(OrbitleError) -> String?
    /// Новый канал: то же тело, `chatType: CHANNEL`, участников нет. `nil` — в ответе нет чата.
    func createChannel(title: String) async throws(OrbitleError) -> String?
    /// Вход по ссылке приглашения (`CHAT_JOIN` 57). `nil` — сервер не вернул чат.
    func joinByLink(_ link: String) async throws(OrbitleError) -> String?
    /// Первая страница участников группы или канала.
    func members(chatId: String) async throws(OrbitleError) -> [ChatMemberRef]
    /// Команды бота. Имена без ведущего слэша.
    func botCommands(botId: String) async throws(OrbitleError) -> [BotCommandRef]
    /// Сигнал личного звонка. `nil` — сервер не вернул адрес. Звук и видео не открываются.
    func signalCall(calleeId: String, isVideo: Bool) async throws(OrbitleError) -> String?
    /// Нажатие inline-кнопки `CALLBACK` бота (опкод 118). Сам ответ бота обычно приходит
    /// сообщением; здесь — короткий текст или адрес, если сервер их прислал.
    func pressButton(chatId: String, messageId: String, callbackId: String, payload: String?) async throws(OrbitleError) -> BotButtonAnswer
}

/// Ответ сервера на нажатие кнопки бота: уведомление и/или адрес для открытия.
public struct BotButtonAnswer: Sendable, Equatable {
    public var text: String?
    public var url: URL?

    public init(text: String? = nil, url: URL? = nil) {
        self.text = text
        self.url = url
    }
}

/// Без поддержки источника необязательные действия недоступны: набор пуст,
/// вызовы отклоняются, потоки отдают пустое значение.
public extension ChatRepository {
    var capabilities: ChatListCapabilities { [] }
    func setPinned(_ pinned: Bool, chatId: String) async throws(OrbitleError) { throw .invalidRequest }
    func reorderPinned(_ chatIds: [String]) async throws(OrbitleError) { throw .invalidRequest }
    func setMarkedUnread(_ unread: Bool, chatId: String) async throws(OrbitleError) { throw .invalidRequest }
    func markUnread(chatId: String, from date: Date) async throws(OrbitleError) { throw .invalidRequest }
    func setMuted(_ muted: Bool, chatId: String) async throws(OrbitleError) { throw .invalidRequest }
    func setArchived(_ archived: Bool, chatId: String) async throws(OrbitleError) { throw .invalidRequest }
    func delete(chatId: String, forEveryone: Bool) async throws(OrbitleError) { throw .invalidRequest }
    func clearHistory(chatId: String, forEveryone: Bool) async throws(OrbitleError) { throw .invalidRequest }
    func loadMoreChats() async throws(OrbitleError) -> Bool { false }
    func search(query: String) async throws(OrbitleError) -> [ChatSearchResult] { [] }
    func searchMessages(query: String) async throws(OrbitleError) -> [FoundMessage] { [] }
    func folders() -> AsyncStream<[ChatFolder]> { AsyncStream { $0.yield([]); $0.finish() } }
    func typing() -> AsyncStream<[String: [String]]> { AsyncStream { $0.yield([:]); $0.finish() } }
    func prepareDialog(_ draft: DialogDraft) async {}
    func createGroup(title: String, memberIds: [String]) async throws(OrbitleError) -> String? { throw .invalidRequest }
    func createChannel(title: String) async throws(OrbitleError) -> String? { throw .invalidRequest }
    func joinByLink(_ link: String) async throws(OrbitleError) -> String? { throw .invalidRequest }
    func members(chatId: String) async throws(OrbitleError) -> [ChatMemberRef] { throw .invalidRequest }
    func botCommands(botId: String) async throws(OrbitleError) -> [BotCommandRef] { throw .invalidRequest }
    func signalCall(calleeId: String, isVideo: Bool) async throws(OrbitleError) -> String? { throw .invalidRequest }
    func pressButton(chatId: String, messageId: String, callbackId: String, payload: String?) async throws(OrbitleError) -> BotButtonAnswer {
        throw .invalidRequest
    }
}

/// Черновики полей ввода. Хранятся только на устройстве.
public protocol ChatDraftStore: Sendable {
    func draft(chatId: String) async -> String?
    /// Пустой текст удаляет черновик.
    func saveDraft(_ text: String, chatId: String) async
}

/// Недавние чаты из поиска, новые первыми.
public protocol RecentSearchStore: Sendable {
    func recent() async -> [String]
    func add(chatId: String) async
    func remove(chatId: String) async
    func clear() async
}
