import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

private actor FakeStories: StoriesRepository {
    var me = "1"
    var feedList: [StoryRing] = []
    var owners: [StoryOwner: OwnerStories] = [:]
    var failure: OrbitleError?
    var publishReply: StoryRing?
    private(set) var marked: [String] = []
    private(set) var markedOwners: [StoryOwner] = []
    private(set) var deleted: [[String]] = []
    private(set) var published: [StoryAudience] = []
    private(set) var storyRequests = 0

    func set(feed: [StoryRing]) { feedList = feed }
    func set(owner: String, _ value: OwnerStories) { owners[StoryOwner(id: owner)] = value }
    func set(owner: StoryOwner, _ value: OwnerStories) { owners[owner] = value }
    func set(failure: OrbitleError?) { self.failure = failure }
    func set(publishReply: StoryRing?) { self.publishReply = publishReply }

    func currentUserId() async -> String { me }
    nonisolated func updates() -> AsyncStream<StoryRing> { AsyncStream { _ in } }

    func feed() async throws(OrbitleError) -> [StoryRing] { feedList }

    func stories(owner: StoryOwner) async throws(OrbitleError) -> OwnerStories {
        storyRequests += 1
        if let failure { throw failure }
        return owners[owner] ?? OwnerStories(ring: nil, stories: [])
    }

    func markSeen(owner: StoryOwner, storyId: String) async throws(OrbitleError) {
        marked.append(storyId)
        markedOwners.append(owner)
    }

    func publish(_ story: OutgoingStory, audience: StoryAudience, progress: @escaping @Sendable (Double) -> Void) async throws(OrbitleError) -> StoryRing? {
        if let failure { throw failure }
        progress(0.5)
        published.append(audience)
        return publishReply
    }

    func delete(storyIds: [String]) async throws(OrbitleError) {
        if let failure { throw failure }
        deleted.append(storyIds)
    }
}

private func ring(_ id: String, total: Int, read: Int, at seconds: TimeInterval, name: String? = nil) -> StoryRing {
    StoryRing(owner: StoryOwner(id: id), name: name ?? "u\(id)", updatedAt: Date(timeIntervalSince1970: seconds), total: total, read: read)
}

private func story(_ owner: String, _ id: String, at seconds: TimeInterval, media: Bool = true) -> Story {
    Story(
        id: id,
        owner: StoryOwner(id: owner),
        time: Date(timeIntervalSince1970: seconds),
        media: media ? StoryMedia(isVideo: false, url: URL(string: "https://i/\(id)")!) : nil
    )
}

