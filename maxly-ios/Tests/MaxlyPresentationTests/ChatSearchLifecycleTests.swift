import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Поиск в чате: жизненный цикл запросов")
@MainActor
struct ChatSearchLifecycleTests {
    @Test("Старый ответ не заменяет новый и не гасит его индикатор")
    func staleResponse() async {
        let repository = FakeMessageRepository()
        let oldGate = Gate()
        let newGate = Gate()
        await repository.setSearch("старое", hits: [FoundMessage(chatId: "c", messageId: "1", text: "старое")], gate: oldGate)
        await repository.setSearch("новое", hits: [FoundMessage(chatId: "c", messageId: "2", text: "новое")], gate: newGate)
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        let old = Task { await model.search.search("старое") }
        #expect(await eventually { await oldGate.arrivals == 1 })
        let next = Task { await model.search.search("новое") }
        #expect(await eventually { await newGate.arrivals == 1 })
        await oldGate.open()
        await old.value
        #expect(model.search.hits.isEmpty && model.search.busy)
        await newGate.open()
        await next.value
        #expect(model.search.hits.map(\.messageId) == ["2"])
        #expect(!model.search.busy)
    }

    @Test("Очистка и закрытие не принимают запоздалый результат")
    func dismiss() async {
        let repository = FakeMessageRepository()
        let gate = Gate()
        await repository.setSearch("слово", hits: [FoundMessage(chatId: "c", messageId: "1", text: "слово")], gate: gate)
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        let task = Task { await model.search.search("слово") }
        #expect(await eventually { await gate.arrivals == 1 })
        model.search.reset()
        await gate.open()
        await task.value
        #expect(model.search.hits.isEmpty && !model.search.busy && model.search.error == nil)
        await model.search.search("  \n ")
        #expect(await repository.chatSearches == ["слово"])
    }

    @Test("Ошибка остаётся в поиске, повтор очищает её, отмена задержки не идёт в сеть")
    func failureRetryAndCancellation() async {
        let repository = FakeMessageRepository()
        await repository.setSearch("слово", error: .networkUnavailable)
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await model.search.search("слово")
        #expect(model.search.error != nil && model.error == nil && !model.search.busy)
        await repository.setSearch("слово", hits: [FoundMessage(chatId: "c", messageId: "1", text: "слово")])
        await model.search.search("слово")
        #expect(model.search.error == nil && model.search.hits.count == 1)
        let task = Task { await model.search.search("отмена", debounce: .seconds(60)) }
        #expect(await eventually { model.search.busy })
        task.cancel()
        await task.value
        #expect(!model.search.busy && model.search.error == nil)
        #expect(await repository.chatSearches == ["слово", "слово"])
    }
}
