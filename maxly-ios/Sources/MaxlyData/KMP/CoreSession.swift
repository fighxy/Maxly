import Foundation
import MaxlyDomain

/// Фаза `MaxClient`, как её отдаёт iOS-фасад ядра.
public enum CorePhase: String, Sendable, Equatable {
    case idle
    case connecting
    case awaitingAuth
    case ready
    case reconnecting
    case tokenRejected
    case failed

    public init(raw: String) {
        self = CorePhase(rawValue: raw) ?? .failed
    }
}

/// Классифицированная ошибка ядра. `kind` совпадает с `ErrorKind` (`NETWORK`, `SESSION_EXPIRED`, …).
public struct CoreFailure: Error, Sendable, Equatable {
    public var kind: String
    public var key: String?
    /// Текст сервера для экрана. Пусто — у экрана остаётся своя фраза.
    public var serverText: String?

    public init(kind: String, key: String?, serverText: String? = nil) {
        self.kind = kind
        self.key = key.flatMap { $0.isEmpty ? nil : $0 }
        let trimmed = serverText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.serverText = trimmed.isEmpty ? nil : trimmed
    }
}

public struct CoreCode: Sendable, Equatable {
    public var token: String
    public var codeLength: Int?

    public init(token: String, codeLength: Int?) {
        self.token = token
        self.codeLength = codeLength
    }
}

public enum CoreAuthStep: Sendable, Equatable {
    case loggedIn(userId: String)
    case password(trackId: String, hint: String?)
    case register(token: String)
}

/// Публичный чат или канал из поиска на сервере (`PUBLIC_SEARCH`).
public struct CoreSearchChat: Sendable, Equatable {
    public var id: String
    /// `DIALOG`, `CHAT` или `CHANNEL`.
    public var type: String
    public var title: String
    /// `@ссылка` или текст последнего сообщения. Пусто, если нет ни того, ни другого.
    public var subtitle: String
    public var avatarURL: String
    public var participantsCount: Int

    public init(id: String, type: String, title: String, subtitle: String = "", avatarURL: String = "", participantsCount: Int = 0) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.avatarURL = avatarURL
        self.participantsCount = participantsCount
    }
}

/// Сообщение из поиска на сервере по всем чатам (`CHAT_SEARCH`).
public struct CoreFoundMessage: Sendable, Equatable {
    public var chatId: String
    public var messageId: String
    public var senderId: String
    public var text: String
    /// Мс Unix; 0 — сервер не прислал время.
    public var timeMs: Int64

    public init(chatId: String, messageId: String, senderId: String = "", text: String, timeMs: Int64 = 0) {
        self.chatId = chatId
        self.messageId = messageId
        self.senderId = senderId
        self.text = text
        self.timeMs = timeMs
    }
}

/// Опрос, чей счётчик надо обновить. Id — десятичные строки.
public struct CorePollRef: Sendable, Equatable {
    public var messageId: String
    public var pollId: String
    public init(messageId: String, pollId: String) {
        self.messageId = messageId
        self.pollId = pollId
    }
}

/// Счётчики опроса. `multiple` у обновления 306; у ответа на голос флага нет.
public struct CorePollCounts: Sendable, Equatable {
    public var pollId: String
    public var total: Int
    public var votes: [String: Int]
    public var multiple: Bool
    public init(pollId: String, total: Int, votes: [String: Int], multiple: Bool = false) {
        self.pollId = pollId
        self.total = total
        self.votes = votes
        self.multiple = multiple
    }
}

public struct CoreChat: Sendable, Equatable {
    public var id: String
    public var title: String
    public var type: String
    public var lastMessageId: String
    public var lastText: String
    public var updatedAtMs: Int64
    public var unread: Int
    /// Картинка чата, у диалога — собеседника. Пусто, если её нет.
    public var avatarURL: String
    /// Автор последнего сообщения. Пусто, если неизвестен.
    public var lastAuthorId: String
    /// Вид первого вложения последнего сообщения (`photo`, `voice`, …). Пусто — только текст.
    public var lastMedia: String
    /// Фото или обложка этого вложения. Пусто, если нет.
    public var lastThumbURL: String
    /// Комментарии канала: `1` включены, `0` выключены, `-1` неизвестно.
    public var comments: Int
    /// Можно ли писать: `1` да, `0` нет, `-1` неизвестно.
    public var canWrite: Int
    /// Уведомления выключены: `1` да, `0` нет, `-1` неизвестно.
    public var muted: Int
    /// Имя автора последнего сообщения. Пусто, если неизвестно.
    public var lastAuthorName: String
    /// Последнее сообщение своё: `1` да, `0` нет, `-1` неизвестно.
    public var lastFromMe: Int
    /// Последнее сообщение — пересылка (текст и вложение — пересланного).
    public var lastForwarded: Bool
    /// Отметка прочтения других участников, мс: свои сообщения до неё прочитаны. `0` — неизвестно.
    public var peerReadMs: Int64
    /// Аккаунт участвует в чате (`status` пуст или `ACTIVE`). Покинутые и закрытые — `false`.
    public var active: Bool
    /// Серверное время последнего сообщения, мс. `0` — сообщений нет или ядро не сказало.
    /// В отличие от `updatedAtMs` (его двигают и правки, и реакции) с ним сравниваются отметки.
    public var lastTimeMs: Int64
    /// Диалог с ботом, у которого есть мини-приложение (ядро знает его опции). `false` у групп,
    /// каналов, людей и бота, о котором ядро ещё ничего не загрузило.
    public var hasWebApp: Bool

    public init(
        id: String, title: String, type: String, lastMessageId: String, lastText: String, updatedAtMs: Int64, unread: Int,
        avatarURL: String = "", lastAuthorId: String = "", lastMedia: String = "", lastThumbURL: String = "", comments: Int = -1,
        canWrite: Int = -1, muted: Int = -1, lastAuthorName: String = "", lastFromMe: Int = -1, lastForwarded: Bool = false,
        peerReadMs: Int64 = 0, active: Bool = true, lastTimeMs: Int64 = 0, hasWebApp: Bool = false
    ) {
        self.hasWebApp = hasWebApp
        self.active = active
        self.lastTimeMs = lastTimeMs
        self.id = id
        self.title = title
        self.type = type
        self.lastMessageId = lastMessageId
        self.lastText = lastText
        self.updatedAtMs = updatedAtMs
        self.unread = unread
        self.avatarURL = avatarURL
        self.lastAuthorId = lastAuthorId
        self.lastMedia = lastMedia
        self.lastThumbURL = lastThumbURL
        self.comments = comments
        self.canWrite = canWrite
        self.muted = muted
        self.lastAuthorName = lastAuthorName
        self.lastFromMe = lastFromMe
        self.lastForwarded = lastForwarded
        self.peerReadMs = peerReadMs
    }
}

/// Ответ сервера на свою отметку прочтения (`CHAT_MARK`).
public struct CoreReadMark: Sendable, Equatable {
    /// Непрочитанных в чате по мнению сервера. `-1` — неизвестно.
    public var unread: Int
    /// Отметка, которую сохранил сервер, мс. `0` — неизвестно.
    public var mark: Int64

    public init(unread: Int, mark: Int64) {
        self.unread = unread
        self.mark = mark
    }
}

/// Контакт из списка аккаунта (`contacts` ответа `LOGIN`).
public struct CoreContact: Sendable, Equatable {
    public var id: String
    public var firstName: String
    public var lastName: String
    /// Цифры без `+`, пусто, если номер скрыт.
    public var phone: String
    public var avatarURL: String
    /// Последний визит, мс Unix; 0 — неизвестно.
    public var lastSeenMs: Int64
    public var online: Bool
    /// `accountStatus`. `nil` или 0 — аккаунт жив. Другое значение — удалён и в список не входит.
    public var accountStatus: Int?
    public var isBot: Bool
    public var isOfficial: Bool
    public var isServiceAccount: Bool
    /// Код статуса (`-1` неизвестно, `0` не в сети, `1` в сети, `2` недавно, `3` давно).
    public var presence: Int

