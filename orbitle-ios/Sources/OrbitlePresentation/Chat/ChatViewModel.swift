import Foundation
import Observation
import OrbitleDomain

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
            if !isRestoringHistory, Self.contentChanged(from: oldValue, to: messages) { contentVersion &+= 1 }
            if ids != oldIds { transcriptVersion &+= 1 }
            rows = TranscriptLayout.rows(messages, currentUserId: currentUserId)
            settleTranscripts()
        }
    }
    /// Голосовые (id вложения), чья расшифровка идёт: текст ещё не пришёл.
    public private(set) var transcribing: Set<String> = []
    /// Голосовые, у которых расшифровка раскрыта.
    public private(set) var openTranscripts: Set<String> = []
    /// Столько ждём пуша с текстом, если сервер ответил «ещё расшифровываю».
    static let transcriptWait: Duration = .seconds(60)
    /// Строки ленты с разделителями дней, склейкой и подписями автора (`TranscriptLayout`).
    public private(set) var rows: [TranscriptRow] = []
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
            // Текст правки не черновик: его не сохраняем.
            guard draft != oldValue, !isRestoringDraft, editTarget == nil else { return }
            scheduleDraftSave()
        }
    }
    public private(set) var error: OrbitleError?
    public private(set) var stickToBottom = true
    /// Цитата над полем ввода.
    public private(set) var replyTarget: Message?
    /// Сообщение, текст которого сейчас правится в поле ввода.
    public private(set) var editTarget: Message?
    /// Черновик, отложенный на время правки.
    @ObservationIgnored private var draftBeforeEdit = ""
    public private(set) var voicePhases: [String: VoicePhase] = [:]
    public private(set) var scrollTarget: String?
    public private(set) var scrollToken = 0
    public private(set) var highlightedId: String?
    /// Пост, чьи комментарии открыты в модальном окне.
    public var openedComments: Message?
    /// Число комментариев под постами канала (id поста на сервере → число).
    public private(set) var commentCounts: [String: Int] = [:]
    /// Сообщение, для которого открыт выбор «удалить у себя / у всех».
    public var deletionCandidate: Message?
    /// Сообщение, для которого открыт выбор чата пересылки.
    public var forwardCandidate: Message?
    /// Короткое уведомление над полем ввода («Переслано»). Само пропадает.
    public private(set) var notice: String?
    /// Просмотр фото и видео.
    public var viewer: MediaViewerRequest?
    /// Кружок, который играет прямо в ленте (не на весь экран).
    public private(set) var roundPlayback: RoundPlayback?
    /// Открытый файл.
    public var openedFile: OpenedFile?
    /// Открытое окно «Сохранить в Файлы».
    public var fileExport: FileExport?
    /// Идёт сохранение (скачивание перед ним): повторное нажатие ждёт.
    public private(set) var isSaving = false
    /// Вложение, для которого сейчас запрашивается ссылка или качается файл: пузырь рисует на нём загрузку.
    public private(set) var loadingMediaId: String?
    /// Диалог открыт из контактов, и на сервере его может ещё не быть: пустая история не
    /// ошибка, экран предлагает написать первое сообщение.
    public let isNewDialog: Bool
    /// Каталог реакций сервера. Пуст, пока не загрузился: меню берёт запасной набор.
    public private(set) var reactionCatalog: [String] = []
    /// Сообщение, для которого открыт полный выбор реакций.
    public var reactionPickerTarget: Message?
    /// Открытый список «Кто отреагировал».
    public var reactionUsers: ReactionUsersViewModel?
    @ObservationIgnored private var catalogRequested = false
    /// Ход загрузки вложений своих сообщений: id сообщения → доля 0…1.
    public private(set) var uploadProgress: [String: Double] = [:]
    @ObservationIgnored private var progressWatch: Task<Void, Never>?

    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private let drafts: (any ChatDraftStore)?
    @ObservationIgnored private let media: (any MediaRepository)?
    @ObservationIgnored private let links: (any MediaLinkResolver)?
    @ObservationIgnored private let comments: (any CommentsRepository)?
    /// Посты, чьи счётчики уже спрошены: один запрос на пост за время жизни экрана.
    @ObservationIgnored private var askedCounts: Set<String> = []
    /// Посты, чьи реакции уже спрошены отдельным запросом.
    @ObservationIgnored private var askedReactions: Set<String> = []
    /// Прямые адреса видео, полученные у сервера за время жизни экрана.
    @ObservationIgnored private var resolvedVideos: [String: URL] = [:]
    @ObservationIgnored private var mediaTask: Task<Void, Never>?
    @ObservationIgnored private let voice: (any VoicePlaying)?
    @ObservationIgnored private let draftDelay: Duration
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var draftSave: Task<Void, Never>?
    @ObservationIgnored private var isRestoringDraft = false
    @ObservationIgnored private var saveChain: Task<Void, Never>?
    /// Последний текст, отданный хранилищу: не пишем одно и то же дважды.
    @ObservationIgnored private var savedDraft: String?
    @ObservationIgnored private var activeVoiceId: String?
    @ObservationIgnored private var voiceTask: Task<Void, Never>?
    @ObservationIgnored private var voiceToggle: Task<Void, Never>?
    @ObservationIgnored private var fileTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let gallery: (any GallerySaving)?
    @ObservationIgnored private var commentsModel: CommentsViewModel?

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
        isNewDialog: Bool = false
    ) {
        self.isNewDialog = isNewDialog
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.repository = messages
        self.drafts = drafts
        self.draftDelay = draftDelay
        self.media = media
        self.links = links
        self.comments = comments
        self.voice = voice
        self.gallery = gallery
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
    public private(set) var latestLoaded = false
    /// Кэш и серверная сверка при каждом открытии не являются live-вставками.
    public private(set) var isRestoringHistory = false
    @ObservationIgnored private var watchGeneration = 0

    /// Пустое «Избранное»: вместо ленты плашка о том, что это за чат.
    public var showsSavedPlaceholder: Bool {
        chatId == Chat.savedMessagesId && latestLoaded && messages.isEmpty
    }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func isOutgoing(_ message: Message) -> Bool {
        !currentUserId.isEmpty && message.authorId == currentUserId
    }

    public func activate() {
        guard watch == nil else { return }
        loadReactionCatalog()
        startMessagesWatch()
        let progress = repository.uploadProgress()
        progressWatch = Task { [weak self] in
            for await snapshot in progress {
                guard let self else { return }
                self.uploadProgress = snapshot
            }
        }
        if let drafts {
            let chatId = chatId
            Task { [weak self] in
                let saved = await drafts.draft(chatId: chatId)
                guard let self, let saved, self.draft.isEmpty else { return }
                self.savedDraft = saved
                self.isRestoringDraft = true
                self.draft = saved
                self.isRestoringDraft = false
            }
        }
    }

    private func startMessagesWatch(finishesRestoration: Bool = false) {
        watch?.cancel()
        watchGeneration &+= 1
        let generation = watchGeneration
        let stream = repository.messages(chatId: chatId)
        watch = Task { [weak self] in
            var first = true
            for await page in stream {
                guard let self, !Task.isCancelled, self.watchGeneration == generation else { return }
                self.messages = page
                if first, finishesRestoration {
                    self.messagesChange = .reload
                    self.isRestoringHistory = false
                }
                first = false
            }
        }
    }

    public func deactivate() {
        watchGeneration &+= 1
        isRestoringHistory = false
        watch?.cancel()
        watch = nil
        progressWatch?.cancel()
        progressWatch = nil
        stopVoice()
        fileTask?.cancel()
        fileTask = nil
        mediaTask?.cancel()
        mediaTask = nil
        loadingMediaId = nil
        openedFile = nil
        flushDraft()
    }

    /// Сохранить черновик сразу, не дожидаясь паузы в наборе.
    public func flushDraft() {
        draftSave?.cancel()
        draftSave = nil
        persistDraft()
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
        guard text != (savedDraft ?? "") else { return }
        savedDraft = text
        let chatId = chatId
        // Записи идут цепочкой: иначе поздний пустой черновик мог бы лечь раньше раннего.
        let previous = saveChain
        saveChain = Task {
            await previous?.value
            await drafts.saveDraft(text, chatId: chatId)
        }
    }

    public func loadLatest() async {
        isRestoringHistory = true
        defer {
            // Новый stream даёт авторитетный снимок после сверки, без гонки с очередью
            // старого подписчика. Первый снимок завершает восстановление без анимаций.
            if watch != nil { startMessagesWatch(finishesRestoration: true) }
            else { isRestoringHistory = false }
        }
        do {
            try await repository.fetchLatest(chatId: chatId)
            latestLoaded = true
            error = nil
        } catch {
            // Истории нового диалога на сервере может не быть: это не ошибка для экрана.
            if isNewDialog, messages.isEmpty, error != .networkUnavailable { return }
            show(error)
        }
    }

    /// Вложения из листа: делятся на сообщения (`AttachmentBatchPlanner`), цитата уходит
    /// с первым. Каждое сообщение появляется сразу и грузится в фоне.
    public func sendAttachments(_ drafts: [AttachmentDraft], caption: String) async {
        let plan = AttachmentBatchPlanner.plan(drafts, caption: caption)
        guard !plan.batches.isEmpty else { return }
        var reply = replyTarget?.id
        replyTarget = nil
        stickToBottom = true
        do {
            for batch in plan.batches {
                try await repository.sendAttachments(batch.drafts, caption: batch.caption, chatId: chatId, replyTo: reply)
                reply = nil
            }
            if !plan.trailingText.isEmpty {
                try await repository.send(text: plan.trailingText, chatId: chatId, replyTo: nil)
            }
            error = nil
        } catch {
            show(error)
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
        stickToBottom = false
        do {
            try await repository.loadOlder(chatId: chatId)
        } catch {
            if isNewDialog, messages.isEmpty, error != .networkUnavailable { return }
            show(error)
        }
    }

    public func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let target = editTarget {
            await saveEdit(target, text: text)
            return
        }
        let reply = replyTarget
        draft = ""
        replyTarget = nil
        stickToBottom = true
        do {
            try await repository.send(text: text, chatId: chatId, replyTo: reply?.id)
            error = nil
        } catch {
            draft = text
            replyTarget = reply
            show(error)
        }
    }

    public func beginReply(to message: Message) {
        if editTarget != nil { cancelEdit() }
        replyTarget = message
    }

    // MARK: Правка

    /// Править можно свой отправленный текст (не пересланный).
    public func canEdit(_ message: Message) -> Bool {
        isOutgoing(message) && message.status == .sent && message.serverId != nil
            && message.content.forward == nil
            && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Текст сообщения переходит в поле ввода; прежний черновик откладывается.
    public func beginEdit(_ message: Message) {
        guard canEdit(message) else { return }
        replyTarget = nil
        if editTarget == nil { draftBeforeEdit = draft }
        editTarget = message
        draft = message.text
    }

    public func cancelEdit() {
        guard editTarget != nil else { return }
        editTarget = nil
        draft = draftBeforeEdit
        draftBeforeEdit = ""
    }

    private func saveEdit(_ target: Message, text: String) async {
        if text == target.text.trimmingCharacters(in: .whitespacesAndNewlines) {
            cancelEdit()
            return
        }
        editTarget = nil
        let restore = draftBeforeEdit
        draftBeforeEdit = ""
        isRestoringDraft = true
        draft = restore
        isRestoringDraft = false
        do {
            try await repository.edit(messageId: target.id, chatId: chatId, text: text)
            error = nil
        } catch {
            // Правка не ушла: вернуть её в поле ввода.
            draftBeforeEdit = draft
            editTarget = target
            draft = text
            show(error)
        }
    }

    public func cancelReply() {
        replyTarget = nil
    }

    // MARK: Реакции

    /// Реакции ставятся на сообщения, уже принятые сервером.
    public func canReact(_ message: Message) -> Bool {
        message.status == .sent && message.serverId.flatMap { Int64($0) } != nil
    }

    /// Быстрый ряд меню сообщения: начало каталога, своя реакция всегда в нём.
    public func quickReactions(for message: Message) -> [String] {
        ReactionPalette.quick(catalog: reactionCatalog, mine: message.content.reactions.mine)
    }

    /// Поставить реакцию или снять свою. Лента меняется сразу, при отказе сервера
    /// возвращается прежнее и показывается ошибка.
    public func toggleReaction(messageId: String, emoji: String) async {
        do {
            try await repository.toggleReaction(messageId: messageId, emoji: emoji)
            if case .rejected(Self.reactionFailure)? = error { error = nil }
        } catch {
            switch error {
            case .cancelled:
                return
            case .rejected:
                show(error)
            default:
                show(.rejected(Self.reactionFailure))
            }
        }
    }

    /// Выбрана реакция в полном списке.
    public func pickReaction(_ emoji: String) async {
        guard let target = reactionPickerTarget else { return }
        reactionPickerTarget = nil
        await toggleReaction(messageId: target.id, emoji: emoji)
    }

    public func showMoreReactions(_ message: Message) {
        guard canReact(message) else { return }
        loadReactionCatalog()
        reactionPickerTarget = message
    }

    /// «Кто отреагировал»: есть в группах, если под сообщением есть реакции.
    public func showReactionUsers(_ message: Message) {
        guard canReact(message), !message.content.reactions.isEmpty else { return }
        reactionUsers = ReactionUsersViewModel(message: message, repository: repository)
    }

    /// Сверить реакции показанных сообщений с сервером: при возврате в приложение пуши
    /// за время в фоне могли потеряться.
    public func refreshReactions() async {
        await repository.refreshReactions(chatId: chatId)
        // После фона реакции постов канала спрашиваются заново.
        askedReactions.removeAll()
    }

    /// Реакции показанных сообщений отдельным запросом (`MSG_GET_REACTIONS`): в истории канала
    /// их нет, а своя реакция с другого устройства видна только в нём. Каждое сообщение
    /// спрашивается один раз за открытие; своё переключение реакции не перезаписывается.
    public func requestReactions(for posts: [Message]) {
        let ids = posts.compactMap { post -> String? in
            guard post.status == .sent, let id = post.serverId, Int64(id) != nil, !askedReactions.contains(id) else { return nil }
            return id
        }
        guard !ids.isEmpty else { return }
        askedReactions.formUnion(ids)
        let chatId = chatId
        let repository = repository
        Task { await repository.syncReactions(chatId: chatId, messageIds: ids) }
    }

    private func loadReactionCatalog() {
        guard !catalogRequested else { return }
        catalogRequested = true
        let repository = repository
        Task { [weak self] in
            let catalog = await repository.reactionCatalog()
            guard let self else { return }
            if catalog.isEmpty {
                // Попробовать ещё раз при следующем открытии полного списка.
                self.catalogRequested = false
            } else {
                self.reactionCatalog = catalog
            }
        }
    }

    static let reactionFailure = "Не удалось обновить реакцию"

    /// Прокрутить к цитате, если она уже в загруженном окне.
    public func focusReply(_ messageId: String) {
        guard let match = messages.first(where: { $0.id == messageId || $0.serverId == messageId }) else { return }
        scrollTarget = match.id
        scrollToken += 1
        highlightedId = match.id
        let token = match.id
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, self.highlightedId == token else { return }
            self.highlightedId = nil
        }
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
            reactionCatalog: reactionCatalog
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
        guard let comments else { return }
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
                guard let counts = try? await comments.counts(chatId: chatId, postIds: chunk) else { continue }
                guard let self else { return }
                self.commentCounts.merge(counts) { _, new in new }
                await self.repository.noteCommentCounts(chatId: chatId, counts: counts)
            }
        }
    }

    /// Открывает просмотр фото и видео сообщения. У видео из Max нет адреса в самом вложении:
    /// перед открытием экран спрашивает у сервера прямые ссылки на ролики этого сообщения.
    public func presentMedia(_ message: Message, startId: String) {
        mediaTask?.cancel()
        loadingMediaId = nil
        // Повторное касание играющего кружка останавливает его.
        if roundPlayback?.id == startId {
            roundPlayback = nil
            return
        }
        let pending = message.content.visuals.compactMap(\.video)
            .filter { $0.playbackURL == nil && resolvedVideos[$0.id] == nil }
        guard let links, !pending.isEmpty else {
            showViewer(message, startId: startId)
            return
        }
        loadingMediaId = startId
        mediaTask = Task {
            for video in pending {
                guard !Task.isCancelled else { return }
                if let url = try? await links.link(
                    chatId: message.chatId,
                    messageId: message.serverId ?? message.id,
                    kind: .video,
                    attachmentId: video.id
                ) {
                    resolvedVideos[video.id] = url
                }
            }
            guard !Task.isCancelled else { return }
            loadingMediaId = nil
            showViewer(message, startId: startId)
        }
    }

    private func showViewer(_ message: Message, startId: String) {
        let slides = message.content.visuals.compactMap { attachment -> MediaSlide? in
            if let photo = attachment.photo {
                guard photo.displayURL != nil else { return nil }
                return MediaSlide(id: photo.id, stillURL: photo.displayURL, playURL: nil, isVideo: false)
            }
            if let video = attachment.video {
                let play = video.playbackURL ?? resolvedVideos[video.id]
                guard video.displayURL != nil || play != nil else { return nil }
                return MediaSlide(id: video.id, stillURL: video.displayURL, playURL: play, isVideo: play != nil)
            }
            return nil
        }
        let tappedVideo = message.content.visuals.compactMap(\.video).first { $0.id == startId }
        if let tappedVideo, tappedVideo.playbackURL == nil, resolvedVideos[tappedVideo.id] == nil {
            show(.rejected("Видео не удалось загрузить"))
        }
        if let tappedVideo, tappedVideo.isRound, let url = tappedVideo.playbackURL ?? resolvedVideos[tappedVideo.id] {
            stopVoice()
            playRound(tappedVideo.id, url: url)
            return
        }
        guard slides.contains(where: { $0.id == startId }) else { return }
        viewer = MediaViewerRequest(id: startId, slides: slides, messageId: message.id)
    }

    /// Запасной путь видео: поток не открылся — ролик скачивается целиком и играет с диска.
    public func downloadVideo(_ slide: MediaSlide) async -> URL? {
        guard let url = slide.playURL, !url.isFileURL, let media else { return slide.playURL }
        do {
            return try await media.preview(for: MediaItem(id: "video-\(slide.id)", type: .video, url: url, size: 0))
        } catch {
            show(error)
            return nil
        }
    }

    public func openFile(_ message: Message, attachmentId: String) {
        fileTask?.cancel()
        fileTask = Task { await self.loadFile(message, attachmentId: attachmentId) }
    }

    public func voicePhase(for id: String) -> VoicePhase {
        voicePhases[id] ?? .idle
    }

    /// Кружок играет из кэша («Видеосообщения» в «Данных и памяти»): ролик в полмегабайта
    /// качается целиком, а повторный просмотр не тянет его из сети. Не скачался — играет поток.
    private func playRound(_ id: String, url: URL) {
        guard !url.isFileURL, let media else {
            roundPlayback = RoundPlayback(id: id, url: url)
            return
        }
        loadingMediaId = id
        mediaTask = Task {
            let file = try? await media.preview(for: MediaItem(id: "note-\(id)", type: .videoNote, url: url, size: 0))
            guard !Task.isCancelled else { return }
            loadingMediaId = nil
            roundPlayback = RoundPlayback(id: id, url: file ?? url)
        }
    }

    /// Кружок доиграл или ушёл из ленты.
    public func stopRound(id: String) {
        if roundPlayback?.id == id { roundPlayback = nil }
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
        if openTranscripts.contains(voice.id), voice.transcript != nil { return .expanded }
        return .collapsed
    }

    /// «→T»: раскрыть расшифровку (запросив её у сервера, если её ещё нет) или свернуть.
    public func toggleTranscript(_ message: Message) {
        guard let voice = message.content.voices.first, !transcribing.contains(voice.id) else { return }
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
                if self.transcribing.remove(id) != nil { self.showNotice("Расшифровка ещё не готова, попробуйте позже") }
            } catch {
                self.transcribing.remove(id)
                self.show(error)
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

    public func toggleVoice(_ message: Message) {
        roundPlayback = nil
        voiceToggle?.cancel()
        voiceToggle = Task { await self.playVoice(message) }
    }

    public func stopVoice() {
        voiceToggle?.cancel()
        voiceToggle = nil
        voiceTask?.cancel()
        voiceTask = nil
        voice?.stop()
        if let id = activeVoiceId { voicePhases[id] = .idle }
        activeVoiceId = nil
    }

    private func playVoice(_ message: Message) async {
        guard let clip = message.content.voices.first else { return }
        if activeVoiceId == clip.id, voicePhase(for: clip.id).isPlaying {
            voice?.pause()
            voicePhases[clip.id] = .paused(voice?.progress ?? voicePhase(for: clip.id).progress)
            voiceTask?.cancel()
            voiceTask = nil
            return
        }
        if activeVoiceId == clip.id, case .paused = voicePhase(for: clip.id) {
            if voice?.resume() == true {
                voicePhases[clip.id] = .playing(voice?.progress ?? 0)
                trackVoice(clip.id)
            } else {
                voicePhases[clip.id] = .failed
            }
            return
        }
        stopVoicePlayback()
        activeVoiceId = clip.id
        if let file = clip.fileURL {
            startPlayback(clip.id, url: file)
            return
        }
        guard let item = clip.cacheItem(), let media else {
            voicePhases[clip.id] = .failed
            activeVoiceId = nil
            return
        }
        voicePhases[clip.id] = .downloading(0)
        do {
            let file = try await media.preview(for: item)
            guard !Task.isCancelled, activeVoiceId == clip.id else { return }
            await repository.noteDownloaded(messageId: message.id, attachmentId: clip.id, localPath: file.path)
            guard !Task.isCancelled, activeVoiceId == clip.id else { return }
            startPlayback(clip.id, url: file)
        } catch {
            guard activeVoiceId == clip.id else { return }
            voicePhases[clip.id] = .failed
            activeVoiceId = nil
        }
    }

    /// Останавливает плеер, не отменяя задачу, которая сейчас качает следующий файл.
    private func stopVoicePlayback() {
        voiceTask?.cancel()
        voiceTask = nil
        voice?.stop()
        if let id = activeVoiceId { voicePhases[id] = .idle }
        activeVoiceId = nil
    }

    private func startPlayback(_ id: String, url: URL) {
        guard let voice, voice.play(url: url) else {
            voicePhases[id] = .failed
            activeVoiceId = nil
            return
        }
        voicePhases[id] = .playing(0)
        trackVoice(id)
    }

    private func trackVoice(_ id: String) {
        voiceTask?.cancel()
        voiceTask = Task { @MainActor [weak self] in
            var seenPlaying = false
            var silentTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.activeVoiceId == id else { return }
                if self.voice?.failed == true {
                    self.voicePhases[id] = .failed
                    self.activeVoiceId = nil
                    return
                }
                let playing = self.voice?.isPlaying ?? false
                let progress = self.voice?.progress ?? 0
                if playing {
                    seenPlaying = true
                    silentTicks = 0
                    self.voicePhases[id] = .playing(progress)
                } else if seenPlaying {
                    self.voicePhases[id] = .idle
                    self.activeVoiceId = nil
                    self.voice?.stop()
                    return
                } else {
                    silentTicks += 1
                    // Плеер принял файл, но так и не начал. Иначе пузырь крутится бесконечно.
                    if silentTicks >= 15 {
                        self.voice?.stop()
                        self.voicePhases[id] = .failed
                        self.activeVoiceId = nil
                        return
                    }
                }
            }
        }
    }

    private func loadFile(_ message: Message, attachmentId: String) async {
        guard let file = message.content.files.first(where: { $0.id == attachmentId }) else { return }
        if let local = file.fileURL {
            guard !Task.isCancelled else { return }
            openedFile = OpenedFile(id: file.id, url: Self.namedCopy(of: local, name: file.name, id: file.id), name: file.name)
            return
        }
        guard let media else { return }
        loadingMediaId = file.id
        defer { if loadingMediaId == file.id { loadingMediaId = nil } }
        do {
            var item = file.cacheItem()
            if item == nil, let links {
                // У файла из Max в сообщении только id: адрес выдаёт сервер (`FILE_DOWNLOAD`).
                let url = try await links.link(
                    chatId: message.chatId,
                    messageId: message.serverId ?? message.id,
                    kind: .file,
                    attachmentId: file.id
                )
                item = MediaItem(id: file.id, type: .file, url: url, size: file.size, localPath: nil)
            }
            guard let item else {
                show(.rejected("Файл недоступен"))
                return
            }
            let saved = try await media.preview(for: item)
            guard !Task.isCancelled else { return }
            await repository.noteDownloaded(messageId: message.id, attachmentId: file.id, localPath: saved.path)
            guard !Task.isCancelled else { return }
            openedFile = OpenedFile(id: file.id, url: Self.namedCopy(of: saved, name: file.name, id: file.id), name: file.name)
        } catch let failure as OrbitleError {
            guard !Task.isCancelled else { return }
            show(failure)
        } catch {
            guard !Task.isCancelled else { return }
            show(.storageError)
        }
    }

    // MARK: Сохранение на телефон

    /// Есть что сохранить: в «Фото» — фото, видео и кружки, в «Файлы» — любые вложения.
    public func canSave(_ message: Message, to target: SaveTarget) -> Bool {
        switch target {
        case .photos: gallery != nil && !message.content.visuals.isEmpty
        case .files: !Self.saveable(message, to: .files).isEmpty
        }
    }

    /// Сохранить вложения сообщения (или одно, `attachmentId`) в «Фото» или в «Файлы».
    /// Нескачанное сначала качается в кэш. `fromViewer` — нажато в просмотре фото.
    public func save(_ message: Message, to target: SaveTarget, attachmentId: String? = nil, fromViewer: Bool = false) {
        guard !isSaving else { return }
        var chosen = Self.saveable(message, to: target)
        if let attachmentId { chosen = chosen.filter { $0.id == attachmentId } }
        guard !chosen.isEmpty else { return }
        isSaving = true
        saveTask = Task {
            await self.performSave(chosen, of: message, to: target, fromViewer: fromViewer)
            self.isSaving = false
        }
    }

    /// Сохранить кадр, открытый в просмотре.
    public func saveViewerSlide(_ slideId: String, to target: SaveTarget) {
        guard let messageId = viewer?.messageId,
              let message = messages.first(where: { $0.id == messageId }) else { return }
        save(message, to: target, attachmentId: slideId, fromViewer: true)
    }

    /// Окно «Сохранить в Файлы» закрыто: `saved` — файлы записаны в выбранную папку.
    public func finishFileExport(saved: Bool) {
        let count = fileExport?.files.count ?? 0
        fileExport = nil
        if saved { showNotice(count > 1 ? "Сохранено в «Файлы»: \(count)" : "Сохранено в «Файлы»") }
    }

    static func saveable(_ message: Message, to target: SaveTarget) -> [ChatAttachment] {
        message.content.attachments.filter { attachment in
            switch attachment {
            case .photo, .video: true
            case .voice, .file: target == .files
            case .contact: false
            }
        }
    }

    private func performSave(_ attachments: [ChatAttachment], of message: Message, to target: SaveTarget, fromViewer: Bool) async {
        if attachments.count == 1 { loadingMediaId = attachments[0].id }
        defer { if attachments.count == 1, loadingMediaId == attachments[0].id { loadingMediaId = nil } }
        var files: [SavedFile] = []
        do {
            for (index, attachment) in attachments.enumerated() {
                files.append(try await savedFile(attachment, of: message, index: index))
            }
        } catch let failure as OrbitleError {
            guard !Task.isCancelled else { return }
            showNotice(failure.userMessage ?? "Не удалось сохранить")
            return
        } catch {
            showNotice("Не удалось сохранить")
            return
        }
        guard !Task.isCancelled else { return }
        switch target {
        case .photos:
            guard let gallery else { return }
            do {
                try await gallery.save(files)
                showNotice(Self.photosNotice(files))
            } catch let failure as OrbitleError {
                showNotice(failure.userMessage ?? "Не удалось сохранить в «Фото»")
            } catch {
                showNotice("Не удалось сохранить в «Фото»")
            }
        case .files:
            fileExport = FileExport(files: files, fromViewer: fromViewer)
        }
    }

    static func photosNotice(_ files: [SavedFile]) -> String {
        if files.count > 1 { return "Сохранено в «Фото»: \(files.count)" }
        return files.first?.kind == .video ? "Видео сохранено в «Фото»" : "Фото сохранено в «Фото»"
    }

    /// Файл вложения на устройстве с именем для сохранения. Фото и видео берутся из кэша
    /// под теми же id, что и при просмотре: уже открытое не качается заново.
    private func savedFile(_ attachment: ChatAttachment, of message: Message, index: Int) async throws(OrbitleError) -> SavedFile {
        switch attachment {
        case .photo(let photo):
            let local = try await localFile(
                existing: photo.localPath,
                item: photo.url.map { MediaItem(id: photo.id, type: .image, url: $0, size: 0) }
            )
            // Только JPG или PNG: WebP, HEIC и прочее с CDN перекодируются.
            let base = SaveNaming.name(for: message.timestamp, index: index, ext: "")
            let saved = try await SaveFormat.image(at: local, in: SaveFormat.folder(for: photo.id), baseName: base)
            return SavedFile(url: saved, name: saved.lastPathComponent, kind: .image)
        case .video(let video):
            var remote = video.url ?? resolvedVideos[video.id]
            if remote == nil, let links {
                remote = try await links.link(chatId: message.chatId, messageId: message.serverId ?? message.id, kind: .video, attachmentId: video.id)
                resolvedVideos[video.id] = remote
            }
            let item = remote.map {
                MediaItem(id: video.isRound ? "note-\(video.id)" : "video-\(video.id)", type: video.isRound ? .videoNote : .video, url: $0, size: 0)
            }
            let local = try await localFile(existing: video.localPath, item: item)
            // Всегда MP4: QuickTime (.mov) перекладывается в MP4 без перекодирования.
            let name = SaveNaming.name(for: message.timestamp, index: index, ext: "mp4")
            let saved = SaveFormat.folder(for: video.id).appending(path: name)
            try await SaveFormat.video(at: local, to: saved)
            return SavedFile(url: saved, name: name, kind: .video)
        case .voice(let clip):
            let local = try await localFile(existing: clip.localPath, item: clip.cacheItem())
            let name = SaveNaming.name(for: message.timestamp, index: index, ext: local.pathExtension.isEmpty ? "ogg" : local.pathExtension)
            return SavedFile(url: Self.namedCopy(of: local, name: name, id: clip.id), name: name, kind: .other)
        case .file(let file):
            var item = file.cacheItem()
            if item == nil, file.fileURL == nil, let links {
                let url = try await links.link(chatId: message.chatId, messageId: message.serverId ?? message.id, kind: .file, attachmentId: file.id)
                item = MediaItem(id: file.id, type: .file, url: url, size: file.size)
            }
            let local = try await localFile(existing: file.localPath, item: item)
            await repository.noteDownloaded(messageId: message.id, attachmentId: file.id, localPath: local.path)
            return SavedFile(url: Self.namedCopy(of: local, name: file.name, id: file.id), name: file.name, kind: .other)
        case .contact:
            throw .rejected("Контакт нельзя сохранить файлом")
        }
    }

    /// Свой файл, если он ещё на диске, иначе копия из кэша медиа (скачивается при нужде).
    private func localFile(existing path: String?, item: MediaItem?) async throws(OrbitleError) -> URL {
        if let path, FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        guard let item, let media else { throw .rejected("Файл недоступен") }
        if item.url.isFileURL, FileManager.default.fileExists(atPath: item.url.path) { return item.url }
        return try await media.preview(for: item)
    }

    /// Предпросмотр узнаёт тип файла по расширению, а в кэше файл лежит под id. Отдаём копию
    /// с настоящим именем во временной папке.
    static func namedCopy(of url: URL, name: String, id: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty, safe != url.lastPathComponent else { return url }
        let folder = id.filter { $0.isLetter || $0.isNumber }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "OrbitleFiles", directoryHint: .isDirectory)
            .appending(path: folder.isEmpty ? "file" : folder, directoryHint: .isDirectory)
        let target = directory.appending(path: safe)
        let manager = FileManager.default
        if manager.fileExists(atPath: target.path) { return target }
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: url, to: target)
            return target
        } catch {
            return url
        }
    }

    // MARK: Удаление и пересылка

    public func requestDelete(_ message: Message) {
        deletionCandidate = message
    }

    /// «Удалить у всех» — только для своих сообщений, уже принятых сервером.
    /// «Избранное» принадлежит только аккаунту: сообщение удаляется на сервере целиком
    /// (`forMe: false`), и пересланное, и отправленное с другого устройства. Удаление
    /// «у себя» скрыло бы его лишь в этом клиенте.
    public func deletesEverywhere(_ message: Message) -> Bool {
        message.serverId.map { Int64($0) != nil } ?? false
    }

    public func canDeleteForEveryone(_ message: Message) -> Bool {
        isOutgoing(message) && message.status == .sent && message.serverId != nil
    }

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

    private func show(_ failure: OrbitleError) {
        if failure != .cancelled { error = failure }
    }
}