@Suite("Истории")
@MainActor
struct StoriesViewModelTests {
    @Test("Одинаковые id человека, группы и канала не смешивают кольца, кэш и просмотр")
    func ownerNamespaces() async {
        let repo = FakeStories()
        let owners = [StoryOwner(id: "2"), StoryOwner(id: "2", kind: .chat), StoryOwner(id: "2", kind: .channel)]
        var feed: [StoryRing] = []
        for (index, owner) in owners.enumerated() {
            let entry = StoryRing(owner: owner, name: "Владелец \(index)", updatedAt: Date(timeIntervalSince1970: 1), total: 1, read: 0)
            var item = story("2", "same-story-id", at: 1)
            item.owner = owner
            await repo.set(owner: owner, OwnerStories(ring: entry, stories: [item]))
            feed.append(entry)
        }
        await repo.set(feed: feed)
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        #expect(model.rings.map(\.owner) == owners)
        model.open("2")
        await model.settle()
        #expect(model.viewer?.story?.owner == owners[0])
        model.nextOwner()
        await model.settle()
        #expect(model.viewer?.story?.owner == owners[1])
        model.nextOwner()
        await model.settle()
        #expect(model.viewer?.story?.owner == owners[2])
        #expect(await repo.markedOwners == owners)
        #expect(await repo.storyRequests == 3)
        for owner in owners { #expect(model.ring(of: owner.id, kind: owner.kind)?.read == 1) }
    }

    @Test("Канал с id текущего пользователя не становится своей историей")
    func channelIsNotOwn() async {
        let repo = FakeStories()
        let channel = StoryRing(owner: StoryOwner(id: "1", kind: .channel), name: "Канал", updatedAt: .now, total: 1, read: 0)
        await repo.set(feed: [channel])
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        #expect(model.own == nil)
        #expect(model.rings == [channel])
        #expect(model.ring(of: "1") == nil)
        #expect(model.ring(of: "1", kind: .channel) == channel)
    }

    @Test("Загрузка колец вне ленты учитывает тип владельца")
    func peerNamespaces() async {
        let repo = FakeStories()
        let user = ring("9", total: 1, read: 0, at: 1)
        var channel = user
        channel.owner.kind = .channel
        channel.name = "Канал"
        await repo.set(owner: user.owner, OwnerStories(ring: user, stories: []))
        await repo.set(owner: channel.owner, OwnerStories(ring: channel, stories: []))
        let model = StoriesViewModel(repository: repo)
        await model.loadRing("9")
        await model.loadRing("9", kind: .channel)
        #expect(model.ring(of: "9") == user)
        #expect(model.ring(of: "9", kind: .channel) == channel)
        #expect(await repo.storyRequests == 2)
    }

    @Test("Лента: сначала непросмотренные, затем свежие; своё кольцо отдельно")
    func feedOrder() async {
        let repo = FakeStories()
        await repo.set(feed: [ring("2", total: 2, read: 2, at: 300), ring("3", total: 1, read: 0, at: 100), ring("4", total: 3, read: 1, at: 200), ring("1", total: 1, read: 0, at: 50), ring("5", total: 0, read: 0, at: 900)])
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        #expect(model.rings.map(\.owner.id) == ["4", "3", "2"])
        #expect(model.own?.owner.id == "1")
        #expect(model.ring(of: "3") != nil)
        #expect(model.ring(of: "5") == nil)
        #expect(model.ring(of: "0") == nil)
    }

    @Test("Просмотр: с первой непросмотренной, отметка один раз, листание владельцев")
    func viewer() async {
        let repo = FakeStories()
        await repo.set(feed: [ring("4", total: 3, read: 1, at: 200), ring("3", total: 1, read: 0, at: 100)])
        await repo.set(owner: "4", OwnerStories(ring: ring("4", total: 3, read: 1, at: 200), stories: [story("4", "41", at: 1), story("4", "42", at: 2), story("4", "43", at: 3)]))
        await repo.set(owner: "3", OwnerStories(ring: ring("3", total: 1, read: 0, at: 100), stories: [story("3", "31", at: 5)]))
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        model.open("4")
        await model.settle()
        #expect(model.viewer?.story?.id == "42")
        #expect(await repo.marked == ["42"])
        #expect(model.ring(of: "4")?.read == 2)
        model.previous()
        #expect(model.viewer?.story?.id == "41")
        model.next()
        model.next()
        await model.settle()
        #expect(model.viewer?.story?.id == "43")
        #expect(await repo.marked == ["42", "43"])
        model.next()
        await model.settle()
        #expect(model.viewer?.ring.owner.id == "3")
        #expect(model.viewer?.story?.id == "31")
        model.next()
        #expect(model.viewer == nil)
        #expect(model.rings.map(\.owner.id) == ["4", "3"])
        #expect(model.rings.allSatisfy { !$0.hasUnread })
    }

    @Test("Загруженные истории не спрашиваются снова, пустой владелец пропускается")
    func cacheAndSkip() async {
        let repo = FakeStories()
        await repo.set(feed: [ring("4", total: 1, read: 0, at: 200), ring("3", total: 1, read: 0, at: 100)])
        await repo.set(owner: "4", OwnerStories(ring: ring("4", total: 1, read: 0, at: 200), stories: [story("4", "41", at: 1, media: false)]))
        await repo.set(owner: "3", OwnerStories(ring: ring("3", total: 1, read: 0, at: 100), stories: [story("3", "31", at: 1)]))
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        model.open("4")
        await model.settle()
        #expect(model.viewer?.story?.id == "31")
        model.close()
        model.open("3")
        await model.settle()
        #expect(await repo.storyRequests == 2)
    }

    @Test("Свои истории не отмечаются и удаляются")
    func ownDelete() async {
        let repo = FakeStories()
        await repo.set(feed: [ring("1", total: 2, read: 0, at: 100), ring("3", total: 1, read: 0, at: 100)])
        await repo.set(owner: "1", OwnerStories(ring: ring("1", total: 2, read: 0, at: 100), stories: [story("1", "11", at: 1), story("1", "12", at: 2)]))
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        model.open("1")
        await model.settle()
        #expect(model.viewer?.isOwn == true)
        #expect(model.viewer?.queue.count == 1)
        #expect(await repo.marked.isEmpty)
        await model.deleteCurrent()
        #expect(await repo.deleted == [["11"]])
        #expect(model.viewer?.story?.id == "12")
        #expect(model.own?.total == 1)
        await model.deleteCurrent()
        #expect(model.viewer == nil)
        #expect(model.own == nil)
    }

    @Test("Пуши обновляют и убирают кольца, имя остаётся прежним")
    func pushes() async {
        let repo = FakeStories()
        await repo.set(feed: [ring("3", total: 1, read: 0, at: 100, name: "Анна")])
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        model.apply(ring("3", total: 2, read: 1, at: 400, name: ""))
        #expect(model.ring(of: "3")?.name == "Анна")
        #expect(model.ring(of: "3")?.total == 2)
        model.apply(ring("7", total: 1, read: 0, at: 500))
        #expect(model.rings.map(\.owner.id) == ["7", "3"])
        model.apply(ring("3", total: 0, read: 0, at: 600))
        #expect(model.ring(of: "3") == nil)
    }

    @Test("Кольцо вне ленты для профиля спрашивается один раз")
    func peerRing() async {
        let repo = FakeStories()
        await repo.set(owner: "9", OwnerStories(ring: ring("9", total: 1, read: 0, at: 100), stories: [story("9", "91", at: 1)]))
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        await model.loadRing("9")
        await model.loadRing("9")
        await model.loadRing("0")
        #expect(await repo.storyRequests == 1)
        #expect(model.ring(of: "9") != nil)
        model.open("9")
        await model.settle()
        #expect(model.viewer?.queue.count == 1)
        #expect(model.viewer?.story?.id == "91")
        #expect(await repo.storyRequests == 1)
    }

    @Test("Собеседник личного чата — id диалога XOR свой id")
    func dialogPeer() async {
        let repo = FakeStories()
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        let chat = String(Int64(1) ^ Int64(42))
        #expect(model.peer(ofChat: chat, type: .private) == "42")
        #expect(model.peer(ofChat: "0", type: .private) == nil)
        #expect(model.peer(ofChat: chat, type: .group) == nil)
    }

    @Test("Публикация: прогресс и своё кольцо")
    func publish() async {
        let repo = FakeStories()
        let model = StoriesViewModel(repository: repo, now: { Date(timeIntervalSince1970: 777) })
        await model.refresh()
        await model.publish(OutgoingStory(fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), isVideo: false), audience: .contacts)
        #expect(await repo.published == [.contacts])
        #expect(model.publishProgress == nil)
        #expect(model.own?.total == 1)
        #expect(model.own?.updatedAt == Date(timeIntervalSince1970: 777))
        #expect(model.message == "История опубликована")
        await repo.set(publishReply: ring("1", total: 5, read: 0, at: 900))
        await model.publish(OutgoingStory(fileURL: URL(fileURLWithPath: "/tmp/b.mp4"), isVideo: true, duration: 3), audience: .everyone)
        #expect(model.own?.total == 5)
    }

