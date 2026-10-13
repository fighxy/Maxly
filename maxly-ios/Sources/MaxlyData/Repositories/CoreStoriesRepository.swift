import Foundation
import MaxlyDomain

/// Истории через ядро: лента (208), истории владельца (210), просмотр (214), публикация (215),
/// удаление (218), архив своих (219) и пуши колец (216).
public struct CoreStoriesRepository: StoriesRepository {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func currentUserId() async -> String {
        await core.currentUserId()
    }

    public func updates() -> AsyncStream<StoryRing> {
        core.storyUpdates()
    }

    public func feed() async throws(MaxlyError) -> [StoryRing] {
        let rings = try await run("Лента историй") { try await core.loadStoriesFeed() }
        Log.info(.chats, "Лента историй: \(rings.count) колец")
        return rings.filter { !$0.isEmpty }
    }

    public func stories(owner: StoryOwner) async throws(MaxlyError) -> OwnerStories {
        let reply = try await run("Истории \(owner.id)") { try await core.loadOwnerStories(owner: owner) }
        return OwnerStories(ring: reply.ring.flatMap { $0.isEmpty ? nil : $0 }, stories: reply.stories.sorted { $0.time < $1.time })
    }

    public func markSeen(owner: StoryOwner, storyId: String) async throws(MaxlyError) {
        guard Int64(storyId) != nil else { return }
        try await run("Отметка истории \(storyId)") { try await core.markStorySeen(owner: owner, storyId: storyId) }
    }

    public func publish(_ story: OutgoingStory, audience: StoryAudience, progress: @escaping @Sendable (Double) -> Void) async throws(MaxlyError) -> StoryRing? {
        let durationMs = Int64(((story.duration ?? 0) * 1000).rounded())
        let reply = try await run("Публикация истории") {
            try await core.publishStory(path: story.fileURL.path, isVideo: story.isVideo, durationMs: durationMs,
                                        audience: audience.rawValue, progress: progress)
        }
        Log.info(.chats, "История опубликована")
        return reply.ring.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func delete(storyIds: [String]) async throws(MaxlyError) {
        let ids = storyIds.filter { Int64($0) != nil }
        guard !ids.isEmpty else { return }
        try await run("Удаление историй") { try await core.deleteStories(ids: ids) }
    }

    /// Курсор уходит, только если он не ноль: пустой и `0` — первая страница.
    public func archive(marker: String) async throws(MaxlyError) -> StoryArchivePage {
        let cursor = marker.trimmingCharacters(in: .whitespaces)
        let sent = cursor == "0" ? "" : cursor
        let page = try await run("Архив историй") { try await core.ownStoryArchive(marker: sent) }
        Log.info(.chats, "Архив историй: \(page.stories.count)\(page.isLast ? ", конец" : "")")
        return StoryArchivePage(stories: page.stories, marker: page.isLast ? "" : page.marker)
    }

    public func react(_ story: Story, emoji: String?) async throws(MaxlyError) -> Bool {
        try await run("Лайк истории \(story.id)") { try await core.reactToStory(owner: story.owner, storyId: story.id, emoji: emoji ?? "") }
    }

    public func reply(to story: Story, text: String) async throws(MaxlyError) {
        let expires = Int64((story.expiresAt?.timeIntervalSince1970 ?? 0) * 1000)
        try await run("Ответ на историю \(story.id)") {
            try await core.replyToStory(owner: story.owner, storyId: story.id, expiresAtMs: expires, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        Log.info(.chats, "Ответ на историю отправлен")
    }

    public func setHidden(_ owner: StoryOwner, hidden: Bool) async throws(MaxlyError) {
        try await run("Скрыть истории \(owner.id)") { try await core.setStoriesHidden(owner: owner, hidden: hidden) }
    }

    public func reportReasons() async throws(MaxlyError) -> [ComplaintReason] {
        try await run("Причины жалобы на историю") { try await core.complaintReasons(typeId: 9) }
    }

    public func report(_ story: Story, reasonId: Int) async throws(MaxlyError) -> Bool {
        try await run("Жалоба на историю \(story.id)") { try await core.reportStory(reasonId: reasonId, owner: story.owner, storyId: story.id) }
    }

    private func run<T: Sendable>(_ what: String, _ body: () async throws -> T) async throws(MaxlyError) -> T {
        do {
            return try await body()
        } catch {
            Log.warning(.chats, "\(what): \(error)")
            throw CoreMapping.apiError(error).maxlyError
        }
    }
}
