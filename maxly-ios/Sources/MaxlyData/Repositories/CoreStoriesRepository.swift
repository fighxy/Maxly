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

    private func run<T: Sendable>(_ what: String, _ body: () async throws -> T) async throws(MaxlyError) -> T {
        do {
            return try await body()
        } catch {
            Log.warning(.chats, "\(what): \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }
}