    public init(
        id: String, firstName: String, lastName: String, phone: String, avatarURL: String, lastSeenMs: Int64, online: Bool,
        accountStatus: Int? = nil, isBot: Bool = false, isOfficial: Bool = false, isServiceAccount: Bool = false, presence: Int = -1
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.avatarURL = avatarURL
        self.lastSeenMs = lastSeenMs
        self.online = online
        self.accountStatus = accountStatus
        self.isBot = isBot
        self.isOfficial = isOfficial
        self.isServiceAccount = isServiceAccount
        self.presence = presence
    }
}

/// Карточка чата из ядра (`loadProfile`). Пустые строки и нули — «нет данных».
public struct CoreProfile: Sendable, Equatable {
    public struct Command: Sendable, Equatable {
        public var name: String
        public var description: String

        public init(name: String, description: String) {
            self.name = name
            self.description = description
        }
    }

    /// `user`, `bot`, `group`, `channel` или `saved`.
    public var kind: String
    public var chatId: String
    public var peerId: String
    public var title: String
    public var avatarURL: String
    public var description: String
    public var link: String
    /// Цифры без `+`.
    public var phone: String
    public var participants: Int
    public var lastSeenMs: Int64
    public var online: Bool
    public var official: Bool
    public var isPublic: Bool
    public var commands: [Command]
    /// Бот с мини-приложением (кнопка «Открыть приложение»).
    public var hasWebApp: Bool
    /// Опция канала `COMMENTS`: `nil`, если карточка не сказала.
    public var commentsEnabled: Bool?
    /// Код статуса человека (`-1` неизвестно или не человек, `0`–`3` как у `CorePresence`).
    public var presence: Int

    public init(
        kind: String, chatId: String, peerId: String = "", title: String = "", avatarURL: String = "",
        description: String = "", link: String = "", phone: String = "", participants: Int = 0,
        lastSeenMs: Int64 = 0, online: Bool = false, official: Bool = false, isPublic: Bool = false,
        commands: [Command] = [], hasWebApp: Bool = false, commentsEnabled: Bool? = nil, presence: Int = -1
    ) {
        self.kind = kind
        self.chatId = chatId
        self.peerId = peerId
        self.title = title
        self.avatarURL = avatarURL
        self.description = description
        self.link = link
        self.phone = phone
        self.participants = participants
        self.lastSeenMs = lastSeenMs
        self.online = online
        self.official = official
        self.isPublic = isPublic
        self.commands = commands
        self.hasWebApp = hasWebApp
        self.commentsEnabled = commentsEnabled
        self.presence = presence
    }
}

/// Ответ на нажатие inline-кнопки бота: пустые строки — сервер их не прислал.
public struct CoreButtonAnswer: Sendable, Equatable {
    public var text: String
    public var url: String

    public init(text: String = "", url: String = "") {
        self.text = text
        self.url = url
    }
}

/// Звонок из журнала (`VIDEO_CHAT_HISTORY`).
public struct CoreCall: Sendable, Equatable {
    public var id: String
    /// Пусто, если сервер не прислал чат.
    public var chatId: String
    /// Пусто у группового звонка.
    public var peerId: String
    public var title: String
    public var avatarURL: String
    public var isGroup: Bool
    public var outgoing: Bool
    public var missed: Bool
    public var video: Bool
    /// `HUNGUP`, `CANCELED`, `REJECTED`, `MISSED`…
    public var hangupType: String
    /// Длительность как её прислал сервер; 0 — не ответили.
    public var duration: Int64
    public var timeMs: Int64

    public init(
        id: String, chatId: String, peerId: String, title: String, avatarURL: String, isGroup: Bool,
        outgoing: Bool, missed: Bool, video: Bool, hangupType: String, duration: Int64, timeMs: Int64
    ) {
        self.id = id
        self.chatId = chatId
        self.peerId = peerId
        self.title = title
        self.avatarURL = avatarURL
        self.isGroup = isGroup
        self.outgoing = outgoing
        self.missed = missed
        self.video = video
        self.hangupType = hangupType
        self.duration = duration
        self.timeMs = timeMs
    }
}

public struct CoreMessage: Sendable, Equatable {
    public var id: String
    public var chatId: String
    public var authorId: String
    public var text: String
    public var timeMs: Int64
    /// Фрагмент вложений и реакций. Пустая строка значит, что фасад его не прислал.
    public var contentJSON: String
    public var authorName: String
    public var authorAvatarURL: String
    /// Реакции сообщения (`{counters, totalCount, yourReaction}`, docs/reactions.md). Пустая
    /// строка — источник мог их не прислать (ответ на правку), прежние остаются.
    public var reactionsJSON: String
    /// Время последней правки (`updateTime`, мс). `0` — не правили.
    public var updateTimeMs: Int64

    public init(
        id: String,
        chatId: String,
        authorId: String,
        text: String,
        timeMs: Int64,
        contentJSON: String = "",
        authorName: String = "",
        authorAvatarURL: String = "",
        reactionsJSON: String = "",
        updateTimeMs: Int64 = 0
    ) {
        self.id = id
        self.chatId = chatId
        self.authorId = authorId
        self.text = text
        self.timeMs = timeMs
        self.contentJSON = contentJSON
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.reactionsJSON = reactionsJSON
        self.updateTimeMs = updateTimeMs
    }
}

/// Локальный файл для `MaxCore.sendMedia`. `kind` — `photo`, `video` или `file`.
public struct CoreOutgoingMedia: Sendable, Equatable {
    public var path: String
    public var kind: String
    /// Имя, которое увидит получатель. Пусто — последний компонент пути.
    public var fileName: String

    public init(path: String, kind: String, fileName: String) {
        self.path = path
        self.kind = kind
        self.fileName = fileName
    }
}

