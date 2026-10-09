import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private actor FakeArchive: StoriesRepository {
    /// Ответы по курсору запроса.
    var pages: [String: StoryArchivePage] = [:]
    var failure: MaxlyError?
    private(set) var markers: [String] = []

    func set(_ marker: String, _ page: StoryArchivePage) { pages[marker] = page }
    func set(failure: MaxlyError?) { self.failure = failure }

    func currentUserId() async -> String { "1" }
    nonisolated func updates() -> AsyncStream<StoryRing> { AsyncStream { _ in } }
    func feed() async throws(MaxlyError) -> [StoryRing] { [] }
    func stories(owner: StoryOwner) async throws(MaxlyError) -> OwnerStories { OwnerStories(ring: nil, stories: []) }
    func markSeen(owner: StoryOwner, storyId: String) async throws(MaxlyError) {}
    func publish(_ story: OutgoingStory, audience: StoryAudience, progress: @escaping @Sendable (Double) -> Void) async throws(MaxlyError) -> StoryRing? { nil }
    func delete(storyIds: [String]) async throws(MaxlyError) {}

    func archive(marker: String) async throws(MaxlyError) -> StoryArchivePage {
        markers.append(marker)
        if let failure { throw failure }
        return pages[marker] ?? StoryArchivePage(stories: [], marker: "")
    }
}

private func story(_ id: String) -> Story {
    Story(id: id, owner: StoryOwner(id: "1"), time: Date(timeIntervalSince1970: 1_000), media: nil)
}

@Suite("Мои истории")
@MainActor
struct StoryArchiveModelTests {
    @Test("Первая страница без курсора, дальше курсор ответа; пустой курсор — конец")
    func paging() async {
        let archive = FakeArchive()
        await archive.set("", StoryArchivePage(stories: [story("3"), story("2")], marker: "777"))
        await archive.set("777", StoryArchivePage(stories: [story("2"), story("1")], marker: ""))
        let model = StoryArchiveModel(repository: archive)
        await model.activate()
        #expect(model.state == .ready)
        #expect(model.stories.map(\.id) == ["3", "2"])
        #expect(model.canLoadMore)
        await model.loadMore()
        // Повтор с прошлой страницы не дублируется.
        #expect(model.stories.map(\.id) == ["3", "2", "1"])
        #expect(!model.canLoadMore)
        await model.loadMore()
        // Повторное открытие экрана не грузит заново.
        await model.activate()
        #expect(await archive.markers == ["", "777"])
    }

    @Test("Пустой архив — «Место для воспоминаний»; курсор «0» — тоже конец")
    func empty() async {
        let archive = FakeArchive()
        await archive.set("", StoryArchivePage(stories: [], marker: "0"))
        let model = StoryArchiveModel(repository: archive)
        await model.activate()
        #expect(model.state == .empty)
        #expect(!model.canLoadMore)
        #expect(StoryArchiveModel.emptyTitle == "Место для воспоминаний")
    }

    @Test("Ошибка первой страницы — экран ошибки, следующей — список остаётся")
    func failures() async {
        let archive = FakeArchive()
        await archive.set(failure: .networkUnavailable)
        let model = StoryArchiveModel(repository: archive)
        await model.activate()
        #expect(model.state == .failed(MaxlyError.networkUnavailable.userMessage ?? ""))

        await archive.set(failure: nil)
        await archive.set("", StoryArchivePage(stories: [story("2")], marker: "5"))
        await model.reload()
        #expect(model.state == .ready)
        await archive.set(failure: .networkUnavailable)
        await model.loadMore()
        #expect(model.stories.map(\.id) == ["2"])
        #expect(model.pageError != nil)
        #expect(model.canLoadMore)
    }
}