    @Test("Ошибки становятся сообщениями")
    func failures() async {
        let repo = FakeStories()
        await repo.set(feed: [ring("3", total: 1, read: 0, at: 100)])
        let model = StoriesViewModel(repository: repo)
        await model.refresh()
        await repo.set(failure: .networkUnavailable)
        model.open("3")
        await model.settle()
        #expect(model.viewer == nil)
        #expect(model.message == "Нет соединения с сервером")
        model.message = nil
        await model.publish(OutgoingStory(fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), isVideo: false), audience: .everyone)
        #expect(model.publishProgress == nil)
        #expect(model.message == "Нет соединения с сервером")
    }

    @Test("Подписи: аватар, название, сегменты, давность")
    func texts() {
        let anna = StoryRing(owner: StoryOwner(id: "15"), name: "Анна Петрова", updatedAt: Date(), total: 3, read: 1)
        #expect(StoryText.avatar(anna) == ChatAvatar(kind: .initials("АП"), colorIndex: 1))
        #expect(StoryText.title(anna, own: true) == "Ваша история")
        #expect(StoryText.segments(anna).count == 3)
        #expect(StoryText.segments(anna).read == 1)
        var many = anna
        many.total = 50
        many.read = 45
        #expect(StoryText.segments(many).count == 30)
        #expect(StoryText.segments(many).read == 30)
        let now = Date(timeIntervalSince1970: 100_000)
        #expect(StoryText.ago(now.addingTimeInterval(-30), now: now) == "только что")
        #expect(StoryText.ago(now.addingTimeInterval(-300), now: now) == "5 мин назад")
        #expect(StoryText.ago(now.addingTimeInterval(-3 * 3600), now: now) == "3 ч назад")
        #expect(StoryText.ago(now.addingTimeInterval(-25 * 3600), now: now) == "вчера")
        #expect(StoriesViewModel.resumeIndex(ring("1", total: 3, read: 2, at: 0), count: 3) == 2)
        #expect(StoriesViewModel.resumeIndex(ring("1", total: 3, read: 3, at: 0), count: 3) == 0)
    }
}