/// Пуш, который клиент пишет в базу. Звонки, присутствие и неизвестные опкоды сюда не входят.
public struct CoreEvent: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case message
        case edited
        case deleted
        case chat
        /// `authorId` печатает в `chatId`. `text` — тип действия пуша 129 (`TEXT`, `STICKER`…),
        /// пусто — мост его не передал, это обычный набор текста.
        case typing
        case read
        /// Изменились реакции сообщения `messageId`, сами они в `reactionsJSON`.
        case reactions
        /// Сервер расшифровал голосовое `messageId`: текст в `text`, статус в `unread`
        /// (`1` готово, `0` ещё идёт).
        case transcription
        /// Аккаунт больше не участвует в чате `chatId` (вышел, чат закрыт): чат уходит из списка.
        case chatGone
        /// Сменился звук чата `chatId` (пуш `NOTIF_CONFIG` 134, свой `setChatMuted`, вход):
        /// `muted` `1` без звука, `0` со звуком, `-1` неизвестно; `timeMs` — сырой
        /// `dontDisturbUntil` (`-1` насовсем, иначе конец в мс, `0` — со звуком или неизвестно).
        case chatMute
        /// Конфиг аккаунта стал известен или пропал (вход, выход): звук известных чатов
        /// перечитывается (`isChatMuted`).
        case config
        /// Черновик сервера чата `chatId` изменился (другое устройство, пуши 152/153, вход,
        /// отправка): сам он в `draft`, `nil` — черновика больше нет.
        case draft
        /// Статус человека `authorId` изменился: код в `presence`, время визита (мс) в `timeMs`.
        case presence
        /// Режим призрака включили или выключили (`setGhostMode`): `text` — `on` или `off`.
        /// Приходит и без входа в аккаунт.
        case ghostMode
        /// «Не отправлять отметки о прочтении» (`setHideReadReceipts`): `text` — `on` или `off`.
        case hideReadReceipts
        /// Закрепы чата (`NOTIF_CHAT_MESSAGE_PINNED` 243). `text` — `pin`, `unpin` или `unpinAll`.
        /// `messageId` — сообщение, `unread` — сколько закрепов осталось (`-1` неизвестно).
        /// В базу не пишется: плашку обновляет открытый чат.
        case pinned
        /// Отложенное сообщение (`created`, `edited`, `deleted`, `fired` в `text`).
        /// В базу не пишется: список перечитывает открытый чат.
        case scheduled
        /// Журнал звонков изменился (`NOTIF_CALL_HISTORY` 165): `text` — `add` или `remove`,
        /// `messageId` — `historyId` записи (пусто — пуш без записей, журнал перечитывается).
        case callLog
        /// Сервер не принял загрузку (`NOTIF_ATTACH` 136 с `error`): ошибка в `text`, id вложения
        /// в `messageId`, вид (`file`, `video`, `audio`) в `title`; пусто, если пуш их не назвал.
        case attachError
    }

    public var kind: Kind
    public var chatId: String
    public var messageId: String
    public var authorId: String
    public var text: String
    public var title: String
    public var chatType: String
    public var timeMs: Int64
    /// `-1`, если событие не меняет счётчик непрочитанных.
    public var unread: Int
    /// Фрагмент вложений. Пустая строка — пуш его не принёс.
    public var contentJSON: String
    public var authorName: String
    public var authorAvatarURL: String
    /// Реакции: у `message` и `reactions`. У `reactions` без ключа `yourReaction`, если своя
    /// реакция неизвестна. Пустая строка у `edited`: правка реакции не меняет.
    public var reactionsJSON: String
    /// Время правки сообщения у `message` и `edited` (мс). `0` — не правили или пуш его не нёс.
    public var updateTimeMs: Int64
    /// Звук у `chatMute`: `1` без звука, `0` со звуком, `-1` неизвестно (у остальных `-1`).
    public var muted: Int
    /// Черновик у `draft`; `nil` — его стёрли или отправили.
    public var draft: CoreDraft?
    /// Код статуса у `presence` (`-1` у остальных).
    public var presence: Int

    public init(
        kind: Kind,
        chatId: String,
        messageId: String,
        authorId: String,
        text: String,
        title: String,
        chatType: String,
        timeMs: Int64,
        unread: Int,
        contentJSON: String = "",
        authorName: String = "",
        authorAvatarURL: String = "",
        reactionsJSON: String = "",
        updateTimeMs: Int64 = 0,
        muted: Int = -1,
        draft: CoreDraft? = nil,
        presence: Int = -1
    ) {
        self.kind = kind
        self.chatId = chatId
        self.messageId = messageId
        self.authorId = authorId
        self.text = text
        self.title = title
        self.chatType = chatType
        self.timeMs = timeMs
        self.unread = unread
        self.contentJSON = contentJSON
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.reactionsJSON = reactionsJSON
        self.updateTimeMs = updateTimeMs
        self.muted = muted
        self.draft = draft
        self.presence = presence
    }
}

