import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Общие медиа с сервера")
struct SharedMediaDataTests {
    private func photo(_ id: String, at seconds: TimeInterval) -> MessageRecord {
        MessageRecord(
            id: id, serverId: id, chatId: "c1", authorId: "2", text: "",
            timestamp: Date(timeIntervalSince1970: seconds), status: .sent,
            contentJSON: #"{"attaches":[{"_type":"PHOTO","photoId":"# + id + #","baseUrl":"https://i.example/p"}]}"#
        )
    }

    @Test("Страница приходит сообщениями с вложениями и не пишется в кэш ленты")
    func notCached() async throws {
        let stack = try SwiftDataStack(inMemory: true)
        let api = FakeMaxAPI()
        await api.setSharedMediaResult(.success([photo("10", at: 10), photo("5", at: 5)]))
        let repository = MessageRepositoryImpl.make(stack: stack, api: api)

        let page = try #require(await repository.sharedMedia(chatId: "c1", types: [.photo, .video], anchorId: "99", forward: 50, backward: 50))
        #expect(page.map(\.id) == ["10", "5"])
        #expect(page.first?.content.attachments.first?.photo != nil)

        let requests = await api.sharedMediaRequests
        #expect(requests.count == 1)
        #expect(requests.first?.0 == [.photo, .video])
        #expect(requests.first?.1 == "99")
        #expect(requests.first?.2 == 50)
        // В ленте нет дыр: разреженная страница не попала в кэш.
        let cached = try await repository.page(chatId: "c1", before: nil, limit: 50)
        #expect(cached.isEmpty)
    }

    @Test("Ошибка сервера — nil, без якоря запрос не уходит")
    func failure() async throws {
        let stack = try SwiftDataStack(inMemory: true)
        let api = FakeMaxAPI()
        await api.setSharedMediaResult(.failure(.offline))
        let repository = MessageRepositoryImpl.make(stack: stack, api: api)
        let failed = await repository.sharedMedia(chatId: "c1", types: [.audio], anchorId: "99", forward: 0, backward: 50)
        #expect(failed == nil)
        let noAnchor = await repository.sharedMedia(chatId: "c1", types: [.audio], anchorId: "", forward: 0, backward: 50)
        #expect(noAnchor == nil)
        #expect(await api.sharedMediaRequests.count == 1)
    }
}
