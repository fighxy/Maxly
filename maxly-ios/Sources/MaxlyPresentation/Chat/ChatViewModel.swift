import Foundation
import Observation
import MaxlyDomain

/// Открытый чат: сообщения из репозитория, черновик, отправка и повтор.
@MainActor
@Observable
public final class ChatViewModel {
    public let chatId: String
    public let currentUserId: String
    public private(set) var messages: [Message] = [] {
        didSet {
            let ids = messages.map(\.id)
            let oldIds = oldValue.map(\.id)
            messagesChange = isRestoringHistory ? .reload : CollectionChange.between(oldIds, ids)
            changeFromPaging = pagingInFlight
            if !isRestoringHistory, Self.contentChanged(from: oldValue, to: messages) { contentVersion &+= 1 }
            if ids != oldIds { transcriptVersion &+= 1 }
            placeUnreadAnchor()
            rows = TranscriptLayout.rows(messages, currentUserId: currentUserId, unreadAnchorId: unreadAnchorId)
            settleTranscripts()
            pins.applyState()
            settleSeen()
            recountUnreadBelow()
            refreshHistoryFlags()
        }
    }
    /// История сверена с сервером и пуста: в пустом диалоге с ботом внизу «Начать». Отдельный
    /// флаг, чтобы экран не перерисовывался целиком на каждое новое сообщение.
    public private(set) var isHistoryEmpty = false
    /// В ленте есть свои сообщения: плашка незнакомца больше не предлагает «Заблокировать».
    public private(set) var hasOwnMessages = false
    /// Живая лента из репозитория: последние сообщения чата подряд. Лента показывает её или
    /// окно вокруг далёкого сообщения (`window`).
    @ObservationIgnored private var live: [Message] = []
    /// Окно вокруг сообщения, к которому перешли и которого не было в живой ленте.
    private var window: TimelineWindow?
    /// Лента показывает окно, ещё не сошедшееся с живой лентой: новых внизу не видно, кнопка
    /// «вниз» ведёт к живой ленте.
    public var isJumped: Bool { window.map { !$0.joined } ?? false }
    /// Раньше могут быть сообщения: верх ленты догружает их сам.
    public var canLoadOlder: Bool { window.map { !$0.reachedOldest } ?? !liveReachedOldest }
    /// Живая лента дошла до начала истории: страница старше не принесла ничего нового. Без
    /// этого короткий чат спрашивал старое снова и снова, пока строка загрузки видна.
    private var liveReachedOldest = false
    /// Идёт загрузка окна вокруг далёкого сообщения.
    public private(set) var isJumping = false
    /// Последняя страница старого не пришла (пауза сервера, сеть): экран повторит её сам.
    @ObservationIgnored public private(set) var olderFailed = false
    public private(set) var isLoadingNewer = false
    /// Последнее изменение ленты — страница окна, а не новое в чате: экран не едет за ним вниз.
    /// Держится до следующего изменения: экран читает его позже, в `onChange`.
    @ObservationIgnored public private(set) var changeFromPaging = false
    @ObservationIgnored private var pagingInFlight = false
    /// С каких сообщений переходили к цитатам: кнопка «вниз» возвращает к ним по очереди.
    @ObservationIgnored private var returnStack: [String] = []
    /// До какого момента читатель долистал ленту. Чужие сообщения новее — непрочитанные ниже экрана.
    @ObservationIgnored private var seenUpTo: Date?
    /// Непрочитанные ниже экрана: число на кнопке «вниз».
    public private(set) var unreadBelow = 0
    /// Непрочитанные упоминания себя (id сообщений от старых к новым): кнопка «@» в группе.
    /// Те же правила, что у `unreadBelow`: чужие сообщения живой ленты ниже отметки «долистал».
    public private(set) var unreadMentions: [String] = []
    /// Упоминания, к которым уже перешли кнопкой «@» за этот заход.
    @ObservationIgnored private var visitedMentions: Set<String> = []
    /// Сообщение у низа экрана, когда читатель ушёл из чата посреди истории.
    @ObservationIgnored private var savedPlace: String?
    /// Сообщение, на котором открывают чат (`openAt`), пока экран не встал.
    @ObservationIgnored private var pendingOpen: (messageId: String, date: Date?)?
    /// Номер строки по id сообщения: плашка даты ищет верхнюю из видимых.
    @ObservationIgnored private var rowIndex: [String: Int] = [:]
    /// Сообщение, над которым стоит «Непрочитанные сообщения». Ставится один раз при открытии
    /// чата и не двигается, пока чат открыт; своё отправленное сообщение его убирает.
    public private(set) var unreadAnchorId: String? {
        didSet {
            guard unreadAnchorId != oldValue else { return }
            rows = TranscriptLayout.rows(messages, currentUserId: currentUserId, unreadAnchorId: unreadAnchorId)
            // Разделитель встал после отметки «долистал»: непрочитанные под ним снова считаются.
            if let anchor = unreadAnchorId, let seen = seenUpTo, let before = readBefore(anchor), before < seen {
                seenUpTo = before
                readProgress.noteReadAtOpen(ReadMark.time(of: before))
            }
            settleSeen()
            recountUnreadBelow()
        }
    }
    /// Сколько непрочитанных было при открытии и ещё ждут места в ленте.
    @ObservationIgnored private var pendingUnread = 0
    /// Своя отметка прочтения при открытии (`OwnReadMark`, мс): разделитель встаёт над первым
    /// чужим сообщением новее неё. `0` — неизвестна, разделитель ставится по счётчику.
    @ObservationIgnored private var openReadMark: Int64 = 0
    /// Голосовые (id вложения), чья расшифровка идёт: текст ещё не пришёл.
    public private(set) var transcribing: Set<String> = []
    /// Голосовые, у которых расшифровка раскрыта.
    public private(set) var openTranscripts: Set<String> = []
    /// Голосовые, чья расшифровка не удалась: ошибка раскрыта в пузыре до нажатия «^».
    public private(set) var failedTranscripts: Set<String> = []
    /// Столько ждём пуша с текстом, если сервер ответил «ещё расшифровываю».
    static let transcriptWait: Duration = .seconds(60)
    /// Строки ленты с разделителями дней, склейкой и подписями автора (`TranscriptLayout`).
    public private(set) var rows: [TranscriptRow] = [] {
        didSet {
            rowIndex = Dictionary(rows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
    /// Растёт, когда меняется состав ленты (новое, удалённое, история): экран анимирует по нему,
    /// не сравнивая списки id при каждой перерисовке.
    public private(set) var transcriptVersion = 0
    /// Как лента изменилась последним обновлением: экран по нему решает, анимировать ли.
    public private(set) var messagesChange: CollectionChange = .none
    /// Растёт, когда у уже показанных сообщений поменялись реакции или текст: пузырь
    /// меняет размер, и лента плавно раздвигается, а не прыгает.
    public private(set) var contentVersion = 0
    /// Текст в поле ввода. Сохраняется черновиком с короткой задержкой и при уходе с экрана.
    public var draft = "" {
        didSet {
            format.textChanged(from: oldValue, to: draft)
            if draft.isEmpty {
                mentionDraft.clear()
            } else {
                mentionDraft.retainPresent(draft)
            }
            // Текст правки не черновик: его не сохраняем.
            guard draft != oldValue, !isRestoringDraft, editTarget == nil else { return }
            scheduleDraftSave()
            refreshComposerHints()
            if !draft.isEmpty { typingReporter?.textEdited(chatId: chatId, canWrite: typingAllowed) }
        }
    }
    /// Подсказки `@` над полем ввода.
    public private(set) var mentionHints: [ChatMemberRef] = []
    /// Подсказки `/` для бота.
    public private(set) var commandHints: [BotCommandRef] = []
    public private(set) var error: MaxlyError?
    public private(set) var stickToBottom = true
    /// Цитата над полем ввода. Входит в черновик: черновик из одного ответа тоже сохраняется.
    public private(set) var replyTarget: Message? {
        didSet {
            guard replyTarget?.id != oldValue?.id, !isRestoringDraft, editTarget == nil else { return }
            pendingDraftReply = nil
            scheduleDraftSave()
        }
    }
    /// Ответ из черновика, сообщение которого ещё не в ленте (серверный id).
    @ObservationIgnored private var pendingDraftReply: String?
    /// Сообщение, текст которого сейчас правится в поле ввода.
    public private(set) var editTarget: Message?
    /// Черновик, отложенный на время правки.
    @ObservationIgnored private var draftBeforeEdit = ""
    /// Просьба прокрутить ленту: переход к сообщению или вниз. Экран выполняет её и снимает.
    public private(set) var scrollTarget: ChatScrollTarget?
    public private(set) var scrollToken = 0
    public private(set) var highlightedId: String?
    /// Пост, чьи комментарии открыты в модальном окне.
    public var openedComments: Message?
    /// Число комментариев под постами канала (id поста на сервере → число).
    public private(set) var commentCounts: [String: Int] = [:]
    /// Сообщение, для которого открыт выбор «удалить у себя / у всех».
    public var deletionCandidate: Message?
    /// Варианты удаления открытого сообщения (`deletePlan` ядра, как у выбора нескольких).
    public private(set) var deletionOptions: MessageSelectionRules.DeleteOptions?
    /// `edit-timeout` сервера в секундах; `nil` — неизвестен, срок правки не проверяется.
    @ObservationIgnored private var editTimeoutSeconds: Int?
    @ObservationIgnored private var rulesLoaded = false
    /// Сообщение, для которого открыт выбор чата пересылки.
    public var forwardCandidate: Message?
    /// Сообщение, с которого чат помечают непрочитанным: экран забирает его и закрывается.
    public var unreadMarkCandidate: Message?
    /// Короткое уведомление над полем ввода («Переслано»). Само пропадает.
    public private(set) var notice: String?
    /// Диалог открыт из контактов, и на сервере его может ещё не быть: пустая история не
    /// ошибка, экран предлагает написать первое сообщение.
    public let isNewDialog: Bool
    /// Открытые «Сведения» о сообщении.
    public var messageInfo: MessageInfoViewModel?
    /// Ход загрузки вложений своих сообщений: id сообщения → доля 0…1.
    public private(set) var uploadProgress: [String: Double] = [:]
    @ObservationIgnored private var progressWatch: Task<Void, Never>?
    @ObservationIgnored private var failureWatch: Task<Void, Never>?
    /// «Я печатаю» для собеседника (`MSG_TYPING` 65). `nil` — не отправляется.
    @ObservationIgnored public var typingReporter: TypingReporter?
    /// Можно ли писать в чат: экран ставит его по праву на поле ввода. Пока не поставил,
    /// «печатаю» не уходит (канал без прав, чат из поиска).
    @ObservationIgnored public var typingAllowed = false
    /// Когда уходит отметка прочтения (`ReadMarkRules`): пауза после последней смены
    /// кандидата, только самое новое, никогда не старее отправленного.
    @ObservationIgnored private(set) var readMarks: ReadMarkScheduler?
    /// Экран чата на виду: открыт и приложение активно. Только тогда отметки уходят.
    @ObservationIgnored private var readScreenActive = false
    /// Что прочитано: порог открытия, увиденное за показ и «у низа» (`ReadProgress`).
    @ObservationIgnored private var readProgress = ReadProgress()
    /// Чат помечают непрочитанным: отметки не уходят до следующего открытия.
    @ObservationIgnored private var markingUnread = false

    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private let drafts: (any ChatDraftStore)?
    @ObservationIgnored private let comments: (any CommentsRepository)?
    /// Посты, чьи счётчики уже спрошены: один запрос на пост за время жизни экрана.
    @ObservationIgnored private var askedCounts: Set<String> = []
    /// После ошибки счётчики комментариев не спрашиваются до этого времени.
    @ObservationIgnored private var countsRetryAt = Date.distantPast
    @ObservationIgnored private let chats: (any ChatRepository)?
    @ObservationIgnored private var mentionDraft = MentionDraft()
    @ObservationIgnored private var memberRows: [ChatMemberRef] = []
    @ObservationIgnored private var commandRows: [BotCommandRef] = []
    @ObservationIgnored private var membersAsked = false
    @ObservationIgnored private var commandsAsked = false
    /// Собеседник личного чата: команды бота и сигнал звонка.
    @ObservationIgnored public var peerId: String?
    @ObservationIgnored public var peerIsBot = false
    @ObservationIgnored private let draftDelay: Duration
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var draftSave: Task<Void, Never>?
    @ObservationIgnored private var isRestoringDraft = false
    @ObservationIgnored private var saveChain: Task<Void, Never>?
    /// Последний текст, отданный хранилищу: не пишем одно и то же дважды.
    @ObservationIgnored private var savedDraft: String?
    /// Ответ, записанный в черновик (серверный id).
    @ObservationIgnored private var savedReply: String?
    /// Подписка на черновики, изменённые не из этого поля.
    @ObservationIgnored private var draftWatch: Task<Void, Never>?
    @ObservationIgnored private var commentsModel: CommentsViewModel?
    /// Выбор нескольких сообщений: копирование, пересылка, удаление одним запросом.
    public let selection: MessageSelectionModel
    /// Поиск по сообщениям чата.
    public let search: ChatSearchModel
    /// Голоса в опросах, новый опрос, сверка счёта.
    public let polls: ChatPollsModel
    /// Отложенные сообщения.
    public let scheduled: ScheduledMessagesModel
    /// Голосовые: пуск, пауза, перемотка и полоса «играет голосовое».
    public let voices: VoicePlaybackModel
    /// Вложения: просмотр, кружки в ленте, файлы, сохранение.
    public let attachments: ChatMediaModel
    /// Реакции: каталог, поставить и снять, выбор, «Кто отреагировал», анимация.
    public let reactions: ChatReactionsModel
    /// Закрепы в шапке: служебное сообщение, список 241, пуши.
    public let pins: ChatPinsModel

    public init(
        chatId: String,
        currentUserId: String,
        messages: any MessageRepository,
        drafts: (any ChatDraftStore)? = nil,
        draftDelay: Duration = .milliseconds(500),
        media: (any MediaRepository)? = nil,
        links: (any MediaLinkResolver)? = nil,
        comments: (any CommentsRepository)? = nil,
        voice: (any VoicePlaying)? = nil,
        gallery: (any GallerySaving)? = nil,
        isNewDialog: Bool = false,
        chats: (any ChatRepository)? = nil,
        readMarkSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.isNewDialog = isNewDialog
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.repository = messages
        self.drafts = drafts
        self.draftDelay = draftDelay
        self.comments = comments
        self.chats = chats
        self.selection = MessageSelectionModel(chatId: chatId, currentUserId: currentUserId, repository: messages)
        self.search = ChatSearchModel(chatId: chatId, repository: messages)
        self.polls = ChatPollsModel(chatId: chatId, repository: messages)
        self.scheduled = ScheduledMessagesModel(chatId: chatId, repository: messages)
        self.voices = VoicePlaybackModel(chatId: chatId, currentUserId: currentUserId, repository: messages, media: media, voice: voice)
        self.attachments = ChatMediaModel(chatId: chatId, repository: messages, media: media, links: links, gallery: gallery)
        self.reactions = ChatReactionsModel(chatId: chatId, repository: messages)
        self.pins = ChatPinsModel(chatId: chatId, repository: messages)
        selection.onNotice = { [weak self] text in self?.showNotice(text) }
        selection.onError = { [weak self] failure in self?.show(failure) }
        selection.onDeleted = { [weak self] ids in
            guard let self, let reply = self.replyTarget, ids.contains(reply.id) else { return }
            self.replyTarget = nil
        }
        readMarks = ReadMarkScheduler(sleep: readMarkSleep) { [weak self] mark in
            await self?.sendReadMark(mark) ?? false
        }
        polls.messages = { [weak self] in self?.messages ?? [] }
        polls.beforeSend = { [weak self] in self?.returnToLiveForSending() }
        polls.onSuccess = { [weak self] in self?.error = nil }
        polls.onNotice = { [weak self] text in self?.showNotice(text) }
        polls.onError = { [weak self] failure in self?.show(failure) }
        scheduled.onScheduled = { [weak self] in self?.draft = "" }
        voices.onWillPlay = { [weak self] in self?.attachments.stopRoundPlayback() }
        attachments.messages = { [weak self] in self?.messages ?? [] }
        attachments.isOutgoing = { [weak self] message in self?.isOutgoing(message) ?? false }
        attachments.onWillPlayRound = { [weak self] in self?.voices.stop() }
        attachments.onNotice = { [weak self] text in self?.showNotice(text) }
        attachments.onError = { [weak self] failure in self?.show(failure) }
        reactions.messages = { [weak self] in self?.messages ?? [] }
        pins.live = { [weak self] in self?.live ?? [] }
        pins.onFocus = { [weak self] id in self?.focusReply(id) }
        pins.onNotice = { [weak self] text in self?.showNotice(text) }
        pins.onError = { [weak self] failure in self?.show(failure) }
        reactions.onError = { [weak self] failure in self?.show(failure) }
        reactions.onSuccess = { [weak self] in
            if case .rejected(ChatReactionsModel.failure)? = self?.error { self?.error = nil }
        }
        scheduled.onNotice = { [weak self] text in self?.showNotice(text) }
        scheduled.onError = { [weak self] failure in self?.show(failure) }
    }



    public var errorMessage: String? { error?.userMessage }

    /// У сообщений, что были и остались, поменялись реакции или текст.
    nonisolated static func contentChanged(from old: [Message], to new: [Message]) -> Bool {
        guard !old.isEmpty, !new.isEmpty else { return false }
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return new.contains { message in
            guard let previous = before[message.id] else { return false }
            return previous.content.reactions != message.content.reactions || previous.text != message.text
        }
    }

    /// Подсказка вместо пустой истории нового диалога.
    public var emptyHint: String? {
        guard isNewDialog, messages.isEmpty else { return nil }
        return "Здесь пока нет сообщений. Напишите первое — диалог появится в списке чатов."
    }

    /// Свежая история загружена хотя бы раз: пустая лента — действительно пустой чат.
    public private(set) var latestLoaded = false {
        didSet {
            if latestLoaded, !oldValue { placeUnreadAnchor() }
            refreshHistoryFlags()
        }
    }
    /// Адрес, который экран должен открыть: ответ бота на кнопку или кнопка-ссылка.
    public var openURLRequest: URL?
    /// Мини-приложение бота, которое экран должен открыть листом.
    public var botAppRequest: BotAppRequest?
    /// Подпись кнопки бота, нажатие которой ждёт ответа сервера.
    public private(set) var pressingButton: String?
    /// Кэш и серверная сверка при каждом открытии не являются live-вставками.
    public private(set) var isRestoringHistory = false {
        didSet {
            if !isRestoringHistory { settleSeen() }
            refreshHistoryFlags()
        }
    }
    @ObservationIgnored private var watchGeneration = 0
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var latestRetry: Task<Void, Never>?
    public private(set) var isLoadingLatest = false
    public private(set) var isLoadingOlder = false
    public private(set) var historyError: MaxlyError? {
        didSet { refreshHistoryFlags() }
    }

    /// Пустое «Избранное»: вместо ленты плашка о том, что это за чат.
    public var showsSavedPlaceholder: Bool {
        chatId == Chat.savedMessagesId && latestLoaded && messages.isEmpty
    }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Чат открыт с `count` непрочитанными (до отметки прочтения): над первым из них встанет
    /// разделитель, лента откроется на нём. `ownReadMark` — своя отметка прочтения
    /// (`ChatRepository.ownReadMark`, самая свежая из карточки, пуша и местной): если она
    /// известна, разделитель встаёт над первым чужим сообщением новее неё.
    ///
    /// Это и есть открытие чата (возврат из профиля его не вызывает): окно перехода, возвраты
    /// к цитатам, отметка «долистал» и отправленная отметка прочтения прежнего захода
    /// сбрасываются.
    public func noteUnreadOnOpen(_ count: Int, ownReadMark: Int64 = 0) {
        pendingUnread = max(count, 0)
        openReadMark = max(ownReadMark, 0)
        markingUnread = false
        readMarks?.reset()
        readProgress.open(position: openReadMark)
        returnStack = []
        seenUpTo = nil
        visitedMentions = []
        if window != nil { setWindow(nil) }
        unreadAnchorId = nil
        placeUnreadAnchor()
        settleSeen()
        recountUnreadBelow()
    }

    private func placeUnreadAnchor() {
        guard pendingUnread > 0, unreadAnchorId == nil else { return }
        guard let anchor = TranscriptLayout.firstUnread(
            live, readMark: openReadMark, unread: pendingUnread, currentUserId: currentUserId, complete: latestLoaded
        ) else { return }
        pendingUnread = 0
        unreadAnchorId = anchor
    }

    /// Нажатие inline-кнопки бота `CALLBACK` или `OPEN_APP`. Ссылку и копирование экран делает
    /// сам. Ответ сервера с текстом — уведомление над полем, с адресом — `openURLRequest`.
    public func press(_ button: InlineButton, in message: Message) async {
        switch button.action {
        case .callback:
            guard let chats, let callbackId = message.content.keyboard?.callbackId, !callbackId.isEmpty,
                  let serverId = message.serverId ?? (Int64(message.id) != nil ? message.id : nil) else {
                showNotice("Кнопка не поддерживается")
                return
            }
            pressingButton = button.text
            defer { pressingButton = nil }
            do {
                let answer = try await chats.pressButton(chatId: chatId, messageId: serverId, callbackId: callbackId, payload: button.payload)
                if let url = answer.url { openURLRequest = url }
                if let text = answer.text { showNotice(text) }
            } catch {
                show(error)
            }
        case .openApp(let botId, let startParam, let appChat):
            guard let bot = botId ?? (peerIsBot ? peerId : nil) else {
                showNotice("Не удалось открыть приложение")
                return
            }
            botAppRequest = BotAppRequest(botId: bot, chatId: appChat ?? chatId, startParam: startParam, title: button.text)
        case .link(let url):
            openURLRequest = url
        case .copy:
            break
        }
    }

    /// «Открыть приложение» в чате с ботом.
    public func openBotApp(botId: String, title: String) {
        botAppRequest = BotAppRequest(botId: botId, chatId: chatId, startParam: nil, title: title)
    }

    /// Идёт вступление в канал или группу: кнопка показывает индикатор и не нажимается.
    public private(set) var joining = false

    /// «Подписаться» в канале или «Вступить» в группе вне списка (открыты из поиска): вступление
    /// по публичной ссылке (`CHAT_JOIN`). Чат попадает в список, и экран сам переходит к нему.
    /// `true` — сервер принял.
    @discardableResult
    public func join(link: String) async -> Bool {
        guard let chats, !joining else { return false }
        joining = true
        defer { joining = false }
        do {
            _ = try await chats.joinByLink(link)
            return true
        } catch {
            show(error)
            return false
        }
    }

    public func isOutgoing(_ message: Message) -> Bool {
        !currentUserId.isEmpty && message.authorId == currentUserId
    }

    // MARK: «Я печатаю»

    /// Запись голосового (`.audio`) или кружка (`.videoMessage`) пошла; `nil` — кончилась.
    public func typingRecording(_ kind: TypingKind?) {
        guard let typingReporter else { return }
        if let kind {
            typingReporter.recordingStarted(kind, chatId: chatId, canWrite: typingAllowed)
        } else {
            typingReporter.recordingStopped(chatId: chatId)
        }
    }

    /// Открыта панель эмодзи и стикеров.
    public func typingStickerPanelOpened() {
        typingReporter?.stickerPanelOpened(chatId: chatId, canWrite: typingAllowed)
    }

    /// Ход загрузки своих вложений этого чата: фото, видео или файл. Голосовое и кружок
    /// уже сообщены записью.
    private func reportUploads(_ snapshot: [String: Double]) {
        guard let typingReporter, !snapshot.isEmpty else { return }
        for message in messages where message.chatId == chatId {
            guard let fraction = snapshot[message.id], fraction < 1,
                  let kind = Self.uploadKind(message) else { continue }
            typingReporter.uploadProgress(kind, chatId: chatId, canWrite: typingAllowed)
            return
        }
    }

    nonisolated static func uploadKind(_ message: Message) -> TypingKind? {
        for attachment in message.content.attachments {
            switch attachment {
            case .photo: return .photo
            case .video(let video): return video.isRound ? nil : .video
            case .file: return .file
            default: continue
            }
        }
        return nil
    }

    public func activate() {
        guard watch == nil else { return }
        reactions.loadCatalog()
        startMessagesWatch()
        pins.startWatch()
        scheduled.startWatch()
        polls.startRefresh()
        let progress = repository.uploadProgress()
        let failures = repository.uploadFailures()
        failureWatch = Task { [weak self] in
            for await failure in failures {
                guard let self else { return }
                guard failure.chatId == self.chatId else { continue }
                self.showNotice(failure.notice)
            }
        }
        progressWatch = Task { [weak self] in
            for await snapshot in progress {
                guard let self else { return }
                self.uploadProgress = snapshot
                self.reportUploads(snapshot)
            }
        }
        if let drafts {
            let chatId = chatId
            Task { [weak self] in
                let saved = await drafts.draft(chatId: chatId)
                let reply = await drafts.draftReply(chatId: chatId)
                guard let self else { return }
                if let saved, self.draft.isEmpty {
                    self.savedDraft = saved
                    self.isRestoringDraft = true
                    self.draft = saved
                    self.isRestoringDraft = false
                }
                if let reply, self.replyTarget == nil, self.editTarget == nil {
                    self.savedReply = reply
                    self.pendingDraftReply = reply
                    self.resolveDraftReply()
                }
            }
            draftWatch?.cancel()
            draftWatch = Task { [weak self] in
                let changes = await drafts.draftChanges()
                for await changed in changes where changed == chatId {
                    guard let self, !Task.isCancelled else { return }
                    await self.reloadDraft()
                }
            }
        }
    }

    private func startMessagesWatch(finishesRestoration: Bool = false, loaded: Bool = false) {
        watch?.cancel()
        watchGeneration &+= 1
        let generation = watchGeneration
        let stream = repository.messages(chatId: chatId)
        watch = Task { [weak self] in
            var first = true
            for await page in stream {
                guard let self, !Task.isCancelled, self.watchGeneration == generation else { return }
                self.receiveLive(page)
                self.resolveDraftReply()
                if first, finishesRestoration {
                    self.messagesChange = .reload
                    if loaded { self.latestLoaded = true }
                    self.isRestoringHistory = false
                }
                first = false
            }
        }
    }

    public func deactivate() {
        typingReporter?.recordingStopped(chatId: chatId)
        endReadSession()
        latestRetry?.cancel()
        latestRetry = nil
        loadGeneration &+= 1
        isLoadingLatest = false
        isLoadingOlder = false
        watchGeneration &+= 1
        isRestoringHistory = false
        watch?.cancel()
        watch = nil
        progressWatch?.cancel()
        progressWatch = nil
        failureWatch?.cancel()
        failureWatch = nil
        // Голосовое не останавливается: выход из чата в список его не прерывает, полоса над
        // списком продолжает его показывать. Плеер один на приложение, его останавливает выход
        // из аккаунта.
        attachments.cancel()
        selection.cancel()
        draftWatch?.cancel()
        draftWatch = nil
        pins.stopWatch()
        scheduled.stopWatch()
        polls.stopRefresh()
        flushDraft()
    }

    /// Сохранить черновик сразу, не дожидаясь паузы в наборе.
    public func flushDraft() {
        draftSave?.cancel()
        draftSave = nil
        persistDraft()
        commitDraft()
    }

    /// Из поля ушли: черновик сверяется с сервером после записи на устройстве.
    private func commitDraft() {
        guard let drafts, editTarget == nil else { return }
        let chatId = chatId
        let previous = saveChain
        saveChain = Task {
            await previous?.value
            await drafts.commitDraft(chatId: chatId)
        }
    }

    private func scheduleDraftSave() {
        guard drafts != nil else { return }
        draftSave?.cancel()
        let delay = draftDelay
        draftSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.persistDraft()
        }
    }

    private func persistDraft() {
        guard let drafts else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ответ, чьё сообщение ещё не загружено, остаётся в черновике как был.
        let reply = replyTarget?.serverId ?? pendingDraftReply
        let textChanged = text != (savedDraft ?? "")
        let replyChanged = reply != savedReply
        guard textChanged || replyChanged else { return }
        savedDraft = text
        savedReply = reply
        let chatId = chatId
        // Записи идут цепочкой: иначе поздний пустой черновик мог бы лечь раньше раннего.
        let previous = saveChain
        saveChain = Task {
            await previous?.value
            if replyChanged { await drafts.saveDraftReply(reply, chatId: chatId) }
            if textChanged { await drafts.saveDraft(text, chatId: chatId) }
        }
    }

    /// Ответ из черновика встаёт над полем, как только его сообщение появилось в ленте.
    private func resolveDraftReply() {
        guard let id = pendingDraftReply else { return }
        guard replyTarget == nil, editTarget == nil else {
            pendingDraftReply = nil
            return
        }
        guard let message = messages.first(where: { $0.serverId == id }) ?? live.first(where: { $0.serverId == id }) else { return }
        pendingDraftReply = nil
        isRestoringDraft = true
        replyTarget = message
        isRestoringDraft = false
    }

    /// Черновик поменяли на другом устройстве: поле берёт его, если своих незаписанных правок нет.
    private func reloadDraft() async {
        guard let drafts, editTarget == nil else { return }
        let current = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentReply = replyTarget?.serverId ?? pendingDraftReply
        guard current == (savedDraft ?? ""), currentReply == savedReply else { return }
        let text = await drafts.draft(chatId: chatId) ?? ""
        let reply = await drafts.draftReply(chatId: chatId)
        // Пока ждали хранилище, поле могли начать править.
        guard editTarget == nil, draft.trimmingCharacters(in: .whitespacesAndNewlines) == current else { return }
        savedDraft = text
        savedReply = reply
        isRestoringDraft = true
        draft = text
        if reply != replyTarget?.serverId { replyTarget = nil }
        isRestoringDraft = false
        pendingDraftReply = replyTarget == nil ? reply : nil
        resolveDraftReply()
    }

    public func loadLatest() async {
        guard !isLoadingLatest, !Task.isCancelled else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoadingLatest = true
        isLoadingOlder = false
        historyError = nil
        isRestoringHistory = true
        var loaded = false
        await loadMessageRules()
        do {
            // Открытие чата: страница уходит и во время паузы чтений. Тихий повтор ниже её ждёт.
            try await repository.openLatest(chatId: chatId)
            guard generation == loadGeneration, !Task.isCancelled else {
                finishCancelledLoad(generation)
                return
            }
            await reachUnread(generation)
            guard generation == loadGeneration, !Task.isCancelled else {
                finishCancelledLoad(generation)
                return
            }
            loaded = true
            error = nil
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else {
                finishCancelledLoad(generation)
                return
            }
            if error.isRateLimit {
                // Сервер просит подождать. Красной строки над полем нет: лента из кэша
                // остаётся, пустой экран объясняет паузу, сверка повторится сама.
                historyError = error
                scheduleLatestRetry()
            } else if !(isNewDialog && messages.isEmpty && error != .networkUnavailable) {
                // Истории нового диалога на сервере может не быть: это не ошибка для экрана.
                if error != .cancelled { historyError = error }
                show(error)
            }
        }
        isLoadingLatest = false
        // Завершение сверки относится только к текущему открытию экрана.
        // Пустое состояние публикуется вместе со снимком, а не до него.
        if watch != nil { startMessagesWatch(finishesRestoration: true, loaded: loaded) }
        else {
            if loaded { latestLoaded = true }
            isRestoringHistory = false
        }
    }

    /// Повтор сверки после `too.many.requests`. Без перезагрузки ленты: новые сообщения
    /// приходят в подписку как обычные вставки, прокрутка не сбивается.
    ///
    /// Не больше `latestRetryLimit` раз, с растущей паузой: каждый отказ продлевает ограничение
    /// сервера, и бесконечный повтор в чате, который сервер не отдаёт, держал бы под ним весь
    /// аккаунт. Дальше — только «Повторить» на экране.
    private func scheduleLatestRetry(attempt: Int = 0) {
        latestRetry?.cancel()
        guard attempt < Self.latestRetryLimit else { return }
        latestRetry = Task { [weak self] in
            try? await Task.sleep(for: Self.rateLimitRetry * (1 << attempt))
            guard !Task.isCancelled, let self, self.watch != nil else { return }
            do {
                try await self.repository.fetchLatest(chatId: self.chatId)
                guard !Task.isCancelled else { return }
                self.latestLoaded = true
                if self.historyError?.isRateLimit == true { self.historyError = nil }
            } catch let error as MaxlyError {
                // В замыкании задачи тип ошибки не выводится из `fetchLatest`: приводим явно.
                guard !Task.isCancelled, error.isRateLimit else { return }
                self.scheduleLatestRetry(attempt: attempt + 1)
            } catch {}
        }
    }

    private func finishCancelledLoad(_ generation: Int) {
        guard generation == loadGeneration else { return }
        isLoadingLatest = false
        isRestoringHistory = false
    }

    /// Вложения из листа: делятся на сообщения (`AttachmentBatchPlanner`), цитата уходит
    /// с первым. Каждое сообщение появляется сразу и грузится в фоне.
    /// `true`, если всё ушло; при ошибке её текст уже показан в чате.
    @discardableResult
    public func sendAttachments(_ drafts: [AttachmentDraft], caption: String) async -> Bool {
        let plan = AttachmentBatchPlanner.plan(drafts, caption: caption)
        guard !plan.batches.isEmpty else { return false }
        var reply = replyTarget?.id
        replyTarget = nil
        stickToBottom = true
        returnToLiveForSending()
        do {
            for batch in plan.batches {
                try await repository.sendAttachments(batch.drafts, caption: batch.caption, chatId: chatId, replyTo: reply)
                reply = nil
            }
            if !plan.trailingText.isEmpty {
                try await repository.send(text: plan.trailingText, chatId: chatId, replyTo: nil)
            }
            error = nil
            return true
        } catch {
            show(error)
            return false
        }
    }

    /// Остановить загрузку своего сообщения и убрать его.
    public func cancelUpload(_ message: Message) async {
        await repository.cancelUpload(messageId: message.id)
    }

    /// Доля загрузки для кольца на пузыре; `nil`, если сообщение не грузится.
    public func uploadFraction(of message: Message) -> Double? {
        uploadProgress[message.id]
    }

    public func loadOlder() async {
        guard !isLoadingOlder, !isRestoringHistory, !Task.isCancelled else { return }
        if window != nil {
            await loadOlderInWindow()
            return
        }
        isLoadingOlder = true
        olderFailed = false
        let generation = loadGeneration
        defer { if generation == loadGeneration { isLoadingOlder = false } }
        stickToBottom = false
        do {
            let grew = try await repository.loadOlder(chatId: chatId)
            if !grew, generation == loadGeneration { liveReachedOldest = true }
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            olderFailed = true
            // Пауза сервера: экран спросит страницу ещё раз, пока верх ленты на экране.
            if error.isRateLimit { return }
            if isNewDialog, messages.isEmpty, error != .networkUnavailable { return }
            show(error)
        }
    }

    public func send() async {
        let marked = MessageMarkup.trimmed(draft, spans: format.spans)
        let text = marked.text
        guard !text.isEmpty else { return }
        if let target = editTarget {
            await saveEdit(target)
            return
        }
        let reply = replyTarget
        let animoji = animojiDraft
        let mentions = mentionDraft
        let spans = marked.spans + animoji.spans(in: text) + mentions.spans(in: text)
        draft = ""
        format = ComposerFormat()
        // Ответил — значит, прочитал: разделитель непрочитанных больше не нужен.
        pendingUnread = 0
        unreadAnchorId = nil
        animojiDraft.clear()
        mentionDraft.clear()
        replyTarget = nil
        stickToBottom = true
        returnToLiveForSending()
        do {
            try await repository.send(text: text, chatId: chatId, replyTo: reply?.id, formatting: spans)
            error = nil
        } catch {
            draft = text
            format = ComposerFormat(spans: marked.spans)
            animojiDraft = animoji
            mentionDraft = mentions
            replyTarget = reply
            show(error)
        }
    }

    // MARK: Разметка поля

    /// Разметка поля ввода (панель «Жирный», «Курсив», …), смещения UTF-16 по `draft`.
    public internal(set) var format = ComposerFormat()
    /// Выделение в поле (UTF-16 по `draft`); `nil` — ничего не выделено, панели нет.
    /// Задаёт экран: выделение в SwiftUI-поле видно с iOS 18.
    public var formatSelection: Range<Int>?
    /// Разметка, отложенная на время правки.
    @ObservationIgnored private var formatBeforeEdit = ComposerFormat()

    /// Выделение, к которому применяется панель: внутри текста и не пустое.
    private var selectedRange: Range<Int>? {
        guard let range = formatSelection, !range.isEmpty, range.upperBound <= draft.utf16.count else { return nil }
        return range
    }

    public func isFormatActive(_ kind: TextSpan.Kind) -> Bool {
        guard let range = selectedRange else { return false }
        return kind == .link ? format.link(in: range) != nil : format.isActive(kind, in: range)
    }

    public func toggleFormat(_ kind: TextSpan.Kind) {
        guard let range = selectedRange else { return }
        format.toggle(kind, in: range)
    }

    /// Адрес ссылки на выделении — для поля «Ссылка».
    public var selectedLink: String? {
        selectedRange.flatMap { format.link(in: $0) }
    }

    /// `false` — адрес не похож на ссылку.
    @discardableResult
    public func setLink(_ raw: String) -> Bool {
        guard let range = selectedRange else { return false }
        return format.setLink(raw, in: range)
    }

    public var canClearFormat: Bool {
        selectedRange.map { format.hasFormatting(in: $0) } ?? false
    }

    public func clearFormat() {
        guard let range = selectedRange else { return }
        format.clear(in: range)
    }

    /// Анимодзи, вставленные в поле из панели: уходят с текстом отметками `ANIMOJI`.
    @ObservationIgnored public private(set) var animojiDraft = AnimojiDraft()

    /// Эмодзи из панели встаёт в конец поля (курсор SwiftUI-полю не известен).
    public func insertEmoji(_ emoji: String, animated: AnimatedEmoji? = nil) {
        draft += emoji
        if let animated { animojiDraft.insert(animated) }
    }

    /// Стрелка «стереть» панели эмодзи: убирает последний символ, эмодзи целиком.
    public func deleteBackward() {
        guard !draft.isEmpty else { return }
        draft.removeLast()
    }

    /// Стикер уходит сразу отдельным сообщением; цитата — если отвечали.
    public func sendSticker(_ sticker: Sticker) async {
        await sendAttachments([.sticker(sticker)], caption: "")
    }

    public func beginReply(to message: Message) {
        if editTarget != nil { cancelEdit() }
        replyTarget = message
    }

    // MARK: Правка

    /// Править можно свой отправленный текст (не пересланный), пока не вышел `edit-timeout`
    /// сервера (если ядро его знает).
    public func canEdit(_ message: Message) -> Bool {
        isOutgoing(message) && message.status == .sent && message.serverId != nil
            && message.content.forward == nil
            && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && editTimeoutSeconds.map { Date().timeIntervalSince(message.timestamp) <= TimeInterval($0) } ?? true
    }

    /// Срок правки и права в чате от ядра — один раз при открытии чата.
    private func loadMessageRules() async {
        guard !rulesLoaded else { return }
        rulesLoaded = true
        if let seconds = await repository.editTimeoutSeconds() {
            editTimeoutSeconds = seconds
            selection.editTimeout = .seconds(seconds)
        }
        selection.coreAdmin = await repository.canDeleteOthers(chatId: chatId)
    }

    /// Текст сообщения переходит в поле ввода; прежний черновик откладывается.
    public func beginEdit(_ message: Message) {
        guard canEdit(message) else { return }
        replyTarget = nil
        if editTarget == nil {
            draftBeforeEdit = draft
            formatBeforeEdit = format
        }
        editTarget = message
        draft = message.text
        // Правка начинается со всей разметки сообщения: `MSG_EDIT` заменяет её целиком.
        format = ComposerFormat(spans: message.content.formatting ?? [])
    }

    public func cancelEdit() {
        guard editTarget != nil else { return }
        editTarget = nil
        draft = draftBeforeEdit
        format = formatBeforeEdit
        draftBeforeEdit = ""
        formatBeforeEdit = ComposerFormat()
    }

    /// Текст и весь список разметки: на сервер уходит полный список, пустой снимает разметку.
    /// Ничего не изменилось — правка просто закрывается.
    private func saveEdit(_ target: Message) async {
        let spans = format.spans + animojiDraft.spans(in: draft) + mentionDraft.spans(in: draft)
        let original = target.content.formatting ?? []
        guard MessageMarkup.editRequest(originalText: target.text, originalSpans: original, draft: draft, spans: spans) != nil else {
            cancelEdit()
            return
        }
        let edited = MessageMarkup.trimmed(draft, spans: spans)
        editTarget = nil
        let restore = draftBeforeEdit
        let restoreFormat = formatBeforeEdit
        draftBeforeEdit = ""
        formatBeforeEdit = ComposerFormat()
        isRestoringDraft = true
        draft = restore
        format = restoreFormat
        isRestoringDraft = false
        do {
            try await repository.edit(messageId: target.id, chatId: chatId, text: edited.text, formatting: edited.spans)
            error = nil
        } catch {
            // Правка не ушла: вернуть её в поле ввода.
            draftBeforeEdit = draft
            formatBeforeEdit = format
            editTarget = target
            draft = edited.text
            format = ComposerFormat(spans: edited.spans)
            show(error)
        }
    }

    public func cancelReply() {
        replyTarget = nil
    }

    // MARK: Реакции

    /// «Сведения» о сообщении: у любого сообщения, принятого сервером (своего и чужого).
    /// Тип чата знает экран, модель ленты его не хранит.
    public func canShowInfo(_ message: Message) -> Bool {
        MessageInfoViewModel.isAvailable(for: message)
    }

    public func showMessageInfo(_ message: Message, chatType: ChatType) {
        guard canShowInfo(message) else { return }
        messageInfo = MessageInfoViewModel(message: message, chatType: chatType, isOwn: isOutgoing(message), repository: repository)
    }

    /// Пауза перед повтором реакций и счётчиков после ошибки сервера.
    static let retryAfterError: TimeInterval = 30
    /// Через сколько повторить сверку ленты после `too.many.requests`.
    static let rateLimitRetry: Duration = .seconds(20)
    /// Сколько раз сам повторить свежую страницу после `too.many.requests` (паузы 1×, 2×, 4×).
    static let latestRetryLimit = 3

    /// Перейти к сообщению: цитате, закрепу, найденному, «Показать в чате». `source` — с какого
    /// сообщения перешли (кнопка «вниз» сначала вернёт к нему), `date` — время цели, если известно.
    public func focusReply(_ messageId: String, from source: String? = nil, at date: Date? = nil) {
        Task { await jump(to: messageId, from: source, at: date) }
    }

    /// Сообщение есть в ленте — лента едет к нему и подсвечивает. Нет — с сервера приходит окно
    /// вокруг него (`TimelineWindow`), лента показывает окно. Неотправленное своё сообщение,
    /// которого нет в ленте, искать негде.
    public func jump(to messageId: String, from source: String? = nil, at date: Date? = nil) async {
        if let match = Self.find(messageId, in: messages) {
            noteReturn(from: source, to: match.id)
            focus(on: match.id)
            return
        }
        if window != nil, let match = Self.find(messageId, in: live) {
            setWindow(nil)
            noteReturn(from: source, to: match.id)
            focus(on: match.id)
            return
        }
        guard Int64(messageId) != nil, !isJumping else { return }
        isJumping = true
        defer { isJumping = false }
        do {
            let page = try await repository.historyAround(
                chatId: chatId, messageId: messageId, at: date,
                forward: Self.aroundForward, backward: Self.aroundBackward
            )
            guard let match = Self.find(messageId, in: page) else {
                showNotice("Сообщение не найдено")
                return
            }
            var opened = TimelineWindow(page)
            if opened.meets(live) { opened.join(live) }
            setWindow(opened)
            noteReturn(from: source, to: match.id)
            focus(on: match.id)
        } catch {
            if error.isRateLimit { showNotice("Сервер просит подождать") } else { show(error) }
        }
    }

    /// Кнопка «вниз»: сначала назад к сообщению, с которого перешли к цитате, потом из окна к
    /// живой ленте. `false` — ни того ни другого: экран сам едет к последнему сообщению.
    public func returnFromJump() -> Bool {
        while let source = returnStack.popLast() {
            if let match = Self.find(source, in: messages) {
                request(.message(match.id, highlight: false))
                return true
            }
            if window != nil, let match = Self.find(source, in: live) {
                setWindow(nil)
                request(.message(match.id, highlight: false))
                return true
            }
        }
        guard isJumped else { return false }
        setWindow(nil)
        request(.bottom)
        return true
    }

    /// Чат открывают на сообщении (найденном в общем поиске): лента встанет на нём, как после
    /// перехода по цитате, а не на «Непрочитанных» или прежнем месте. Уже открытый и сверенный
    /// чат переходит сразу, иначе — когда экран встанет после открытия (`startPendingOpen`).
    public func openAt(messageId: String, at date: Date? = nil) {
        if watch != nil, latestLoaded, !isRestoringHistory {
            focusReply(messageId, at: date)
        } else {
            pendingOpen = (messageId, date)
        }
    }

    /// Чат открывается на сообщении (`openAt`), переход ещё не начат.
    public var hasPendingOpen: Bool { pendingOpen != nil }

    /// Экран встал после открытия: переход к сообщению, на котором чат открыли.
    public func startPendingOpen() {
        guard let target = pendingOpen else { return }
        pendingOpen = nil
        focusReply(target.messageId, at: target.date)
    }

    /// Экран выполнил просьбу прокрутки.
    public func consumeScroll() {
        scrollTarget = nil
    }

    /// Страница новее окна перехода, когда низ окна показался. Дойдя до живой ленты, окно
    /// сливается с ней, и лента снова живая.
    public func loadNewer() async {
        guard let current = window, !current.joined, !isLoadingNewer, let newest = current.messages.last else { return }
        isLoadingNewer = true
        defer { isLoadingNewer = false }
        do {
            let page = try await repository.historyAround(
                chatId: chatId, messageId: newest.serverId ?? newest.id, at: newest.timestamp,
                forward: Self.windowPage, backward: 0
            )
            // Пока страница шла, окно могли закрыть или пополнить.
            guard var latest = window, !latest.joined else { return }
            let added = latest.append(page)
            if added == 0 || latest.meets(live) { latest.join(live) }
            pagingInFlight = true
            setWindow(latest)
            pagingInFlight = false
        } catch {
            guard !error.isRateLimit else { return }
            show(error)
        }
    }

    /// Страница старше окна перехода, когда его верх показался.
    private func loadOlderInWindow() async {
        guard let current = window, !current.reachedOldest, let oldest = current.messages.first else { return }
        isLoadingOlder = true
        olderFailed = false
        defer { isLoadingOlder = false }
        do {
            let page = try await repository.historyAround(
                chatId: chatId, messageId: oldest.serverId ?? oldest.id, at: oldest.timestamp,
                forward: 0, backward: Self.windowPage
            )
            guard var latest = window else { return }
            if latest.prepend(page) == 0 { latest.reachedOldest = true }
            pagingInFlight = true
            setWindow(latest)
            pagingInFlight = false
        } catch {
            olderFailed = true
            guard !error.isRateLimit else { return }
            show(error)
        }
    }

    /// Сообщение у низа экрана, пока читатель листает: всё до него прочитано глазами.
    public func noteBottomVisible(_ id: String?) {
        guard let id, let message = Self.find(id, in: messages) else { return }
        markSeen(message.timestamp)
    }

    /// Лента у низа живой ленты: непрочитанных ниже нет, возвраты к цитатам больше не нужны.
    public func noteAtBottom() {
        guard !isJumped else { return }
        returnStack.removeAll()
        if let last = live.last?.timestamp { markSeen(last) }
    }

    // MARK: Отметка прочтения

    /// Что видно в ленте: `newestSeen` — самое новое сообщение, у которого в видимой области
    /// (без шапки, поля ввода и клавиатуры) не меньше `ReadMarkRules.minVisibleFraction` высоты
    /// (`ReadVisibility.newestSeen`); `atBottom` — лента у низа живой ленты и следует за новыми.
    /// Чат читается до самого нового увиденного сообщения.
    public func noteVisible(newestSeen id: String?, atBottom: Bool) {
        let following = atBottom && !isJumped
        var seen = id.flatMap { Self.find($0, in: messages) }.map { ReadMark.time(of: $0) }
        if following, let last = messages.last { seen = max(seen ?? 0, ReadMark.time(of: last)) }
        readProgress.see(seen, following: following)
        proposeReadMark()
    }

    /// Экран чата на виду (`true`) или нет: закрыт, перекрыт, приложение ушло в фон или стало
    /// неактивным. Уход снимает ещё не ушедшую отметку — невидимое не читается; возврат читает
    /// то, что видно.
    public func setScreenActive(_ active: Bool) {
        readScreenActive = active
        if active {
            proposeReadMark()
        } else {
            readMarks?.cancel()
        }
    }

    /// Экран чата ушёл (закрыли чат, сверху открылся другой экран): ждущая отметка снята, а
    /// увиденное этого показа забыто — следующий показ сообщит своё.
    public func endReadSession() {
        setScreenActive(false)
        readProgress.endShowing()
    }

    /// Кандидат в отметку (`ReadProgress.candidate`): у низа — последнее чужое сообщение живой
    /// ленты, иначе самое новое увиденное, и только новее прочитанного при открытии. Когда
    /// отметка уйдёт, решает `ReadMarkScheduler`.
    private func proposeReadMark() {
        guard readScreenActive, !markingUnread, chats != nil, let readMarks else {
            if !readScreenActive || markingUnread {
                DiagnosticEvent.event("read-mark", ["stage": "blocked", "chat": DiagnosticEvent.id(chatId),
                    "screen_active": String(readScreenActive), "marking_unread": String(markingUnread)])
            }
            return
        }
        let me = currentUserId
        let candidate = readProgress.candidate(shown: messages, live: live) { !me.isEmpty && $0.authorId == me }
        guard let mark = candidate else { return }
        if mark.isNewer(than: readMarks.sent), mark.isNewer(than: readMarks.pending) {
            DiagnosticEvent.event("read-mark", ["stage": "propose", "chat": DiagnosticEvent.id(chatId),
                "message": DiagnosticEvent.id(mark.messageId), "mark": String(mark.time),
                "following": String(readProgress.following), "seen": String(readProgress.seen),
                "floor": String(readProgress.floor)])
        }
        readMarks.propose(mark)
    }

    /// Отметка уходит через ядро (`markReadAt`): при скрытых отметках о прочтении оно читает
    /// чат только на устройстве. Ошибка не показывается: отметку повторит следующий кандидат.
    private func sendReadMark(_ mark: ReadMark) async -> Bool {
        guard let chats else { return false }
        do {
            try await chats.markRead(chatId: chatId, messageId: mark.messageId, at: mark.time)
            return true
        } catch {
            return false
        }
    }

    /// Экран чата закрывается. Внизу живой ленты место не хранится: чат откроется на свежих.
    /// Окно перехода при следующем открытии уже закрыто — его место тоже нет.
    public func savePlace(_ id: String?, atBottom: Bool) {
        savedPlace = atBottom || isJumped ? nil : id
    }

    /// Место прошлого захода, если его сообщение есть в ленте: чат открывается на нём.
    public var restoredPlace: String? {
        guard let savedPlace, Self.find(savedPlace, in: messages) != nil else { return nil }
        return savedPlace
    }

    /// Верхняя из видимых строк (id в любом порядке; чужие id, вроде метки низа, не считаются).
    public func topRow(among visible: [String]) -> String? {
        guard let top = visible.compactMap({ rowIndex[$0] }).min(), rows.indices.contains(top) else { return nil }
        return rows[top].id
    }

    /// Место строки в ленте (больше — новее): экран по нему выбирает самое новое увиденное.
    public func rowOrder(of id: String) -> Int? {
        rowIndex[id]
    }

    /// Над строкой стоит свой разделитель даты (первое сообщение дня): плавающая плашка с той же
    /// датой рядом с ним не нужна.
    public func rowShowsDay(_ id: String?) -> Bool {
        guard let id, let index = rowIndex[id], rows.indices.contains(index) else { return false }
        return rows[index].dayTitle != nil
    }

    /// Дата сообщения строки — плашка над лентой во время прокрутки.
    public func dayTitle(ofRow id: String?, now: Date = Date()) -> String? {
        guard let id, let index = rowIndex[id], rows.indices.contains(index) else { return nil }
        return ChatContentFormat.dayTitle(rows[index].message.timestamp, now: now)
    }

    /// Сколько сообщений окна перехода вокруг цели: чуть больше после неё.
    static let aroundBackward = 25
    static let aroundForward = 35
    /// Страница при листании окна перехода.
    static let windowPage = 40
    /// Сколько страниц сверх окна ленты открытие чата догружает ради первого непрочитанного.
    static let unreadPages = 4

    private static func find(_ id: String, in list: [Message]) -> Message? {
        list.first { $0.id == id || $0.serverId == id }
    }

    private func request(_ target: ChatScrollTarget) {
        scrollTarget = target
        scrollToken += 1
    }

    private func focus(on id: String) {
        request(.message(id, highlight: true))
        highlightedId = id
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, self.highlightedId == id else { return }
            self.highlightedId = nil
        }
    }

    private func noteReturn(from source: String?, to target: String) {
        guard let source, source != target, returnStack.last != source else { return }
        returnStack.append(source)
        if returnStack.count > 20 { returnStack.removeFirst() }
    }

    /// Лента показывает окно перехода или, без него, живую ленту.
    private func setWindow(_ value: TimelineWindow?) {
        window = value
        let shown = value?.messages ?? live
        if messages != shown { messages = shown }
    }

    /// Новая живая лента из репозитория.
    private func receiveLive(_ page: [Message]) {
        live = page
        defer { proposeReadMark() }
        if var current = window {
            if current.joined {
                current.absorb(page)
                window = current
                if messages != current.messages { messages = current.messages }
            } else {
                // Лента показывает старую историю: закреп и счётчик «вниз» берутся из живой.
                pins.applyState()
                recountUnreadBelow()
            }
        } else if messages != page {
            messages = page
        }
    }

    /// Своё сообщение ложится вниз живой ленты: окно перехода закрывается, лента едет вниз.
    private func returnToLiveForSending() {
        returnStack.removeAll()
        guard isJumped else { return }
        setWindow(nil)
        request(.bottom)
    }

    /// Время сообщения перед первым непрочитанным: до него всё прочитано.
    private func readBefore(_ anchorId: String) -> Date? {
        guard let index = live.firstIndex(where: { $0.id == anchorId }) else { return nil }
        return index > 0 ? live[index - 1].timestamp : live[index].timestamp.addingTimeInterval(-0.001)
    }

    /// Отметка «долистал» при открытии: до первого непрочитанного или до последнего сообщения.
    /// Пока непрочитанные ждут места в ленте, отметки нет.
    private func settleSeen() {
        guard seenUpTo == nil, !isRestoringHistory, !live.isEmpty else { return }
        if let anchor = unreadAnchorId, let before = readBefore(anchor) {
            seenUpTo = before
        } else if pendingUnread == 0 {
            seenUpTo = live.last?.timestamp
        } else {
            return
        }
        // Всё до этого места было прочитано ещё до открытия: отметка о нём не нужна.
        if let seenUpTo { readProgress.noteReadAtOpen(ReadMark.time(of: seenUpTo)) }
        recountUnreadBelow()
    }

    private func markSeen(_ time: Date) {
        guard let seen = seenUpTo, time > seen else { return }
        seenUpTo = time
        recountUnreadBelow()
    }

    /// Чужие сообщения живой ленты новее отметки «долистал» и упоминания себя среди них.
    private func recountUnreadBelow() {
        var count = 0
        var mentions: [String] = []
        if let seen = seenUpTo {
            for message in live where message.timestamp > seen && !isOutgoing(message) && !message.content.isService {
                count += 1
                if mentionsMe(message), !visitedMentions.contains(message.id) { mentions.append(message.id) }
            }
        }
        if count != unreadBelow { unreadBelow = count }
        if mentions != unreadMentions { unreadMentions = mentions }
    }

    /// Флаги ленты для экрана; меняются, только когда меняется их значение.
    private func refreshHistoryFlags() {
        let empty = latestLoaded && messages.isEmpty && !isRestoringHistory && historyError == nil
        if empty != isHistoryEmpty { isHistoryEmpty = empty }
        let own = messages.contains { isOutgoing($0) }
        if own != hasOwnMessages { hasOwnMessages = own }
    }

    /// В тексте сообщения упомянут этот аккаунт (`USER_MENTION` со своим id).
    private func mentionsMe(_ message: Message) -> Bool {
        guard !currentUserId.isEmpty else { return false }
        return message.content.formatting?.contains { $0.kind == .mention && $0.userId == currentUserId } == true
    }

    /// Кнопка «@»: лента едет к самому старому непрочитанному упоминанию и подсвечивает его.
    /// Оно сразу уходит из счётчика; остальные уходят, когда их долистали.
    public func jumpToNextMention() {
        guard let id = unreadMentions.first else { return }
        visitedMentions.insert(id)
        recountUnreadBelow()
        focusReply(id)
    }

    /// Непрочитанных больше, чем чужих в окне ленты: окно растёт страницами, пока первое
    /// непрочитанное не войдёт в него, но не больше `unreadPages` страниц — дальше разделитель
    /// встанет над самым старым. Считает по страницам репозитория, а не по ленте: подписка
    /// приносит окно позже.
    private func reachUnread(_ generation: Int) async {
        guard pendingUnread > 0 else { return }
        var shown = live
        if shown.isEmpty {
            shown = (try? await repository.loadMore(chatId: chatId, before: nil)) ?? []
        }
        var incoming = shown.filter { countsAsUnread($0) }.count
        var cursor = shown.map(\.timestamp).min()
        var pages = 0
        while incoming < pendingUnread, pages < Self.unreadPages, let before = cursor {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            guard let page = try? await repository.loadMore(chatId: chatId, before: before), !page.isEmpty else { break }
            pages += 1
            incoming += page.filter { countsAsUnread($0) }.count
            cursor = page.map(\.timestamp).min()
        }
        for _ in 0..<pages {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            try? await repository.loadOlder(chatId: chatId)
        }
    }

    private func countsAsUnread(_ message: Message) -> Bool {
        !isOutgoing(message) && !message.content.isService
    }

    public func openComments(_ message: Message) {
        guard comments != nil else { return }
        openedComments = message
    }

    /// Модель окна комментариев открытого поста. Одна на пост, пока окно не закрыто.
    public func commentsModel(for post: Message) -> CommentsViewModel? {
        guard let comments else { return nil }
        if let commentsModel, commentsModel.post.id == post.id { return commentsModel }
        let model = CommentsViewModel(
            chatId: chatId,
            post: post,
            currentUserId: currentUserId,
            comments: comments,
            reactionCatalog: reactions.catalog
        )
        commentsModel = model
        return model
    }

    public func closeComments() {
        let post = openedComments ?? commentsModel?.post
        openedComments = nil
        commentsModel = nil
        // После обсуждения счётчик мог измениться: спросить заново.
        if let post {
            let id = post.serverId ?? post.id
            askedCounts.remove(id)
            requestCommentCounts(for: [post])
        }
    }

    /// Число комментариев поста: ответ сервера, иначе счётчик из самого сообщения.
    public func commentCount(for message: Message) -> Int? {
        commentCounts[message.serverId ?? message.id] ?? message.content.comments?.count
    }

    /// Спросить счётчики комментариев у постов, которых ещё не спрашивали (пачками по 50).
    public func requestCommentCounts(for posts: [Message]) {
        guard let comments, Date() >= countsRetryAt else { return }
        let ids = posts.compactMap { post -> String? in
            let id = post.serverId ?? post.id
            guard Int64(id) != nil, !askedCounts.contains(id) else { return nil }
            return id
        }
        guard !ids.isEmpty else { return }
        askedCounts.formUnion(ids)
        let chatId = chatId
        Task { [weak self] in
            for start in stride(from: 0, to: ids.count, by: 50) {
                let chunk = Array(ids[start..<min(start + 50, ids.count)])
                do {
                    let counts = try await comments.counts(chatId: chatId, postIds: chunk)
                    guard let self else { return }
                    self.commentCounts.merge(counts) { _, new in new }
                    await self.repository.noteCommentCounts(chatId: chatId, counts: counts)
                } catch {
                    // Остальные пачки не уходят: сервер, скорее всего, ответит им too.many.requests.
                    guard let self else { return }
                    self.askedCounts.subtract(ids[start...])
                    self.countsRetryAt = Date().addingTimeInterval(Self.retryAfterError)
                    return
                }
            }
        }
    }

    /// Сохранённая история чата с вложениями и ссылками — для общих медиа профиля.
    public func sharedHistory() async -> [Message] {
        await repository.sharedHistory(chatId: chatId, limit: 3000)
    }

    /// Страница общих медиа с сервера для профиля, независимо от загруженной истории.
    public func sharedMedia(_ request: SharedMediaRequest) async -> [Message]? {
        await repository.sharedMedia(
            chatId: chatId, types: request.types, anchorId: request.anchorId,
            forward: request.forward, backward: request.backward
        )
    }

    // MARK: Расшифровка голосовых

    /// Расшифровать можно голосовое, уже принятое сервером.
    public func canTranscribe(_ message: Message) -> Bool {
        guard let voice = message.content.voices.first else { return false }
        if voice.transcript != nil { return true }
        return message.status == .sent && message.serverId.flatMap { Int64($0) } != nil && Int64(voice.id) != nil
    }

    public func transcriptPhase(for voice: VoiceContent) -> TranscriptPhase {
        if transcribing.contains(voice.id) { return .loading }
        if failedTranscripts.contains(voice.id) { return .failed }
        if openTranscripts.contains(voice.id), voice.transcript != nil { return .expanded }
        return .collapsed
    }

    /// «→T»: раскрыть расшифровку (запросив её у сервера, если её ещё нет) или свернуть.
    public func toggleTranscript(_ message: Message) {
        guard let voice = message.content.voices.first, !transcribing.contains(voice.id) else { return }
        // «^» у ошибки сворачивает её; следующее «→Т» спросит сервер заново.
        if failedTranscripts.remove(voice.id) != nil { return }
        if openTranscripts.contains(voice.id) {
            openTranscripts.remove(voice.id)
            return
        }
        if voice.transcript != nil {
            openTranscripts.insert(voice.id)
            return
        }
        guard canTranscribe(message) else { return }
        let id = voice.id
        transcribing.insert(id)
        Task { [weak self] in
            guard let self else { return }
            do {
                let ready = try await self.repository.transcribe(messageId: message.id, attachmentId: id)
                if ready {
                    // Текст уже в базе; снимок ленты с ним мог прийти раньше ответа.
                    if self.transcribing.remove(id) != nil { self.openTranscripts.insert(id) }
                    return
                }
                // Сервер ещё работает: текст придёт пушем (`settleTranscripts`).
                try? await Task.sleep(for: Self.transcriptWait)
                if self.transcribing.remove(id) != nil { self.failedTranscripts.insert(id) }
            } catch {
                // Ошибка — в самом пузыре, как в Komet, а не над полем ввода.
                self.transcribing.remove(id)
                if (error as? MaxlyError) != .cancelled { self.failedTranscripts.insert(id) }
            }
        }
    }

    /// Пришёл текст голосового, чья расшифровка шла: она раскрывается.
    private func settleTranscripts() {
        guard !transcribing.isEmpty else { return }
        for message in messages {
            for voice in message.content.voices where voice.transcript != nil && transcribing.contains(voice.id) {
                transcribing.remove(voice.id)
                openTranscripts.insert(voice.id)
            }
        }
    }

    // MARK: Удаление и пересылка

    /// Меню сообщения → «Удалить»: варианты решает ядро (`deletePlan`), как и для выбора
    /// нескольких. Нельзя удалить вовсе — плашка вместо диалога.
    public func requestDelete(_ message: Message) {
        Task { [weak self] in
            guard let self else { return }
            let options = await selection.deletePlan(for: [message])
            guard options.canDelete || deletesWithoutChoice else {
                showNotice("Это сообщение нельзя удалить")
                return
            }
            deletionOptions = options
            deletionCandidate = message
        }
    }

    /// «Удалить у всех» — только для своих сообщений, уже принятых сервером.
    /// «Избранное» принадлежит только аккаунту: сообщение удаляется на сервере целиком
    /// (`forMe: false`), и пересланное, и отправленное с другого устройства. Удаление
    /// «у себя» скрыло бы его лишь в этом клиенте.
    public func deletesEverywhere(_ message: Message) -> Bool {
        message.serverId.map { Int64($0) != nil } ?? false
    }

    /// Только «удалить у всех», без выбора (канал с правами).
    public var deletionForcesEveryone: Bool { deletionOptions?.forcesForEveryone == true }

    /// Вариант «удалить у всех» есть; `deletionPrefersEveryone` — он идёт первым.
    public var deletionShowsEveryone: Bool { deletionOptions?.showsForEveryone == true }
    public var deletionPrefersEveryone: Bool { deletionOptions?.forEveryoneByDefault == true }

    /// Удаление из «Избранного»: собеседника нет, поэтому один вариант без выбора.
    public var deletesWithoutChoice: Bool { chatId == Chat.savedMessagesId }

    /// Чат — «Избранное». Приватный режим оставляет ему настоящее название.
    public var isSavedMessages: Bool { chatId == Chat.savedMessagesId }

    /// Удаление выбранного сообщения. Сообщение передаётся явно: диалог подтверждения
    /// сбрасывает `deletionCandidate` раньше, чем срабатывает его кнопка.
    public func confirmDelete(_ candidate: Message? = nil, forEveryone: Bool) async {
        guard let message = candidate ?? deletionCandidate else { return }
        deletionCandidate = nil
        if replyTarget?.id == message.id { replyTarget = nil }
        do {
            try await repository.delete(messageIds: [message.id], chatId: chatId, forEveryone: forEveryone)
            error = nil
        } catch {
            show(error)
        }
    }

    public func requestForward(_ message: Message) {
        forwardCandidate = message
    }

    // MARK: Непрочитанное

    /// Пометить непрочитанным можно сообщение, принятое сервером, кроме служебного о закрепе.
    public func canMarkUnread(_ message: Message) -> Bool {
        message.status == .sent && Int64(message.serverId ?? message.id) != nil && !message.content.isService
    }

    /// Чат помечают непрочитанным с этого сообщения. Экран передаёт пометку списку чатов и
    /// закрывается: открытый чат тут же отметился бы прочитанным.
    public func requestMarkUnread(_ message: Message) {
        guard canMarkUnread(message) else { return }
        // Отметка, ждущая паузы, прочитала бы чат обратно.
        markingUnread = true
        readMarks?.reset()
        unreadMarkCandidate = message
    }

    public func forward(to targetChatId: String) async {
        guard let message = forwardCandidate else { return }
        forwardCandidate = nil
        do {
            try await repository.forward(messageId: message.serverId ?? message.id, from: chatId, to: targetChatId)
            error = nil
            showNotice("Сообщение переслано")
        } catch {
            show(error)
        }
    }

    /// «Поделиться контактом» из профиля: карточка `userId` уходит в чат `targetChatId`.
    public func shareContact(userId: String, name: String, to targetChatId: String) async {
        let card = AttachmentDraft(kind: .contact, contactId: userId, contactName: name)
        do {
            try await repository.sendAttachments([card], caption: "", chatId: targetChatId, replyTo: nil)
            showNotice("Контакт отправлен")
        } catch {
            show(error)
        }
    }

    /// Своя роль в этой группе или канале: владельцу в профиле — «Удалить канал».
    public func ownRole() async -> ChatOwnRole {
        await repository.ownRole(chatId: chatId) ?? ChatOwnRole(isOwner: false, isAdmin: false)
    }

    /// Короткое уведомление над полем ввода от экрана («Скопировано»).
    public func announce(_ text: String) {
        showNotice(text)
    }

    private func showNotice(_ text: String) {
        notice = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.notice == text else { return }
            self.notice = nil
        }
    }

