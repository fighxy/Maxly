import Foundation
import Observation
import MaxlyDomain

/// Поле ввода открытого чата: черновик и его сохранение, разметка, анимодзи, упоминания,
/// подсказки `@` и `/`, ответ и правка, отправка текста, стикера и вложений, «я печатаю».
/// Ленту трогает только через хуки: перед отправкой она возвращается к живой и снимает
/// разделитель непрочитанных.
@MainActor
@Observable
public final class ComposerModel {
    public let chatId: String
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
            refreshHints()
            if !draft.isEmpty { typingReporter?.textEdited(chatId: chatId, canWrite: typingAllowed) }
        }
    }
    /// Подсказки `@` над полем ввода.
    public private(set) var mentionHints: [ChatMemberRef] = []
    /// Подсказки `/` для бота.
    public private(set) var commandHints: [BotCommandRef] = []
    /// Цитата над полем ввода. Входит в черновик: черновик из одного ответа тоже сохраняется.
    public private(set) var replyTarget: Message? {
        didSet {
            guard replyTarget?.id != oldValue?.id, !isRestoringDraft, editTarget == nil else { return }
            pendingDraftReply = nil
            scheduleDraftSave()
        }
    }
    /// Сообщение, текст которого сейчас правится в поле ввода.
    public private(set) var editTarget: Message?
    /// Разметка поля ввода (панель «Жирный», «Курсив», …), смещения UTF-16 по `draft`.
    public internal(set) var format = ComposerFormat()
    /// Выделение в поле (UTF-16 по `draft`); `nil` — ничего не выделено, панели нет.
    /// Задаёт экран: выделение в SwiftUI-поле видно с iOS 18.
    public var formatSelection: Range<Int>?
    /// Анимодзи, вставленные в поле из панели: уходят с текстом отметками `ANIMOJI`.
    @ObservationIgnored public private(set) var animojiDraft = AnimojiDraft()
    /// «Я печатаю» для собеседника (`MSG_TYPING` 65). `nil` — не отправляется.
    @ObservationIgnored public var typingReporter: TypingReporter?
    /// Можно ли писать в чат: экран ставит его по праву на поле ввода. Пока не поставил,
    /// «печатаю» не уходит (канал без прав, чат из поиска).
    @ObservationIgnored public var typingAllowed = false
    /// `edit-timeout` сервера в секундах; `nil` — неизвестен, срок правки не проверяется.
    @ObservationIgnored var editTimeoutSeconds: Int?

    /// Сообщение ленты по серверному id: цитата из черновика встаёт, когда оно загружено.
    @ObservationIgnored public var findReply: (String) -> Message? = { _ in nil }
    /// Бот личного чата, чьи команды подсказываются после `/`; `nil` — не бот.
    @ObservationIgnored public var bot: () -> String? = { nil }
    /// Уходит текст: разделитель непрочитанных больше не нужен.
    @ObservationIgnored public var onWillSendText: (() -> Void)?
    /// Уходит своё сообщение (текст, стикер, вложения): лента возвращается вниз живой.
    @ObservationIgnored public var onWillSend: (() -> Void)?
    @ObservationIgnored public var onSuccess: (() -> Void)?
    @ObservationIgnored public var onError: ((MaxlyError) -> Void)?

    @ObservationIgnored private let currentUserId: String
    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private let drafts: (any ChatDraftStore)?
    @ObservationIgnored private let chats: (any ChatRepository)?
    @ObservationIgnored private let draftDelay: Duration
    /// Ответ из черновика, сообщение которого ещё не в ленте (серверный id).
    @ObservationIgnored private var pendingDraftReply: String?
    /// Черновик и разметка, отложенные на время правки.
    @ObservationIgnored private var draftBeforeEdit = ""
    @ObservationIgnored private var formatBeforeEdit = ComposerFormat()
    @ObservationIgnored private var mentionDraft = MentionDraft()
    @ObservationIgnored private var memberRows: [ChatMemberRef] = []
    @ObservationIgnored private var commandRows: [BotCommandRef] = []
    @ObservationIgnored private var membersAsked = false
    @ObservationIgnored private var commandsAsked = false
    @ObservationIgnored private var draftSave: Task<Void, Never>?
    @ObservationIgnored private var isRestoringDraft = false
    @ObservationIgnored private var saveChain: Task<Void, Never>?
    /// Последний текст, отданный хранилищу: не пишем одно и то же дважды.
    @ObservationIgnored private var savedDraft: String?
    /// Ответ, записанный в черновик (серверный id).
    @ObservationIgnored private var savedReply: String?
    /// Подписка на черновики, изменённые не из этого поля.
    @ObservationIgnored private var draftWatch: Task<Void, Never>?

    public init(
        chatId: String,
        currentUserId: String,
        repository: any MessageRepository,
        drafts: (any ChatDraftStore)?,
        draftDelay: Duration,
        chats: (any ChatRepository)?
    ) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.repository = repository
        self.drafts = drafts
        self.draftDelay = draftDelay
        self.chats = chats
    }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Черновик

    /// Экран открыт: черновик берётся из хранилища, правки с других устройств — по подписке.
    func start() {
        guard let drafts else { return }
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

    /// С экрана ушли: запись голосового для «печатаю» кончилась, черновик сохраняется сразу.
    func stop() {
        typingReporter?.recordingStopped(chatId: chatId)
        draftWatch?.cancel()
        draftWatch = nil
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
    func resolveDraftReply() {
        guard let id = pendingDraftReply else { return }
        guard replyTarget == nil, editTarget == nil else {
            pendingDraftReply = nil
            return
        }
        guard let message = findReply(id) else { return }
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

    // MARK: Отправка

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
        onWillSendText?()
        animojiDraft.clear()
        mentionDraft.clear()
        replyTarget = nil
        onWillSend?()
        do {
            try await repository.send(text: text, chatId: chatId, replyTo: reply?.id, formatting: spans)
            onSuccess?()
        } catch {
            draft = text
            format = ComposerFormat(spans: marked.spans)
            animojiDraft = animoji
            mentionDraft = mentions
            replyTarget = reply
            onError?(error)
        }
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
        onWillSend?()
        do {
            for batch in plan.batches {
                try await repository.sendAttachments(batch.drafts, caption: batch.caption, chatId: chatId, replyTo: reply)
                reply = nil
            }
            if !plan.trailingText.isEmpty {
                try await repository.send(text: plan.trailingText, chatId: chatId, replyTo: nil)
            }
            onSuccess?()
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    /// Стикер уходит сразу отдельным сообщением; цитата — если отвечали.
    public func sendSticker(_ sticker: Sticker) async {
        await sendAttachments([.sticker(sticker)], caption: "")
    }

    // MARK: Ответ и правка

    public func beginReply(to message: Message) {
        if editTarget != nil { cancelEdit() }
        replyTarget = message
    }

    public func cancelReply() {
        replyTarget = nil
    }

    /// Сообщения удаляются: цитата на одно из них снимается с поля.
    func dropReply(ifIn ids: some Collection<String>) {
        guard let reply = replyTarget, ids.contains(reply.id) else { return }
        replyTarget = nil
    }

    /// Править можно свой отправленный текст (не пересланный), пока не вышел `edit-timeout`
    /// сервера (если ядро его знает).
    public func canEdit(_ message: Message) -> Bool {
        !currentUserId.isEmpty && message.authorId == currentUserId
            && message.status == .sent && message.serverId != nil
            && message.content.forward == nil
            && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && editTimeoutSeconds.map { Date().timeIntervalSince(message.timestamp) <= TimeInterval($0) } ?? true
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
            onSuccess?()
        } catch {
            // Правка не ушла: вернуть её в поле ввода.
            draftBeforeEdit = draft
            formatBeforeEdit = format
            editTarget = target
            draft = edited.text
            format = ComposerFormat(spans: edited.spans)
            onError?(error)
        }
    }

    // MARK: Разметка

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

    // MARK: Вставки

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

    private func refreshHints() {
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
        if command != nil, let botId = bot(), !commandsAsked, let chats {
            commandsAsked = true
            Task { [weak self] in
                guard let self else { return }
                do {
                    commandRows = try await chats.botCommands(botId: botId)
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
        commandHints = (command == nil || bot() == nil) ? [] : commandRows.filter {
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
}