/// Узкий вход в maxly-core. Реализация с `import MaxlyCore` живёт в приложении, тесты подставляют фейк.
public protocol MaxCore: Sendable {
    func phaseName() async -> CorePhase
    func currentUserId() async -> String
    func hasStoredToken() async -> Bool
    /// Почему ядро отклонило вход. `nil`, пока фазы `tokenRejected` нет.
    func loginRejection() async -> CoreLoginRejection?
    /// Opcode 203. Пустой список — нечего обновлять.
    func refreshPhotoURLs(_ items: [PhotoRefreshKey]) async throws -> [RefreshedPhotoURL]
    func start() async throws -> CorePhase
    func requestCode(phone: String, resend: Bool) async throws -> CoreCode
    func verifyCode(token: String, code: String) async throws -> CoreAuthStep
    func checkPassword(trackId: String, password: String) async throws -> CoreAuthStep
    func register(token: String, firstName: String, lastName: String) async throws -> CoreAuthStep
    func logout() async throws
    func loadChats() async throws -> [CoreChat]
    /// Как `loadChats`, плюс `complete`: ответ — весь список аккаунта с сервера (первый после
    /// входа). Тогда чаты, которых в нём нет, аккаунт покинул.
    func loadChatList() async throws -> (chats: [CoreChat], complete: Bool)
    func loadChat(id: String) async throws -> CoreChat
    func loadHistory(chatId: String, beforeMs: Int64, limit: Int) async throws -> [CoreMessage]
    /// Страница старше `beforeMs`, которую ждёт листающий вверх пользователь: как `loadHistory`,
    /// но не ждёт паузы фоновых чтений после `too.many.requests`.
    func loadOlderHistory(chatId: String, beforeMs: Int64, limit: Int) async throws -> [CoreMessage]
    /// Самая свежая страница чата, который пользователь только что открыл. Не ждёт паузы после
    /// `too.many.requests` (её ждут фоновые чтения), но отказ сервера её продлевает.
    func loadOpenedHistory(chatId: String, limit: Int) async throws -> [CoreMessage]
    /// Сплошная страница вокруг сообщения `messageId` или, если `fromMs` больше нуля, вокруг
    /// этого момента (`CHAT_HISTORY` с `forward`), от старых к новым. В стор ядра не пишется.
    func loadHistoryAround(chatId: String, messageId: String, fromMs: Int64, forward: Int, backward: Int) async throws -> [CoreMessage]
    /// Сообщения с вложениями `attachTypes` вокруг `anchorId` с сервера (`CHAT_MEDIA`).
    func loadSharedMedia(chatId: String, anchorId: String, attachTypes: [String], forward: Int, backward: Int) async throws -> [CoreMessage]
    func sendText(chatId: String, text: String) async throws -> CoreMessage
    /// Ответ: `replyTo` — серверный id сообщения, на которое отвечают.
    func sendText(chatId: String, text: String, replyTo: String) async throws -> CoreMessage
    /// Комментарии поста канала старше `beforeMs` (самые новые при `0`), от старых к новым.
    func loadComments(chatId: String, postId: String, beforeMs: Int64, limit: Int) async throws -> [CoreMessage]
    func sendComment(chatId: String, postId: String, text: String) async throws -> CoreMessage
    /// Заменить текст отправленного сообщения. Возвращает сообщение после правки.
    func editMessage(chatId: String, messageId: String, text: String) async throws -> CoreMessage
    /// Удалить сообщения у себя (`forEveryone == false`) или у всех.
    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async throws
    /// Переслать сообщение в другой чат. Возвращает новое сообщение в целевом чате.
    func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async throws -> CoreMessage
    /// Число комментариев под постами канала: id поста → число. Посты без ответа сервера пропущены.
    func loadCommentCounts(chatId: String, postIds: [String]) async throws -> [String: Int]
    func markRead(chatId: String, messageId: String) async throws
    /// Прочитать чат до сообщения `messageId` с отметкой `mark` — серверным временем этого
    /// сообщения (мс), а не часами устройства. `0` — время неизвестно, его ищет ядро.
    /// Ответ — счётчик непрочитанных и отметка сервера.
    func markRead(chatId: String, messageId: String, mark: Int64) async throws -> CoreReadMark
    /// Чат снова непрочитан начиная с сообщения, отправленного в `mark` (мс). Ответ — число
    /// непрочитанных на сервере.
    func markUnread(chatId: String, mark: Int64) async throws -> Int
    /// Поставить свою реакцию `emoji` или снять её (пустая строка). Непустой `postId` —
    /// комментарий этого поста. Ответ — реакции сервера (`reactionsJSON`) или пустая строка.
    func setReaction(chatId: String, messageId: String, postId: String, emoji: String) async throws -> String
    /// Реакции сообщений: id → `reactionsJSON`. Сообщения, о которых сервер промолчал, пропущены.
    func loadReactions(chatId: String, messageIds: [String]) async throws -> [String: String]
    /// Эмодзи каталога реакций сервера, в его порядке.
    func loadReactionCatalog() async throws -> [String]
    /// Кто поставил реакции на сообщение.
    func loadReactionUsers(chatId: String, messageId: String) async throws -> [ReactionUser]
    /// «Кем прочитано» (`MaxIosClient.loadMessageReaders`): отреагировавшие, затем прочитавшие,
    /// без себя и автора. Пусто, если в чате списка нет. Ядро каждый раз обновляет отметки чата.
    func loadMessageReaders(chatId: String, messageId: String) async throws -> [MessageReader]
    /// Есть ли в чате «Кем прочитано» (`MaxIosClient.isReadersAvailable`) — по сохранённой
    /// карточке, без запроса.
    func isReadersAvailable(chatId: String) -> Bool
    /// Расшифровка голосового (`AUDIO_TRANSCRIPTION` 202). `audioId` — id вложения.
    func transcribeVoice(chatId: String, messageId: String, audioId: String) async throws -> CoreTranscription
    /// Выключить уведомления чата насовсем или включить обратно (`CONFIG`, `dontDisturbUntil`).
    func setChatMuted(chatId: String, muted: Bool) async throws
    /// Выключить звук до `untilMs` (мс Unix), насовсем (`-1`) или включить (`0`).
    func setChatMuteUntil(chatId: String, untilMs: Int64) async throws
    /// Звук чата по конфигу ядра, без запроса: `1` без звука, `0` со звуком, `-1` неизвестно.
    func isChatMuted(chatId: String) async -> Int
    /// Сырой `dontDisturbUntil` чата: `0` со звуком, `-1` насовсем, иначе конец в мс;
    /// `Int64.min` — неизвестно.
    func chatMuteUntil(chatId: String) async -> Int64
    /// User-Agent сессии для CDN: адреса видео и файлов выданы под Android-клиента.
    func mediaUserAgent() -> String?
    /// «Я печатаю» (`MSG_TYPING` 65): кадр уходит сразу, ответа нет, ошибки не возвращаются —
    /// пропущенный сигнал ничего не стоит. `postId` — комментарий к посту, пусто — чат.
    func sendTyping(chatId: String, type: String, postId: String)
    func phases() -> AsyncStream<CorePhase>
    func events() -> AsyncStream<CoreEvent>
    func loadContacts() async throws -> [CoreContact]
    func loadCallHistory() async throws -> [CoreCall]
    /// Журнал звонков по курсору (`CALL_HISTORY` 163): пусто или `0` — первая страница, дальше
    /// `sync` прошлого ответа. Ответ с `reset` заменяет журнал.
    func callHistory(sync: String) async throws -> CallLogPage
    /// Отклонить входящий (`VIDEO_CHAT_HANGUP` 167). Пустой `reason` — `REJECTED`, пустой `peerId`
    /// не уходит. Ошибка — сервер не принял отбой.
    func rejectIncomingCall(conversationId: String, peerId: String, reason: String) async throws
    func loadProfile(chatId: String) async throws -> CoreProfile
    /// Задать закреплённые чаты сервера целиком, сверху вниз (`FOLDERS_UPDATE`, поле `favorites`
    /// папки «Все чаты»). Закрепить, открепить и переставить — это один и тот же вызов.
    /// Возвращает список, который подтвердил сервер. При ошибке ядро оставляет прежний список.
    /// Прямой адрес видео (`kind` = `video`, `VIDEO_PLAY`) или файла (`file`, `FILE_DOWNLOAD`)
    /// сообщения. `attachmentId` — `videoId` или `fileId` вложения.
    func mediaLink(chatId: String, messageId: String, kind: String, attachmentId: String) async throws -> String
    /// Загрузить файлы по порядку и отправить одним сообщением с подписью (пустая — без неё).
    /// `progress` получает долю 0…1 всей пачки не с главного потока. Отмена задачи
    /// останавливает загрузку, тогда бросается `CANCELLED`, и ничего не отправляется.
    func sendMedia(chatId: String, items: [CoreOutgoingMedia], caption: String, replyTo: String,
                   progress: @escaping @Sendable (Double) -> Void) async throws -> CoreMessage
    /// Карточка пользователя MAX `contactId` (`{_type: CONTACT, contactId}`).
    func sendContact(chatId: String, contactId: String, replyTo: String) async throws -> CoreMessage
    /// Записанное голосовое (`kind` = `voice`, Ogg/Opus, `wave` — уровни 0…255) или кружок
    /// (`videoNote`, квадратный MP4): загрузка и одно сообщение. Отмена — как у `sendMedia`.
    func sendRecording(chatId: String, path: String, kind: String, durationMs: Int64, wave: [Int], replyTo: String,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> CoreMessage
    func setPinnedChats(_ chatIds: [String]) async throws -> [String]
    /// Закреплённые чаты сервера сверху вниз: сразу при подписке, если уже известны, и после
    /// каждого изменения (вход, свой вызов, пуш с другого устройства). Пока список неизвестен,
    /// поток молчит, поэтому пустой массив всегда значит «ничего не закреплено».
    func pinnedChats() -> AsyncStream<[String]>

    // MARK: Настройки аккаунта (docs/settings.md)

    func loadMyProfile() async throws -> MyProfile
    func updateProfile(firstName: String, lastName: String, about: String) async throws -> MyProfile
    func uploadAvatar(jpeg: Data) async throws -> MyProfile
    func removeAvatar() async throws -> MyProfile
    /// Мс Unix момента удаления, 0 — сервер не назвал.
    func deleteAccount() async throws -> Int64
    /// Публичные чаты и каналы по запросу, страница `from`..`from + count`.
    func searchPublic(query: String, from: Int, count: Int) async throws -> [CoreSearchChat]
    /// Сообщения во всех чатах по тексту, не больше `count`.
    func searchMessages(query: String, count: Int) async throws -> [CoreFoundMessage]
    /// Настройки сейчас и после каждого изменения.
    func accountSettings() -> AsyncStream<AccountSettings>
    func setPhonePrivacy(_ access: PrivacyAccess) async throws -> AccountSettings
    func setOnlineHidden(_ hidden: Bool) async throws -> AccountSettings
    func setSafeMode(_ enabled: Bool) async throws -> AccountSettings
    func setInactiveTTL(_ ttl: InactiveTTL) async throws -> AccountSettings
    func setQuickReaction(_ emoji: String) async throws -> AccountSettings
    func loadSessions() async throws -> [DeviceSession]
    func closeOtherSessions() async throws
    func approveQrLogin(_ link: String) async throws
    func loadBlockedUsers() async throws -> [BlockedUser]
    func unblockUser(_ userId: String) async throws
    func blockUser(_ userId: String) async throws
    /// Общие чаты с пользователем (`CHAT_SEARCH_COMMON_PARTICIPANTS` 198).
    func commonChats(userId: String) async throws -> [CommonChat]
    /// Причины жалобы для типа (`COMPLAIN_REASONS_GET` 162): `2` — канал, `6` — человек.
    func complaintReasons(typeId: Int) async throws -> [ComplaintReason]
    /// Жалоба (`COMPLAIN` 161). `true` — сервер принял.
    func sendComplaint(reasonId: Int, typeId: Int, ids: [String]) async throws -> Bool
    func syncContacts() async throws -> [CoreContact]
    func loadTwoFactor() async throws -> TwoFactorStatus
    func startEmailChange(password: String) async throws -> String
    func sendEmailCode(trackId: String, email: String) async throws -> Int
    func confirmEmail(trackId: String, code: String) async throws -> TwoFactorStatus
    func launchMiniApp(_ kind: MiniApp.Kind) async throws -> MiniApp
    func miniAppCallback(url: String) async throws -> MiniApp
    /// Папки сервера: сразу, если уже известны, и после каждого изменения.
    func folders() -> AsyncStream<[ServerFolder]>
    func loadFolders() async throws -> [ServerFolder]
    func createFolder(title: String, chatIds: [String], filters: [String]) async throws
    func renameFolder(_ folderId: String, title: String) async throws
    func setFolderChats(_ folderId: String, chatIds: [String]) async throws
    func deleteFolder(_ folderId: String) async throws
    func reorderFolders(_ order: [String]) async throws
    /// Стикер каталога `stickerId` (`{_type: STICKER, stickerId}`).
    func sendSticker(chatId: String, stickerId: String, replyTo: String) async throws -> CoreMessage
    /// Текст с анимодзи: каждая отметка — `ANIMOJI` поверх эмодзи (смещения UTF-16).
    func sendText(chatId: String, text: String, replyTo: String, animoji: [CoreAnimojiMark]) async throws -> CoreMessage
    /// Наборы стикеров (свои первыми) и недавние стикеры.
    func loadStickerCatalog() async throws -> StickerCatalog
    func loadStickers(ids: [String]) async throws -> [Sticker]
    /// Анимодзи сервера с Lottie, в его порядке.
    func loadAnimatedEmoji() async throws -> [AnimatedEmoji]
    /// Человек по номеру (`CONTACT_INFO_BY_PHONE` 46). Телефон — `+` и цифры. В контакты не добавляет.
    func findByPhone(phone: String) async throws -> CoreContact
    /// Контакт (`CONTACT_UPDATE` 34, `{contactId, action: ADD}`). Пустое имя на сервер не уходит.
    func addContact(userId: String, firstName: String) async throws -> CoreContact
    /// Группа (`MSG_SEND` 64, `chatType: CHAT`). `nil` — в ответе нет чата.
    func createGroup(title: String, memberIds: [String]) async throws -> CoreChat?
    /// Канал: то же `MSG_SEND` 64, `chatType: CHANNEL`, без участников. `nil` — в ответе нет чата.
    func createChannel(title: String) async throws -> CoreChat?
    /// Вход по ссылке (`CHAT_JOIN` 57).
    func joinByLink(_ link: String) async throws -> CoreChat
    /// Удалить чат (`CHAT_DELETE` 52).
    func deleteChat(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async throws
    /// Выйти из группы или отписаться от канала (`CHAT_LEAVE` 58).
    func leaveChat(chatId: String) async throws
    /// Очистить переписку (`CHAT_CLEAR` 54).
    func clearHistory(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async throws
    /// Текст с анимодзи и упоминаниями. Смещения UTF-16 по `text`.
    func sendRichText(chatId: String, text: String, replyTo: String, animoji: [CoreAnimojiMark], mentions: [CoreMentionMark]) async throws -> CoreMessage
    /// Закрепить сообщение. `messageId` `0` снимает закреп (`CHAT_UPDATE` 55). Один закреп.
    func pinMessage(chatId: String, messageId: String) async throws
    /// Закреплённые сообщения чата (`PINNED_MESSAGES_GET` 241), от старых к новым.
    /// Пустой `from` и `backward` меньше нуля на сервер не уходят.
    func pinnedMessages(chatId: String, from: String, backward: Int) async throws -> [CoreMessage]
    /// `pin`, `unpin` или `unpinAll` (`PINNED_MESSAGE_UPDATE` 242).
    /// `forMe` уходит только когда true, `notify` — только когда false.
    func updatePinned(chatId: String, action: String, messageIds: [String], forMe: Bool, notify: Bool) async throws
    func scheduleMessage(chatId: String, text: String, sendAtMs: Int64) async throws
    func scheduledMessages(chatId: String) async throws -> [CoreFoundMessage]
    func sendPoll(chatId: String, title: String, answers: [String]) async throws -> CoreMessage
    func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async throws
    /// Несколько ответов одного опроса (`SEND_VOTE` 304).
    func castPollVotes(chatId: String, messageId: String, pollId: String, answerIds: [String]) async throws -> CorePollCounts
    /// Счётчики видимых опросов (`GET_POLL_UPDATES` 306). Пуша со счётом нет.
    func pollUpdates(chatId: String, polls: [CorePollRef]) async throws -> [CorePollCounts]
    func editScheduled(chatId: String, messageId: String, text: String, sendAtMs: Int64) async throws -> CoreFoundMessage
    func cancelScheduled(chatId: String, messageIds: [String]) async throws
    func searchInChat(chatId: String, query: String) async throws -> [CoreFoundMessage]
    func chatMembers(chatId: String) async throws -> [CoreChatMember]
    func botCommands(botId: String) async throws -> [CoreBotCommand]
    /// Нажатие inline-кнопки `CALLBACK` (`MSG_SEND_CALLBACK` 118). Пустой `payload` не уходит.
    func pressButton(chatId: String, messageId: String, callbackId: String, payload: String) async throws -> CoreButtonAnswer
    /// Мини-приложение бота (`WEB_APP_INIT_DATA` 160). Пустые `chatId` и `startParam` не уходят.
    func launchBotApp(botId: String, chatId: String, startParam: String) async throws -> MiniApp
    /// Позвонить пользователю (`VIDEO_CHAT_START_ACTIVE` 78): адрес ws2 и свой номер в звонке.
    func startCall(calleeId: String, isVideo: Bool) async throws -> CoreCallStart
    /// Войти в звонок по ссылке (`VIDEO_CHAT_JOIN_BY_LINK` 166).
    func joinCall(link: String, isVideo: Bool) async throws -> CoreCallStart
    /// Новый групповой звонок со ссылкой (`VIDEO_CHAT_START` 76).
    func createCallLink() async throws -> CoreCallLink
    /// Что за звонок за ссылкой (`LINK_INFO` 89); `nil` — ссылка не в звонок.
    func callLinkInfo(link: String) async throws -> CoreCallLinkInfo?
    /// Удалить звонки журнала на сервере (`VIDEO_CHAT_DELETE_HISTORY` 164).
    func deleteCallHistory(ids: [String]) async throws
    /// Входящие звонки (`NOTIF_CALL_START` 137) с разобранным `vcp`.
    func incomingCalls() -> AsyncStream<CoreIncomingCall>
    func enablePassword(password: String, hint: String) async throws
    func changePassword(oldPassword: String, newPassword: String) async throws
    func disablePassword(password: String) async throws

    // MARK: Истории (схема Komet feature/FullStack)

    /// Лента историй (`STORIES_LIST` 208): по кольцу на владельца, пустые не входят.
    func loadStoriesFeed() async throws -> [StoryRing]
    /// Истории владельца (`STORIES_GET_BY_OWNER_ID` 210), от старых к новым, и его свежее кольцо.
    func loadOwnerStories(owner: StoryOwner) async throws -> OwnerStories
    /// История просмотрена (`STORIES_MARK` 214).
    func markStorySeen(owner: StoryOwner, storyId: String) async throws
    /// Своя история на сутки: слот загрузки, загрузка, `STORIES_SEND` 215. `audience` — `1` всем,
    /// `2` контактам. Ответ — своё кольцо и опубликованные истории. Отмена — как у `sendMedia`.
    func publishStory(path: String, isVideo: Bool, durationMs: Int64, audience: Int,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> OwnerStories
    /// Удалить свои истории (`STORIES_DELETE` 218).
    func deleteStories(ids: [String]) async throws
    /// Архив своих историй (`STORIES_HISTORY_GET_BY_OWNER_ID` 219), 30 на страницу. Пустой
    /// `marker` — первая страница; пустой `marker` ответа — страниц больше нет.
    func ownStoryArchive(marker: String) async throws -> StoryArchivePage
    /// Пуши колец (`NOTIF_STORIES_UPDATE` 216). Пустое кольцо — историй у владельца не осталось.
    func storyUpdates() -> AsyncStream<StoryRing>

    // MARK: Разметка, выбор, черновики, участники и контакты (CoreMessageTools.swift)

    /// Текст с разметкой (`MSG_SEND` 64 с `elements`). `elementsJSON` — массив элементов
    /// сервера `{type, from, length, entityId?, attributes?}`, смещения UTF-16 по `text`.
    func sendFormattedText(chatId: String, text: String, elementsJSON: String, replyTo: String) async throws -> CoreMessage
    /// Правка текста и всей разметки (`MSG_EDIT` 67). `[]` снимает разметку.
    func editMessage(chatId: String, messageId: String, text: String, elementsJSON: String) async throws -> CoreMessage
    /// Удалить выбранное одним `MSG_DELETE` 66. Ответ — какие id сервер удалил и какие нет.
    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool, postId: String) async throws -> CoreDeleteResult
    /// Черновик на сервере (`DRAFT_SAVE` 176). Ответ — время черновика на сервере.
    func saveDraft(chatId: String, text: String, elementsJSON: String, replyTo: String) async throws -> Int64
    /// Убрать черновик (`DRAFT_DISCARD` 177). `time` 0 — время сохранённого в ядре.
    func discardDraft(chatId: String, time: Int64) async throws
    /// Черновики сервера, которые держит ядро (из `LOGIN` и `saveDraft`), новые первыми.
    func serverDrafts() async -> [CoreDraft]
    /// Переименовать контакт (`CONTACT_UPDATE` 34, `UPDATE`). Имя до 64 символов.
    func renameContact(userId: String, firstName: String, lastName: String) async throws -> CoreContact
    /// Удалить контакт (`CONTACT_UPDATE` 34, `REMOVE`). Чат с человеком остаётся.
    func removeContact(userId: String) async throws -> CoreContact?
    /// Контакт по номеру (`CONTACT_ADD_BY_PHONE` 41). Ответ — контакт и новый ли он.
    func addContactByPhone(phone: String, firstName: String, lastName: String) async throws -> CoreAddedContact
    /// Адресная книга устройства для имён: заменяет прежнюю целиком, на сервер не уходит.
    func setAddressBook(_ entries: [CorePhoneContact]) async
    /// Правило имён ядра: `true` (по умолчанию) — имя из адресной книги важнее своего имени
    /// контакта, `false` — наоборот. Ядро помнит его до перезапуска: задаётся при старте.
    func setPreferAddressBookNames(_ prefer: Bool) async
    /// Страница участников с ролями (`CHAT_MEMBERS` 59). Пустой `marker` — с начала;
    /// пустой `nextMarker` ответа — страниц больше нет.
    func loadChatMembers(chatId: String, marker: String, count: Int) async throws -> CoreMembersPage
    /// Поиск участников по имени (`CHAT_MEMBERS` 59 с `query`).
    func searchChatMembers(chatId: String, query: String) async throws -> [CoreGroupMember]
    /// Участники из `members`, подходящие под `query`, по общему правилу ядра (имя или имя для
    /// упоминаний, «@» — только оно). `nil` — ядро не может (участники не из него).
    func filterMembers(_ members: [CoreGroupMember], query: String) async -> [CoreGroupMember]?
    /// Спросить статусы людей (`CONTACT_PRESENCE` 35); изменения приходят и событиями `presence`.
    func loadPresence(userIds: [String]) async throws -> [CorePresence]
    /// Статус, который ядро держит для человека (с `presence-ttl` сервера).
    func presenceOf(userId: String) async -> CorePresence
    /// Приложение на экране (`true`) или в фоне: от этого сервер решает «в сети».
    func setAppActive(_ active: Bool) async
    /// Что показать в поле ввода: свой черновик против черновика сервера и метки стирания.
    /// `nil` — поле пустое.
    func reconcileDraft(chatId: String, text: String, elementsJSON: String, replyTo: String, updateTime: Int64) async -> CoreDraft?
    /// Метка стирания черновика чата (время сервера, мс); `0` — метки нет.
    func draftDiscardedAt(chatId: String) async -> Int64
    /// Свои права в чате по карточке ядра.
    func chatRights(chatId: String) async -> CoreChatRights
    /// `edit-timeout` конфига сервера в секундах; `0` — неизвестно.
    func editTimeoutSeconds() async -> Int64
    /// Как удалять выбранное (общее правило `selection/delete.json`). `nil` — ядро не умеет.
    func deletePlan(chatId: String, messageIds: [String]) async -> CoreDeletePlan?
}

public extension MaxCore {
    /// Ядро без отдельного отказа входа: причины нет.
    func loginRejection() async -> CoreLoginRejection? { nil }

    /// Ядро без обновления адресов фото.
    func refreshPhotoURLs(_ items: [PhotoRefreshKey]) async throws -> [RefreshedPhotoURL] {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }

    /// Ядро без ответа на отметку: она уходит прежним вызовом, ответ неизвестен.
    func markRead(chatId: String, messageId: String, mark: Int64) async throws -> CoreReadMark {
        try await markRead(chatId: chatId, messageId: messageId)
        return CoreReadMark(unread: -1, mark: 0)
    }
    func loadChatList() async throws -> (chats: [CoreChat], complete: Bool) {
        (try await loadChats(), false)
    }
    func loadOpenedHistory(chatId: String, limit: Int) async throws -> [CoreMessage] {
        try await loadHistory(chatId: chatId, beforeMs: 0, limit: limit)
    }
    func loadOlderHistory(chatId: String, beforeMs: Int64, limit: Int) async throws -> [CoreMessage] {
        try await loadHistory(chatId: chatId, beforeMs: beforeMs, limit: limit)
    }
    func sendSticker(chatId: String, stickerId: String, replyTo: String) async throws -> CoreMessage {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func sendText(chatId: String, text: String, replyTo: String, animoji: [CoreAnimojiMark]) async throws -> CoreMessage {
        if replyTo.isEmpty { return try await sendText(chatId: chatId, text: text) }
        return try await sendText(chatId: chatId, text: text, replyTo: replyTo)
    }
    func loadStickerCatalog() async throws -> StickerCatalog { throw CoreFailure(kind: "UNKNOWN", key: "unsupported") }
    func loadStickers(ids: [String]) async throws -> [Sticker] { throw CoreFailure(kind: "UNKNOWN", key: "unsupported") }
    func loadAnimatedEmoji() async throws -> [AnimatedEmoji] { throw CoreFailure(kind: "UNKNOWN", key: "unsupported") }
    /// Фейки в тестах, которым контакты не нужны.
    func loadContacts() async throws -> [CoreContact] { [] }
    func loadSharedMedia(chatId: String, anchorId: String, attachTypes: [String], forward: Int, backward: Int) async throws -> [CoreMessage] {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func loadHistoryAround(chatId: String, messageId: String, fromMs: Int64, forward: Int, backward: Int) async throws -> [CoreMessage] {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func loadCallHistory() async throws -> [CoreCall] { [] }
    func callHistory(sync: String) async throws -> CallLogPage {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func rejectIncomingCall(conversationId: String, peerId: String, reason: String) async throws {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func loadProfile(chatId: String) async throws -> CoreProfile {
        throw CoreFailure(kind: "NOT_FOUND", key: nil)
    }
    func setPinnedChats(_ chatIds: [String]) async throws -> [String] {
        throw CoreFailure(kind: "UNKNOWN", key: nil)
    }
    func markUnread(chatId: String, mark: Int64) async throws -> Int {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func mediaLink(chatId: String, messageId: String, kind: String, attachmentId: String) async throws -> String {
        throw CoreFailure(kind: "NOT_FOUND", key: nil)
    }
    /// Фейки без ответов отправляют просто текст.
    func sendText(chatId: String, text: String, replyTo: String) async throws -> CoreMessage {
        try await sendText(chatId: chatId, text: text)
    }
    func loadComments(chatId: String, postId: String, beforeMs: Int64, limit: Int) async throws -> [CoreMessage] { [] }
    func sendComment(chatId: String, postId: String, text: String) async throws -> CoreMessage {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func loadCommentCounts(chatId: String, postIds: [String]) async throws -> [String: Int] { [:] }
    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async throws {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func setChatMuted(chatId: String, muted: Bool) async throws {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func setChatMuteUntil(chatId: String, untilMs: Int64) async throws {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func isChatMuted(chatId: String) async -> Int { -1 }
    func chatMuteUntil(chatId: String) async -> Int64 { Int64.min }
    func mediaUserAgent() -> String? { nil }
    /// Фейки в тестах «печатаю» не отправляют.
    func sendTyping(chatId: String, type: String, postId: String) {}
    func editMessage(chatId: String, messageId: String, text: String) async throws -> CoreMessage {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async throws -> CoreMessage {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func pinnedChats() -> AsyncStream<[String]> { AsyncStream { $0.finish() } }
    func sendMedia(chatId: String, items: [CoreOutgoingMedia], caption: String, replyTo: String,
                   progress: @escaping @Sendable (Double) -> Void) async throws -> CoreMessage {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func sendContact(chatId: String, contactId: String, replyTo: String) async throws -> CoreMessage {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func sendRecording(chatId: String, path: String, kind: String, durationMs: Int64, wave: [Int], replyTo: String,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> CoreMessage {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }

    // Фейки в тестах, которым настройки аккаунта не нужны.
    private var unsupported: CoreFailure { CoreFailure(kind: "UNKNOWN", key: "unsupported") }
    func loadMyProfile() async throws -> MyProfile { throw unsupported }
    func updateProfile(firstName: String, lastName: String, about: String) async throws -> MyProfile { throw unsupported }
    func uploadAvatar(jpeg: Data) async throws -> MyProfile { throw unsupported }
    func removeAvatar() async throws -> MyProfile { throw unsupported }
    func deleteAccount() async throws -> Int64 { throw unsupported }
    func searchPublic(query: String, from: Int, count: Int) async throws -> [CoreSearchChat] { throw unsupported }
    func searchMessages(query: String, count: Int) async throws -> [CoreFoundMessage] { throw unsupported }
    func accountSettings() -> AsyncStream<AccountSettings> { AsyncStream { $0.finish() } }
    func setPhonePrivacy(_ access: PrivacyAccess) async throws -> AccountSettings { throw unsupported }
    func setOnlineHidden(_ hidden: Bool) async throws -> AccountSettings { throw unsupported }
    func setSafeMode(_ enabled: Bool) async throws -> AccountSettings { throw unsupported }
    func setInactiveTTL(_ ttl: InactiveTTL) async throws -> AccountSettings { throw unsupported }
    func setQuickReaction(_ emoji: String) async throws -> AccountSettings { throw unsupported }
    func loadSessions() async throws -> [DeviceSession] { throw unsupported }
    func closeOtherSessions() async throws { throw unsupported }
    func approveQrLogin(_ link: String) async throws { throw unsupported }
    func loadBlockedUsers() async throws -> [BlockedUser] { throw unsupported }
    func unblockUser(_ userId: String) async throws { throw unsupported }
    func blockUser(_ userId: String) async throws { throw unsupported }
    func commonChats(userId: String) async throws -> [CommonChat] { throw unsupported }
    func complaintReasons(typeId: Int) async throws -> [ComplaintReason] { throw unsupported }
    func sendComplaint(reasonId: Int, typeId: Int, ids: [String]) async throws -> Bool { throw unsupported }
    func syncContacts() async throws -> [CoreContact] { throw unsupported }
    func loadTwoFactor() async throws -> TwoFactorStatus { throw unsupported }
    func startEmailChange(password: String) async throws -> String { throw unsupported }
    func sendEmailCode(trackId: String, email: String) async throws -> Int { throw unsupported }
    func confirmEmail(trackId: String, code: String) async throws -> TwoFactorStatus { throw unsupported }
    func launchMiniApp(_ kind: MiniApp.Kind) async throws -> MiniApp { throw unsupported }
    func miniAppCallback(url: String) async throws -> MiniApp { throw unsupported }
    func folders() -> AsyncStream<[ServerFolder]> { AsyncStream { $0.finish() } }
    func loadFolders() async throws -> [ServerFolder] { throw unsupported }
    func createFolder(title: String, chatIds: [String], filters: [String]) async throws { throw unsupported }
    func renameFolder(_ folderId: String, title: String) async throws { throw unsupported }
    func setFolderChats(_ folderId: String, chatIds: [String]) async throws { throw unsupported }
    func deleteFolder(_ folderId: String) async throws { throw unsupported }
    func reorderFolders(_ order: [String]) async throws { throw unsupported }

    // Фейки без реакций.
    func setReaction(chatId: String, messageId: String, postId: String, emoji: String) async throws -> String { throw unsupported }
    func loadReactions(chatId: String, messageIds: [String]) async throws -> [String: String] { throw unsupported }
    func loadReactionCatalog() async throws -> [String] { throw unsupported }
    func loadReactionUsers(chatId: String, messageId: String) async throws -> [ReactionUser] { throw unsupported }
    func loadMessageReaders(chatId: String, messageId: String) async throws -> [MessageReader] { throw unsupported }
    func isReadersAvailable(chatId: String) -> Bool { false }
    func transcribeVoice(chatId: String, messageId: String, audioId: String) async throws -> CoreTranscription { throw unsupported }

    func findByPhone(phone: String) async throws -> CoreContact { throw unsupported }
    func addContact(userId: String, firstName: String) async throws -> CoreContact { throw unsupported }
    func createGroup(title: String, memberIds: [String]) async throws -> CoreChat? { throw unsupported }
    func createChannel(title: String) async throws -> CoreChat? { throw unsupported }
    func joinByLink(_ link: String) async throws -> CoreChat { throw unsupported }
    func deleteChat(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async throws { throw unsupported }
    func leaveChat(chatId: String) async throws { throw unsupported }
    func clearHistory(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async throws { throw unsupported }
    func sendRichText(chatId: String, text: String, replyTo: String, animoji: [CoreAnimojiMark], mentions: [CoreMentionMark]) async throws -> CoreMessage {
        if mentions.isEmpty { return try await sendText(chatId: chatId, text: text, replyTo: replyTo, animoji: animoji) }
        throw unsupported
    }
    func pinMessage(chatId: String, messageId: String) async throws { throw unsupported }
    func pinnedMessages(chatId: String, from: String, backward: Int) async throws -> [CoreMessage] { throw unsupported }
    func updatePinned(chatId: String, action: String, messageIds: [String], forMe: Bool, notify: Bool) async throws { throw unsupported }
    func scheduleMessage(chatId: String, text: String, sendAtMs: Int64) async throws { throw unsupported }
    func scheduledMessages(chatId: String) async throws -> [CoreFoundMessage] { throw unsupported }
    func sendPoll(chatId: String, title: String, answers: [String]) async throws -> CoreMessage { throw unsupported }
    func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async throws { throw unsupported }
    func castPollVotes(chatId: String, messageId: String, pollId: String, answerIds: [String]) async throws -> CorePollCounts { throw unsupported }
    func pollUpdates(chatId: String, polls: [CorePollRef]) async throws -> [CorePollCounts] { throw unsupported }
    func editScheduled(chatId: String, messageId: String, text: String, sendAtMs: Int64) async throws -> CoreFoundMessage { throw unsupported }
    func cancelScheduled(chatId: String, messageIds: [String]) async throws { throw unsupported }
    func searchInChat(chatId: String, query: String) async throws -> [CoreFoundMessage] { throw unsupported }
    func chatMembers(chatId: String) async throws -> [CoreChatMember] { throw unsupported }
    func botCommands(botId: String) async throws -> [CoreBotCommand] { throw unsupported }
    func pressButton(chatId: String, messageId: String, callbackId: String, payload: String) async throws -> CoreButtonAnswer { throw unsupported }
    func launchBotApp(botId: String, chatId: String, startParam: String) async throws -> MiniApp { throw unsupported }
    func startCall(calleeId: String, isVideo: Bool) async throws -> CoreCallStart { throw unsupported }
    func joinCall(link: String, isVideo: Bool) async throws -> CoreCallStart { throw unsupported }
    func createCallLink() async throws -> CoreCallLink { throw unsupported }
    func callLinkInfo(link: String) async throws -> CoreCallLinkInfo? { throw unsupported }
    func deleteCallHistory(ids: [String]) async throws { throw unsupported }
    func incomingCalls() -> AsyncStream<CoreIncomingCall> { AsyncStream { $0.finish() } }
    func enablePassword(password: String, hint: String) async throws { throw unsupported }
    func changePassword(oldPassword: String, newPassword: String) async throws { throw unsupported }
    func disablePassword(password: String) async throws { throw unsupported }

    // Фейки без историй.
    func loadStoriesFeed() async throws -> [StoryRing] { throw unsupported }
    func loadOwnerStories(owner: StoryOwner) async throws -> OwnerStories { throw unsupported }
    func markStorySeen(owner: StoryOwner, storyId: String) async throws { throw unsupported }
    func publishStory(path: String, isVideo: Bool, durationMs: Int64, audience: Int,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> OwnerStories { throw unsupported }
    func deleteStories(ids: [String]) async throws { throw unsupported }
    func ownStoryArchive(marker: String) async throws -> StoryArchivePage { throw unsupported }
    func storyUpdates() -> AsyncStream<StoryRing> { AsyncStream { $0.finish() } }
}

/// Ответ расшифровки голосового: `status` `1` — готово (`text` пуст, если речи не нашлось),
/// `0` — сервер ещё работает, текст придёт пушем, `-1` — не вышло.
public struct CoreTranscription: Sendable, Equatable {
    public var status: Int
    public var text: String

    public init(status: Int, text: String) {
        self.status = status
        self.text = text
    }
}

/// Анимодзи в отправляемом тексте: эмодзи на `from`/`length` (UTF-16).
public struct CoreAnimojiMark: Sendable, Equatable {
    public var from: Int
    public var length: Int
    public var animojiId: String
    public var lottieURL: String

    public init(from: Int, length: Int, animojiId: String, lottieURL: String) {
        self.from = from
        self.length = length
        self.animojiId = animojiId
        self.lottieURL = lottieURL
    }

    /// Отметки из разметки сообщения (`TextSpan.Kind.animoji`).
    public static func marks(_ spans: [TextSpan]?) -> [CoreAnimojiMark] {
        (spans ?? []).compactMap { span in
            guard span.kind == .animoji, let id = span.entityId, !id.isEmpty, span.length > 0 else { return nil }
            return CoreAnimojiMark(from: span.from, length: span.length, animojiId: id, lottieURL: span.url ?? "")
        }
    }
}

/// Упоминание в отправляемом тексте. Смещения UTF-16.
public struct CoreMentionMark: Sendable, Equatable {
    public var from: Int
    public var length: Int
    public var userId: String

    public init(from: Int, length: Int, userId: String) {
        self.from = from
        self.length = length
        self.userId = userId
    }

    public static func marks(_ spans: [TextSpan]?) -> [CoreMentionMark] {
        (spans ?? []).compactMap { span in
            guard span.kind == .mention, let id = span.userId, !id.isEmpty, span.length > 0 else { return nil }
            return CoreMentionMark(from: span.from, length: span.length, userId: id)
        }
    }
}

public struct CoreChatMember: Sendable, Equatable {
    public var id: String
    public var name: String
    public var avatarURL: URL?

    public init(id: String, name: String, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
    }
}

public struct CoreBotCommand: Sendable, Equatable {
    public var name: String
    public var summary: String

    public init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }
}

/// Звонок, который принял сервер: адрес сигнального сокета ws2 и свой номер в звонке.
public struct CoreCallStart: Sendable, Equatable {
    public var conversationId: String
    public var ws2Url: String
    public var callsUserId: Int64
    /// Ссылка группового звонка; пусто у звонка один на один.
    public var joinLink: String
    public var isVideo: Bool

    public init(conversationId: String, ws2Url: String, callsUserId: Int64, joinLink: String = "", isVideo: Bool = false) {
        self.conversationId = conversationId
        self.ws2Url = ws2Url
        self.callsUserId = callsUserId
        self.joinLink = joinLink
        self.isVideo = isVideo
    }
}

/// Новый групповой звонок. `name` пустое, если сервер его не дал.
public struct CoreCallLink: Sendable, Equatable {
    public var conversationId: String
    public var url: String
    public var name: String

    public init(conversationId: String, url: String, name: String = "") {
        self.conversationId = conversationId
        self.url = url
        self.name = name
    }
}

/// Звонок за ссылкой до входа в него.
public struct CoreCallLinkInfo: Sendable, Equatable {
    public var url: String
    public var name: String
    public var participants: Int
    public var isVideo: Bool

    public init(url: String, name: String, participants: Int, isVideo: Bool) {
        self.url = url
        self.name = name
        self.participants = participants
        self.isVideo = isVideo
    }
}

/// Входящий звонок из пуша: кто звонит, адрес ws2 и серверы ICE из `vcp`.
public struct CoreIncomingCall: Sendable, Equatable {
    public var conversationId: String
    public var callerId: String
    public var callerName: String
    public var callerAvatarURL: String
    public var chatId: String
    public var isVideo: Bool
    public var ws2Url: String
    public var callsUserId: Int64
    public var stunUrls: [String]
    public var turnUrls: [String]
    public var turnUsername: String
    public var turnPassword: String
    /// 0 — сервер не сказал срок.
    public var expiresAtMs: Int64

    public init(
        conversationId: String, callerId: String, callerName: String = "", callerAvatarURL: String = "",
        chatId: String = "", isVideo: Bool = false, ws2Url: String, callsUserId: Int64,
        stunUrls: [String] = [], turnUrls: [String] = [], turnUsername: String = "", turnPassword: String = "",
        expiresAtMs: Int64 = 0
    ) {
        self.conversationId = conversationId
        self.callerId = callerId
        self.callerName = callerName
        self.callerAvatarURL = callerAvatarURL
        self.chatId = chatId
        self.isVideo = isVideo
        self.ws2Url = ws2Url
        self.callsUserId = callsUserId
        self.stunUrls = stunUrls
        self.turnUrls = turnUrls
        self.turnUsername = turnUsername
        self.turnPassword = turnPassword
        self.expiresAtMs = expiresAtMs
    }
}

/// Отказ входа, который ядро уже разобрало: причина, тексты сервера и судьба токена.
public struct CoreLoginRejection: Sendable, Equatable {
    public var reason: String
    public var errorKey: String?
    public var serverText: String?
    public var title: String?
    public var localizedMessage: String?
    /// Поле `description` моста: в Swift оно называется иначе, здесь это пояснение сервера.
    public var detail: String?
    public var tokenCleared: Bool

    public init(
        reason: String,
        errorKey: String? = nil,
        serverText: String? = nil,
        title: String? = nil,
        localizedMessage: String? = nil,
        detail: String? = nil,
        tokenCleared: Bool
    ) {
        self.reason = reason
        self.errorKey = errorKey
        self.serverText = serverText
        self.title = title
        self.localizedMessage = localizedMessage
        self.detail = detail
        self.tokenCleared = tokenCleared
    }
}
