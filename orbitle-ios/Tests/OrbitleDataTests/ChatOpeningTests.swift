import Foundation
import Testing
import OrbitleDomain
import OrbitlePresentation
@testable import OrbitleData

@MainActor
private func openingEventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(3)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@Suite("Открытие чата: кэш и серверная сверка")
@MainActor
struct ChatOpeningTests {
    @Test("Ошибка истории доступна для повтора, кэш остаётся на экране")
    func historyFailureKeepsCache() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([message("1")])
        await api.setHistoryError(.invalidResponse)
        let model = ChatViewModel(chatId: "c1", currentUserId: "me", messages: repository)
        model.activate()
        await model.loadLatest()
        #expect(await openingEventually { !model.isRestoringHistory && model.messages.count == 1 })
        #expect(model.historyError != nil)
        #expect(!model.latestLoaded)

        await api.setHistoryError(nil)
        await api.setHistory([message("1"), message("2")])
        await model.loadLatest()
        #expect(await openingEventually { !model.isRestoringHistory && model.messages.count == 2 })
        #expect(model.historyError == nil)
        #expect(model.latestLoaded)
        model.deactivate()
    }

    @Test("too.many.requests при ленте из кэша не показывается ошибкой")
    func rateLimitKeepsCacheQuiet() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([message("1")])
        await api.setHistoryError(.server(code: OrbitleError.rateLimitCode, text: nil))
        let model = ChatViewModel(chatId: "c1", currentUserId: "me", messages: repository)
        model.activate()
        await model.loadLatest()
        #expect(await openingEventually { !model.isRestoringHistory && model.messages.count == 1 })
        #expect(model.error == nil)
        model.deactivate()
    }

    @Test("Ответ прошлого открытия не завершает новую загрузку")
    func previousOpeningCannotFinishNewSession() async throws {
        let api = FakeMaxAPI()
        let firstGate = Gate()
        await api.setFetchGate(firstGate)
        let (repository, _) = try await makeMessageStack(api: api)
        let model = ChatViewModel(chatId: "c1", currentUserId: "me", messages: repository)
        model.activate()
        let firstLoad = Task { await model.loadLatest() }
        #expect(await eventually { await firstGate.arrivals == 1 })
        model.deactivate()

        let secondGate = Gate()
        await api.setFetchGate(secondGate)
        model.activate()
        let secondLoad = Task { await model.loadLatest() }
        #expect(await eventually { await secondGate.arrivals == 1 })
        await firstGate.open()
        await firstLoad.value
        #expect(model.isRestoringHistory)
        #expect(model.isLoadingLatest)
        #expect(!model.latestLoaded)

        await secondGate.open()
        await secondLoad.value
        #expect(await openingEventually { !model.isRestoringHistory && model.latestLoaded })
        model.deactivate()
    }

    @Test("Отменённая загрузка не объявляет пустой чат загруженным")
    func cancellationDoesNotPublishEmptySuccess() async throws {
        let api = FakeMaxAPI()
        let gate = Gate()
        await api.setFetchGate(gate)
        let (repository, _) = try await makeMessageStack(api: api)
        let model = ChatViewModel(chatId: "c1", currentUserId: "me", messages: repository)
        model.activate()
        let loading = Task { await model.loadLatest() }
        #expect(await eventually { await gate.arrivals == 1 })
        loading.cancel()
        await gate.open()
        await loading.value
        #expect(!model.latestLoaded)
        #expect(!model.isLoadingLatest)
        #expect(!model.isRestoringHistory)
        #expect(model.error == nil)
        model.deactivate()
    }

    @Test("Повторная загрузка во время запроса не создаёт второй запрос")
    func coalescesOpeningRequests() async throws {
        let api = FakeMaxAPI()
        let gate = Gate()
        await api.setFetchGate(gate)
        let (repository, _) = try await makeMessageStack(api: api)
        let model = ChatViewModel(chatId: "c1", currentUserId: "me", messages: repository)
        model.activate()
        let loading = Task { await model.loadLatest() }
        #expect(await eventually { await gate.arrivals == 1 })
        await model.loadLatest()
        #expect(await gate.arrivals == 1)
        await gate.open()
        await loading.value
        #expect(await openingEventually { !model.isRestoringHistory })
        model.deactivate()
    }

    private func message(_ id: String) -> MessageRecord {
        MessageRecord(id: id, serverId: id, chatId: "c1", authorId: "bob", text: id,
                      timestamp: Date(timeIntervalSince1970: Double(id)!), status: .sent)
    }

    @Test("Сверка и повторное открытие не анимируются, следующее live-сообщение анимируется")
    func restorationAndLive() async throws {
        let api = FakeMaxAPI()
        let gate = Gate()
        await api.setFetchGate(gate)
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([message("1")])
        await api.setHistory([message("1"), message("2")])
        let model = ChatViewModel(chatId: "c1", currentUserId: "me", messages: repository)
        model.activate()
        let loading = Task { await model.loadLatest() }
        #expect(await eventually { await gate.arrivals == 1 })
        #expect(await openingEventually { model.messages.count == 1 })
        #expect(model.isRestoringHistory)
        #expect(!model.messagesChange.animatesTranscript)
        await gate.open()
        await loading.value
        #expect(await openingEventually { !model.isRestoringHistory && model.messages.count == 2 })
        #expect(model.messagesChange == .reload)
        try await repository.upsert([message("3")])
        #expect(await openingEventually { model.messages.count == 3 })
        #expect(model.messagesChange == .appended(1))
        model.deactivate()
        await api.setHistory([message("1"), message("2"), message("3"), message("4")])
        model.activate()
        await model.loadLatest()
        #expect(await openingEventually { !model.isRestoringHistory && model.messages.count == 4 })
        #expect(model.messagesChange == .reload)
        model.deactivate()
    }
}
