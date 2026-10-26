import Foundation
import Observation
import MaxlyDomain

/// Комментарии к постам канала: окно открытого поста и счётчики под постами ленты.
@MainActor
@Observable
public final class ChatCommentsModel {
    public let chatId: String
    /// Пост, чьи комментарии открыты в модальном окне.
    public var opened: Message?
    /// Число комментариев под постами канала (id поста на сервере → число).
    public private(set) var counts: [String: Int] = [:]
    /// Комментарии в этом чате есть: без хранилища окно не открывается.
    public var isAvailable: Bool { repository != nil }
    @ObservationIgnored private let currentUserId: String
    @ObservationIgnored private let repository: (any CommentsRepository)?
    @ObservationIgnored private let messages: any MessageRepository
    @ObservationIgnored private var model: CommentsViewModel?
    /// Посты, чьи счётчики уже спрошены: один запрос на пост за время жизни экрана.
    @ObservationIgnored private var asked: Set<String> = []
    /// После ошибки счётчики не спрашиваются до этого времени.
    @ObservationIgnored private var retryAt = Date.distantPast
    /// Каталог реакций чата: окно комментариев показывает тот же.
    @ObservationIgnored public var reactionCatalog: () -> [String] = { [] }
    /// Пауза перед повтором счётчиков после ошибки сервера.
    static let retryAfterError: TimeInterval = 30

    public init(chatId: String, currentUserId: String, repository: (any CommentsRepository)?, messages: any MessageRepository) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.repository = repository
        self.messages = messages
    }

    public func open(_ message: Message) {
        guard repository != nil else { return }
        opened = message
    }

    /// Модель окна комментариев открытого поста. Одна на пост, пока окно не закрыто.
    public func model(for post: Message) -> CommentsViewModel? {
        guard let repository else { return nil }
        if let model, model.post.id == post.id { return model }
        let created = CommentsViewModel(
            chatId: chatId,
            post: post,
            currentUserId: currentUserId,
            comments: repository,
            reactionCatalog: reactionCatalog()
        )
        model = created
        return created
    }

    public func close() {
        let post = opened ?? model?.post
        opened = nil
        model = nil
        // После обсуждения счётчик мог измениться: спросить заново.
        if let post {
            asked.remove(post.serverId ?? post.id)
            requestCounts(for: [post])
        }
    }

    /// Число комментариев поста: ответ сервера, иначе счётчик из самого сообщения.
    public func count(for message: Message) -> Int? {
        counts[message.serverId ?? message.id] ?? message.content.comments?.count
    }

    /// Спросить счётчики у постов, которых ещё не спрашивали (пачками по 50).
    public func requestCounts(for posts: [Message]) {
        guard let repository, Date() >= retryAt else { return }
        let ids = posts.compactMap { post -> String? in
            let id = post.serverId ?? post.id
            guard Int64(id) != nil, !asked.contains(id) else { return nil }
            return id
        }
        guard !ids.isEmpty else { return }
        asked.formUnion(ids)
        let chatId = chatId
        let messages = messages
        Task { [weak self] in
            for start in stride(from: 0, to: ids.count, by: 50) {
                let chunk = Array(ids[start..<min(start + 50, ids.count)])
                do {
                    let counts = try await repository.counts(chatId: chatId, postIds: chunk)
                    guard let self else { return }
                    self.counts.merge(counts) { _, new in new }
                    await messages.noteCommentCounts(chatId: chatId, counts: counts)
                } catch {
                    // Остальные пачки не уходят: сервер, скорее всего, ответит им too.many.requests.
                    guard let self else { return }
                    self.asked.subtract(ids[start...])
                    self.retryAt = Date().addingTimeInterval(Self.retryAfterError)
                    return
                }
            }
        }
    }
}
