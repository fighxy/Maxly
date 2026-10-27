import Foundation
import Observation
import MaxlyDomain

/// Комментарии одного поста канала.
///
/// Обсуждение открывается с первого комментария: первая страница — сразу после поста, более
/// новые — страницами при прокрутке вниз.
/// Свой комментарий сразу виден со статусом «отправляется» и заменяется ответом сервера;
/// при ошибке он помечается неотправленным, а текст возвращается в поле ввода.
@MainActor
@Observable
public final class CommentsViewModel {
    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(String)
    }

    public let chatId: String
    /// Пост, под которым обсуждение. Рисуется над комментариями.
    public let post: Message
    public let currentUserId: String
    public private(set) var comments: [Message] = [] {
        didSet { commentsChange = CollectionChange.between(oldValue.map(\.id), comments.map(\.id)) }
    }
    /// Как обсуждение изменилось последним обновлением: подгрузка страниц — без анимации.
    public private(set) var commentsChange: CollectionChange = .none
    public private(set) var state: State = .loading
    /// На сервере есть комментарии новее загруженных.
    public private(set) var hasNewer = true
    public private(set) var isLoadingNewer = false
    public var draft = ""
    public private(set) var error: MaxlyError?

    /// Каталог реакций сервера из экрана чата. Пуст — меню берёт запасной набор.
    public let reactionCatalog: [String]

    @ObservationIgnored private let repository: any CommentsRepository
    @ObservationIgnored private let pageSize: Int
    /// Через сколько повторить первую страницу, если сервер ответил `too.many.requests`.
    @ObservationIgnored private let rateLimitRetry: Duration
    @ObservationIgnored private var loaded = false
    /// Время последнего комментария из страниц по порядку: следующая страница — после него.
    /// Свои только что отправленные комментарии его не двигают, иначе середина обсуждения
    /// осталась бы незагруженной.
    @ObservationIgnored private var newestLoaded: Date?
    /// Последний запрос реакции по id комментария: поздние ответы на прежние не применяются.
    @ObservationIgnored private var pendingReactions: [String: Int] = [:]
    @ObservationIgnored private var reactionRequest = 0

    public init(
        chatId: String,
        post: Message,
        currentUserId: String,
        comments: any CommentsRepository,
        pageSize: Int = 30,
        reactionCatalog: [String] = [],
        rateLimitRetry: Duration = .seconds(15)
    ) {
        self.chatId = chatId
        self.post = post
        self.currentUserId = currentUserId
        self.repository = comments
        self.pageSize = max(1, pageSize)
        self.reactionCatalog = reactionCatalog
        self.rateLimitRetry = rateLimitRetry
    }

    /// Серверный id поста: комментарии привязаны к нему.
    public var postId: String { post.serverId ?? post.id }

    public var errorMessage: String? { error?.userMessage }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Заголовок окна: число комментариев, пока они не загружены — из счётчика поста.
    public var title: String {
        let count = loaded ? comments.filter { $0.status != .failed }.count : (post.content.comments?.count ?? 0)
        guard count > 0 else { return "Комментарии" }
        return ChatContentFormat.comments(count)
    }

    public var emptyText: String? {
        state == .loaded && comments.isEmpty ? "Пока нет комментариев. Напишите первый." : nil
    }

    public func isOutgoing(_ message: Message) -> Bool {
        !currentUserId.isEmpty && message.authorId == currentUserId
    }

    /// Первая загрузка при открытии окна. Повторный вызов ничего не делает.
    public func load() async {
        guard !loaded else { return }
        await reload()
    }

    /// Первая страница заново: при открытии, по «Повторить» и по жесту обновления.
    public func reload() async {
        if comments.isEmpty { state = .loading }
        await fetchFirst(retryOnLimit: true)
    }

    /// Первая страница — сразу после поста. На `too.many.requests` окно не сдаётся сразу: оно
    /// ждёт паузу сервера, показывая загрузку, и спрашивает ещё раз. Второй отказ уже
    /// показывается с «Повторить».
    private func fetchFirst(retryOnLimit: Bool) async {
        do {
            var page = try await repository.comments(chatId: chatId, postId: postId, after: post.timestamp, limit: pageSize)
            var fromStart = true
            if page.isEmpty, (post.content.comments?.count ?? 0) > 0 {
                // Счётчик поста говорит, что комментарии есть, а страница от поста пуста:
                // показать хотя бы последние, как раньше, а не «пока нет комментариев».
                page = try await repository.comments(chatId: chatId, postId: postId, before: nil, limit: pageSize)
                fromStart = false
            }
            let pending = comments.filter { $0.status != .sent }
            comments = Self.merged(page, pending)
            commentsChange = .reload
            newestLoaded = page.last?.timestamp
            hasNewer = fromStart && page.count >= pageSize
            loaded = true
            state = .loaded
        } catch {
            guard error != .cancelled else { return }
            if retryOnLimit, error.isRateLimit {
                try? await Task.sleep(for: rateLimitRetry)
                guard !Task.isCancelled else { return }
                await fetchFirst(retryOnLimit: false)
                return
            }
            if comments.isEmpty {
                state = .failed(error.userMessage ?? "Не удалось загрузить комментарии")
            } else {
                self.error = error
            }
        }
    }

    /// Страница комментариев после последнего из загруженных по порядку.
    public func loadNewer() async {
        guard loaded, hasNewer, !isLoadingNewer, let after = newestLoaded else { return }
        isLoadingNewer = true
        defer { isLoadingNewer = false }
        do {
            let page = try await repository.comments(chatId: chatId, postId: postId, after: after, limit: pageSize)
            comments = Self.merged(page, comments)
            if let last = page.last?.timestamp { newestLoaded = last }
            hasNewer = page.count >= pageSize
        } catch {
            if error != .cancelled { self.error = error }
        }
    }

    public func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        error = nil
        let local = Message(
            id: "local-\(UUID().uuidString)",
            chatId: chatId,
            authorId: currentUserId,
            text: text,
            timestamp: .now,
            status: .sending,
            content: MessageContent(threadOf: postId)
        )
        comments.append(local)
        do {
            let sent = try await repository.send(text: text, chatId: chatId, postId: postId)
            comments.removeAll { $0.id == local.id || $0.id == sent.id }
            comments = Self.merged([sent], comments)
            if state != .loaded { state = .loaded }
        } catch {
            if let index = comments.firstIndex(where: { $0.id == local.id }) {
                comments[index].status = .failed
            }
            if draft.isEmpty { draft = text }
            if error != .cancelled { self.error = error }
        }
    }

    // MARK: Реакции

    /// Реакции ставятся на комментарии, уже принятые сервером.
    public func canReact(_ comment: Message) -> Bool {
        comment.status == .sent && Int64(comment.serverId ?? comment.id) != nil
    }

    public func quickReactions(for comment: Message) -> [String] {
        ReactionPalette.quick(catalog: reactionCatalog, mine: comment.content.reactions.mine)
    }

    /// Своя реакция на комментарий: сразу на экране, затем на сервере; отказ возвращает прежнее.
    /// Пушей о реакциях комментариев клиент не получает: итог берётся из ответа сервера.
    public func toggleReaction(commentId: String, emoji: String) async {
        guard let index = comments.firstIndex(where: { $0.id == commentId }), canReact(comments[index]) else { return }
        let before = comments[index].content.reactions
        let after = before.toggled(emoji)
        comments[index].content.reactions = after
        reactionRequest += 1
        let request = reactionRequest
        pendingReactions[commentId] = request
        do {
            let update = try await repository.setReaction(
                chatId: chatId,
                postId: postId,
                commentId: comments[index].serverId ?? commentId,
                emoji: after.mine
            )
            guard pendingReactions[commentId] == request else { return }
            pendingReactions[commentId] = nil
            if var update, let current = comments.firstIndex(where: { $0.id == commentId }) {
                if !update.mineKnown {
                    update.mine = after.mine
                    update.mineKnown = true
                }
                comments[current].content.reactions = update.applied(to: comments[current].content.reactions)
            }
            if case .rejected(ChatReactionsModel.failure)? = self.error { self.error = nil }
        } catch {
            guard pendingReactions[commentId] == request else { return }
            pendingReactions[commentId] = nil
            if let current = comments.firstIndex(where: { $0.id == commentId }), comments[current].content.reactions == after {
                comments[current].content.reactions = before
            }
            guard error != .cancelled else { return }
            if case .rejected = error {
                self.error = error
            } else {
                self.error = .rejected(ChatReactionsModel.failure)
            }
        }
    }

    /// Убрать неотправленный комментарий (его текст уже в поле ввода).
    public func discard(_ id: String) {
        comments.removeAll { $0.id == id && $0.status == .failed }
    }

    /// Повторить неотправленный комментарий.
    public func retry(_ id: String) async {
        guard let failed = comments.first(where: { $0.id == id && $0.status == .failed }) else { return }
        comments.removeAll { $0.id == id }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == failed.text { draft = "" }
        let kept = draft
        draft = failed.text
        await send()
        if draft.isEmpty { draft = kept }
    }

    /// Слияние страниц по id: серверная версия важнее, порядок — по времени.
    static func merged(_ incoming: [Message], _ existing: [Message]) -> [Message] {
        var byId: [String: Message] = [:]
        for message in existing { byId[message.id] = message }
        for message in incoming { byId[message.id] = message }
        return byId.values.sorted {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        }
    }
}
