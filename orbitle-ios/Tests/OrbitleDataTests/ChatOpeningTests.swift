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