    public func retry(id: String) async {
        do {
            try await repository.retry(messageId: id)
        } catch {
            show(error)
        }
    }

    private func show(_ failure: MaxlyError) {
        if failure != .cancelled { error = failure }
    }

    /// Собеседник личного чата. Нужен командам бота и звонку.
    public func notePeer(_ id: String?, isBot: Bool) {
        let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        peerId = (trimmed?.isEmpty == false) ? trimmed : nil
        peerIsBot = isBot
    }

    public func insertMention(_ member: ChatMemberRef) {
        guard let at = draft.range(of: "@", options: .backwards) else { return }
        let token = "@\(member.name)"
        let prefix = String(draft[..<at.lowerBound])
        mentionDraft.insert(text: token, userId: member.id)
        draft = prefix + token + " "
        mentionHints = []
    }

    public func insertCommand(_ command: BotCommandRef) {
        let raw = command.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        guard !name.isEmpty else { return }
        draft = "/" + name + " "
        commandHints = []
    }

    private func refreshComposerHints() {
        let mention = Self.query(in: draft, marker: "@")
        let command = Self.query(in: draft, marker: "/")
        if mention != nil, !membersAsked, let chats {
            membersAsked = true
            Task { [weak self] in
                guard let self else { return }
                do {
                    memberRows = try await chats.members(chatId: chatId)
                } catch {
                    membersAsked = false
                }
                publishHints()
            }
        }
        if command != nil, peerIsBot, let peerId, !commandsAsked, let chats {
            commandsAsked = true
            Task { [weak self] in
                guard let self else { return }
                do {
                    commandRows = try await chats.botCommands(botId: peerId)
                } catch {
                    commandsAsked = false
                }
                publishHints()
            }
        }
        publishHints()
    }

