import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

private func photo(_ id: String, _ seconds: TimeInterval, serverId: String? = nil, status: MessageStatus = .sent) -> Message {
    Message(
        id: id, serverId: serverId, chatId: "7", authorId: "2", text: "",
        timestamp: Date(timeIntervalSince1970: seconds), status: status,
        content: MessageContent(attachments: [.photo(PhotoContent(id: "p" + id, url: URL(string: "https://x/\(id).jpg")))])
    )
}

@Suite("Общие медиа: обход сервера")
struct SharedMediaPagerTests {
    @Test("Якорь — последнее сообщение окна, уже известное серверу")
    func anchor() {
        let window = [photo("10", 10), photo("local-a", 20, serverId: "21"), photo("local-b", 30, status: .sending)]
        #expect(SharedMediaPager.anchor(in: window) == "21")
        #expect(SharedMediaPager.anchor(in: [photo("local-b", 30, status: .sending)]) == nil)
        #expect(SharedMediaPager.anchor(in: []) == nil)
    }

    @Test("Вкладки спрашиваются по типам вложений сервера")
    func types() {
        #expect(SharedMediaTab.media.attachTypes == [.photo, .video])
        #expect(SharedMediaTab.files.attachTypes == [.file])
        #expect(SharedMediaTab.voice.attachTypes == [.audio])
        #expect(SharedMediaTab.links.attachTypes == [.share])
    }

    @Test("Первая страница вокруг последнего сообщения, дальше — от самого старого полученного")
    func paging() {
        var pager = SharedMediaPager(pageSize: 2)
        let first = pager.round(latest: "100")
        #expect(first.map(\.tab) == SharedMediaTab.allCases)
        #expect(first.allSatisfy { $0.anchorId == "100" && $0.forward == 2 && $0.backward == 2 })

        let media = first[0]
        let got = pager.receive([photo("90", 90), photo("80", 80)], for: media)
        #expect(got)
        for request in first.dropFirst() {
            let empty = pager.receive([], for: request)
            #expect(!empty)
        }
        let second = pager.round(latest: "100")
        #expect(second == [SharedMediaRequest(tab: .media, anchorId: "80", forward: 0, backward: 2)])

        // Перекрытие на якоре не считается новым, страница со старым — считается.
        let more = pager.receive([photo("80", 80), photo("70", 70)], for: second[0])
        #expect(more)
        let third = pager.round(latest: "100")
        #expect(third.first?.anchorId == "70")
        let end = pager.receive([photo("70", 70)], for: third[0])
        #expect(!end)
        #expect(pager.round(latest: "100").isEmpty)
        #expect(pager.isFinished)
        #expect(Set(pager.messages.keys) == ["90", "80", "70"])
    }

    @Test("Сообщение из другой вкладки не обрывает обход своей")
    func perTabSeen() {
        var pager = SharedMediaPager(pageSize: 1)
        let round = pager.round(latest: "100")
        pager.receive([photo("50", 50)], for: round[0])
        let files = round[1]
        #expect(files.tab == .files)
        let got = pager.receive([photo("50", 50)], for: files)
        #expect(got)
        #expect(pager.round(latest: "100").contains { $0.tab == .files && $0.anchorId == "50" })
    }

    @Test("Лимит страниц останавливает вкладку")
    func pageLimit() {
        var pager = SharedMediaPager(pageSize: 1, maxPages: 2)
        var request = pager.round(latest: "100")[0]
        pager.receive([photo("9", 9)], for: request)
        request = pager.round(latest: "100")[0]
        #expect(request.tab == .media)
        pager.receive([photo("8", 8)], for: request)
        #expect(!pager.round(latest: "100").contains { $0.tab == .media })
    }

    @Test("Ошибка останавливает вкладку до повтора, повтор идёт с того же места")
    func retry() {
        var pager = SharedMediaPager(pageSize: 1)
        let round = pager.round(latest: "100")
        pager.receive([photo("9", 9)], for: round[0])
        let next = pager.round(latest: "100")[0]
        pager.receive(nil, for: next)
        #expect(!pager.round(latest: "100").contains { $0.tab == .media })
        pager.retryFailed()
        #expect(pager.round(latest: "100").first { $0.tab == .media }?.anchorId == "9")
    }
}

@Suite("Общие медиа: профиль")
@MainActor
struct SharedMediaRemoteTests {
    private func model() -> ChatProfileViewModel {
        ChatProfileViewModel(chatId: "7", title: "Женя", repository: OfflineProfiles())
    }

    @Test("Фото старше загруженной истории приходят с сервера, без повторов")
    func fromServer() async {
        let model = model()
        // В чате загружено одно фото — как на экране с одной картинкой во вкладке «Медиа».
        let window = [photo("100", 100)]
        await model.updateShared(window, currentUserId: "me")
        #expect(model.shared.media.count == 1)

        var asked: [SharedMediaRequest] = []
        let pages: [String: [Message]] = [
            "100": [photo("100", 100), photo("60", 60), photo("50", 50)],
            "50": [photo("50", 50), photo("10", 10)],
            "10": [photo("10", 10)],
        ]
        await model.loadRemoteShared(window: window) { request in
            asked.append(request)
            return request.tab == .media ? pages[request.anchorId] : []
        }
        #expect(model.shared.media.map(\.attachmentId) == ["p100", "p60", "p50", "p10"])
        #expect(asked.filter { $0.tab == .media }.map(\.anchorId) == ["100", "50", "10"])
        #expect(!model.isLoadingRemoteShared)

        // Обход закончен: повторное открытие не спрашивает сервер заново.
        asked = []
        await model.loadRemoteShared(window: window) { request in
            asked.append(request)
            return []
        }
        #expect(asked.isEmpty)
    }

    @Test("Своё отправленное фото не дублируется серверной копией")
    func ownNotDuplicated() async {
        let model = model()
        let window = [photo("local-1", 100, serverId: "100")]
        await model.updateShared(window, currentUserId: "me")
        await model.loadRemoteShared(window: window) { request in
            request.tab == .media ? [photo("100", 100), photo("40", 40)] : []
        }
        #expect(model.shared.media.map(\.attachmentId) == ["plocal-1", "p40"])
    }

    @Test("Отказ сервера останавливает весь обход, следующее открытие продолжает")
    func failureStopsWalk() async {
        let model = model()
        let window = [photo("100", 100)]
        await model.updateShared(window, currentUserId: "me")
        var asked = 0
        await model.loadRemoteShared(window: window, pause: .zero) { _ in
            asked += 1
            return nil
        }
        #expect(asked == 1)
        #expect(!model.isLoadingRemoteShared)

        asked = 0
        await model.loadRemoteShared(window: window, pause: .zero) { _ in
            asked += 1
            return []
        }
        #expect(asked == SharedMediaTab.allCases.count)
    }

    @Test("Без серверного сообщения в окне обход не начинается")
    func noAnchor() async {
        let model = model()
        var calls = 0
        await model.loadRemoteShared(window: [photo("local-1", 1, status: .sending)]) { _ in
            calls += 1
            return []
        }
        #expect(calls == 0)
    }
}

private struct OfflineProfiles: ChatProfileRepository {
    func profile(chatId: String) async throws(OrbitleError) -> ChatProfile { throw .networkUnavailable }
}
