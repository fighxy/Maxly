import Foundation
import Observation
import OrbitleDomain

/// Открытый чат: сообщения из репозитория, черновик, отправка и повтор.
@MainActor
@Observable
public final class ChatViewModel {
    public let chatId: String
    public let currentUserId: String
    public private(set) var messages: [Message] = []
    /// Текст в поле ввода. Сохраняется черновиком с короткой задержкой и при уходе с экрана.
    public var draft = "" {
        didSet {
            guard draft != oldValue, !isRestoringDraft else { return }
            scheduleDraftSave()
        }
    }
    public private(set) var error: OrbitleError?
    public private(set) var stickToBottom = true
    /// Цитата над полем ввода.
    public private(set) var replyTarget: Message?
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
    /// Открытый файл.
    public var openedFile: OpenedFile?
    /// Вложение, для которого сейчас запрашивается ссылка или качается файл: пузырь рисует на нём загрузку.
    public private(set) var loadingMediaId: String?
    /// Диалог открыт из контактов, и на сервере его может ещё не быть: пустая история не
    /// ошибка, экран предлагает написать первое сообщение.
    public let isNewDialog: Bool

    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private let drafts: (any ChatDraftStore)?
    @ObservationIgnored private let media: (any MediaRepository)?
    @ObservationIgnored private let links: (any MediaLinkResolver)?
    @ObservationIgnored private let comments: (any CommentsRepository)?
    /// Посты, чьи счётчики уже спрошены: один запрос на пост за время жизни экрана.
    @ObservationIgnored private var askedCounts: Set<String> = []
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
    }

    public var errorMessage: String? { error?.userMessage }

    /// Подсказка вместо пустой истории нового диалога.
    public var emptyHint: String? {
        guard isNewDialog, messages.isEmpty else { return nil }
        return "Здесь пока нет сообщений. Напишите первое — диалог появится в списке чатов."
    }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func isOutgoing(_ message: Message) -> Bool {
        !currentUserId.isEmpty && message.authorId == currentUserId
    }

    public func activate() {
        guard watch == nil else { return }
        let stream = repository.messages(chatId: chatId)
        watch = Task { [weak self] in
            for await page in stream {
                guard let self else { return }
                self.messages = page
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

    public func deactivate() {
        watch?.cancel()
        watch = nil
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
        do {
            try await repository.fetchLatest(chatId: chatId)
            error = nil
        } catch {
            // Истории нового диалога на сервере может не быть: это не ошибка для экрана.
            if isNewDialog, messages.isEmpty, error != .networkUnavailable { return }
            show(error)
        }
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
        replyTarget = message
    }

    public func cancelReply() {
        replyTarget = nil
    }

    public func toggleReaction(messageId: String, emoji: String) async {
        do {
            try await repository.setReaction(messageId: messageId, emoji: emoji)
        } catch {
            show(error)
        }
    }

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
        let model = CommentsViewModel(chatId: chatId, post: post, currentUserId: currentUserId, comments: comments)
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
            }
        }
    }

    /// Открывает просмотр фото и видео сообщения. У видео из Max нет адреса в самом вложении:
    /// перед открытием экран спрашивает у сервера прямые ссылки на ролики этого сообщения.
    public func presentMedia(_ message: Message, startId: String) {
        mediaTask?.cancel()
        loadingMediaId = nil
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
        guard slides.contains(where: { $0.id == startId }) else { return }
        viewer = MediaViewerRequest(id: startId, slides: slides)
    }

    public func openFile(_ message: Message, attachmentId: String) {
        fileTask?.cancel()
        fileTask = Task { await self.loadFile(message, attachmentId: attachmentId) }
    }

    public func voicePhase(for id: String) -> VoicePhase {
        voicePhases[id] ?? .idle
    }

    public func toggleVoice(_ message: Message) {
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
    public func canDeleteForEveryone(_ message: Message) -> Bool {
        isOutgoing(message) && message.status == .sent && message.serverId != nil
    }

    public func confirmDelete(forEveryone: Bool) async {
        guard let message = deletionCandidate else { return }
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
