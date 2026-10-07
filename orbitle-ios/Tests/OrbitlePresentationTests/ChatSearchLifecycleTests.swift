import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

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
        let old = Task { await model.searchInChat("старое") }
        #expect(await eventually { await oldGate.arrivals == 1 })
        let next = Task { await model.searchInChat("новое") }
        #expect(await eventually { await newGate.arrivals == 1 })
        await oldGate.open()
        await old.value
        #expect(model.searchHits.isEmpty && model.searchBusy)
        await newGate.open()
        await next.value
        #expect(model.searchHits.map(\.messageId) == ["2"])
        #expect(!model.searchBusy)
    }

    @Test("Очистка и закрытие не принимают запоздалый результат")
    func dismiss() async {
        let repository = FakeMessageRepository()
        let gate = Gate()
        await repository.setSearch("слово", hits: [FoundMessage(chatId: "c", messageId: "1", text: "слово")], gate: gate)
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        let task = Task { await model.searchInChat("слово") }
        #expect(await eventually { await gate.arrivals == 1 })
        model.resetSearch()
        await gate.open()
        await task.value
        #expect(model.searchHits.isEmpty && !model.searchBusy && model.searchError == nil)
        await model.searchInChat("  \n ")
        #expect(await repository.chatSearches == ["слово"])
    }

    @Test("Ошибка остаётся в поиске, повтор очищает её, отмена задержки не идёт в сеть")
    func failureRetryAndCancellation() async {
        let repository = FakeMessageRepository()
        await repository.setSearch("слово", error: .networkUnavailable)
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await model.searchInChat("слово")
        #expect(model.searchError != nil && model.error == nil && !model.searchBusy)
        await repository.setSearch("слово", hits: [FoundMessage(chatId: "c", messageId: "1", text: "слово")])
        await model.searchInChat("слово")
        #expect(model.searchError == nil && model.searchHits.count == 1)
        let task = Task { await model.searchInChat("отмена", debounce: .seconds(60)) }
        #expect(await eventually { model.searchBusy })
        task.cancel()
        await task.value
        #expect(!model.searchBusy && model.searchError == nil)
        #expect(await repository.chatSearches == ["слово", "слово"])
    }
}