    private func publishHints() {
        let mention = Self.query(in: draft, marker: "@")
        let command = Self.query(in: draft, marker: "/")
        mentionHints = mention.map { needle in
            memberRows.filter { $0.name.localizedCaseInsensitiveContains(needle) }.prefix(8).map { $0 }
        } ?? []
        commandHints = (command == nil || !peerIsBot) ? [] : commandRows.filter {
            let name = $0.name.hasPrefix("/") ? String($0.name.dropFirst()) : $0.name
            return name.localizedCaseInsensitiveContains(command ?? "")
        }.prefix(8).map { $0 }
    }

    private static func query(in text: String, marker: Character) -> String? {
        guard let at = text.lastIndex(of: marker) else { return nil }
        let tail = text[text.index(after: at)...]
        if tail.contains(where: \.isWhitespace) { return nil }
        return String(tail)
    }
}

/// Запуск мини-приложения бота из чата: кнопка «Открыть приложение» или inline-кнопка `OPEN_APP`.
public struct BotAppRequest: Identifiable, Equatable, Sendable {
    public let botId: String
    public let chatId: String
    public let startParam: String?
    public let title: String

    public var id: String { "\(botId):\(startParam ?? "")" }

    public init(botId: String, chatId: String, startParam: String?, title: String) {
        self.botId = botId
        self.chatId = chatId
        self.startParam = startParam
        self.title = title
    }
}
