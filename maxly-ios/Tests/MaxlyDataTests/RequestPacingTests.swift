import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Частота запросов истории")
struct RequestPacingTests {
    @Test("Свежая страница не перезапрашивается: возврат в чат и опрос идут из базы")
    func freshPageReused() async throws {
        let api = FakeMaxAPI()
        await api.setHistory(makeHistory(chatId: "c1", count: 3))
        let (repository, _) = try await makeMessageStack(api: api, latestReuse: 10)

        try await repository.fetchLatest(chatId: "c1")
        try await repository.fetchLatest(chatId: "c1")
        await repository.refreshReactions(chatId: "c1")
        #expect(await api.historyFetches == 1)
        #expect(try await repository.page(chatId: "c1", before: nil).count == 3)

        // Другой чат своё окно не делит.
        try await repository.fetchLatest(chatId: "c2")
        #expect(await api.historyFetches == 2)
    }

    @Test("Ошибка не запоминается: следующий вызов снова спрашивает сервер")
    func failureNotReused() async throws {
        let api = FakeMaxAPI()
        await api.setHistoryError(.server(code: MaxlyError.rateLimitCode, text: nil))
        let (repository, _) = try await makeMessageStack(api: api, latestReuse: 10)

        await #expect(throws: MaxlyError.server(code: MaxlyError.rateLimitCode, text: nil)) {
            try await repository.fetchLatest(chatId: "c1")
        }
        await api.setHistoryError(nil)
        try await repository.fetchLatest(chatId: "c1")
        #expect(await api.historyFetches == 2)
    }

    @Test("Очистка переписки сбрасывает окно: свежая история грузится сразу")
    func dropResetsWindow() async throws {
        let api = FakeMaxAPI()
        await api.setHistory(makeHistory(chatId: "c1", count: 2))
        let (repository, _) = try await makeMessageStack(api: api, latestReuse: 10)

        try await repository.fetchLatest(chatId: "c1")
        await repository.dropLocalHistory(chatId: "c1")
        try await repository.fetchLatest(chatId: "c1")
        #expect(await api.historyFetches == 2)
    }
}

@Suite("Пауза после too.many.requests")
struct ServerRateLimitTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000)
    }

    @Test("Пауза растёт с отказами подряд и сбрасывается удачным чтением")
    func pauses() async {
        let clock = Clock()
        let limit = ServerRateLimit(clock: { clock.now })
        #expect(await limit.remaining() == nil)

        await limit.noteLimited()
        #expect(await limit.remaining() == 10)
        clock.now += 10
        #expect(await limit.remaining() == nil)

        await limit.noteLimited()
        #expect(await limit.remaining() == 20)
        clock.now += 20
        await limit.noteLimited()
        #expect(await limit.remaining() == 40)
        clock.now += 40
        await limit.noteLimited()
        await limit.noteLimited()
        clock.now += 1
        // Потолок — минута от последнего отказа.
        #expect(await limit.remaining() == 59)

        clock.now += 59
        await limit.noteSuccess()
        await limit.noteLimited()
        #expect(await limit.remaining() == 10)
    }

    @Test("Ключ ошибки сервера совпадает с доменным")
    func key() {
        #expect(ServerRateLimit.isLimit("too.many.requests"))
        #expect(!ServerRateLimit.isLimit("not.found"))
        #expect(MaxlyError.server(code: "too.many.requests", text: nil).isRateLimit)
        #expect(MaxlyError.server(code: "too.many.requests", text: nil).userMessage == "Сервер просит подождать: слишком много запросов")
    }
}
