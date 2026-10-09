import Foundation

/// Истории (сторис): лента колец, истории владельца, просмотр, публикация и удаление своих.
public protocol StoriesRepository: Sendable {
    /// Свой id: своё кольцо в ленте — «Ваша история». Пустая строка — ещё не известен.
    func currentUserId() async -> String
    /// Пуши об изменении колец. Пустое кольцо — у владельца историй не осталось.
    func updates() -> AsyncStream<StoryRing>
    /// Первая страница ленты: по кольцу на владельца, пустые не входят.
    func feed() async throws(OrbitleError) -> [StoryRing]
    /// Истории владельца: их ждёт пользователь, открывший кольцо.
    func stories(owner: StoryOwner) async throws(OrbitleError) -> OwnerStories
    func markSeen(owner: StoryOwner, storyId: String) async throws(OrbitleError)
    /// Публикует историю на сутки; ответ — своё новое кольцо, если сервер его прислал.
    /// `progress` получает долю 0…1 загрузки не с главного потока.
    func publish(_ story: OutgoingStory, audience: StoryAudience, progress: @escaping @Sendable (Double) -> Void) async throws(OrbitleError) -> StoryRing?
    /// Удаляет свои истории.
    func delete(storyIds: [String]) async throws(OrbitleError)
    /// Страница архива своих историй, 30 штук. Пустой `marker` — первая страница, дальше —
    /// `marker` прошлого ответа.
    func archive(marker: String) async throws(OrbitleError) -> StoryArchivePage
}

public extension StoriesRepository {
    /// Источник без архива: «Мои истории» показывают ошибку.
    func archive(marker: String) async throws(OrbitleError) -> StoryArchivePage { throw .invalidRequest }
}
