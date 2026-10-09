import Foundation
import Testing
@testable import MaxlyDomain

private func chat(_ id: String, at seconds: TimeInterval, type: ChatType = .group, pin: Int? = nil) -> Chat {
    Chat(id: id, title: id, type: type, updatedAt: Date(timeIntervalSince1970: seconds), pinOrder: pin)
}

@Suite("Порядок и папки списка чатов")
struct ChatListDomainTests {
    @Test("Закреплённые по месту, остальные по свежести, свежий черновик поднимает чат")
    func order() {
        var drafted = chat("d", at: 10)
        drafted.draft = ChatDraft(text: "…", updatedAt: Date(timeIntervalSince1970: 500))
        let sorted = [chat("a", at: 100), chat("p2", at: 1, pin: 5), drafted, chat("p1", at: 1, pin: -1), chat("b", at: 100)]
            .sorted(by: Chat.listOrder)
        #expect(sorted.map(\.id) == ["p1", "p2", "d", "a", "b"])
        #expect(drafted.activityDate == Date(timeIntervalSince1970: 500))
        var stale = drafted
        stale.draft = ChatDraft(text: "…", updatedAt: Date(timeIntervalSince1970: 1))
        #expect(stale.activityDate == Date(timeIntervalSince1970: 10))
    }

    @Test("Фильтры папок по типу, непрочитанным и списку id; архив ни в одну не входит")
    func filters() {
        var bot = chat("bot", at: 1, type: .private)
        bot.isBot = true
        var unread = chat("u", at: 1)
        unread.isMarkedUnread = true
        var archived = chat("arch", at: 1, type: .private)
        archived.isArchived = true
        let saved = chat(Chat.savedMessagesId, at: 1, type: .private)
        let all = [chat("p", at: 1, type: .private), chat("g", at: 1), chat("c", at: 1, type: .channel), bot, unread, archived, saved]
        func ids(_ folder: ChatFolder) -> [String] { all.filter(folder.contains).map(\.id) }
        #expect(ids(.all) == ["p", "g", "c", "bot", "u", "0"])
        #expect(ids(ChatFolder.localFilters[0]) == ["p"])
        #expect(ids(ChatFolder.localFilters[1]) == ["g", "u"])
        #expect(ids(ChatFolder.localFilters[2]) == ["c"])
        #expect(ids(ChatFolder.localFilters[3]) == ["bot"])
        #expect(ids(ChatFolder.localFilters[4]) == ["u"])
        #expect(ids(ChatFolder(id: "s", title: "S", filter: .chats(["g", "arch"]))) == ["g"])
        #expect(saved.isSavedMessages)
        #expect(unread.isUnread)
    }

    @Test("Без поддержки источника необязательные действия недоступны")
    func defaults() async {
        struct Plain: ChatRepository {
            func chats() -> AsyncStream<[Chat]> { AsyncStream { $0.finish() } }
            func refresh() async throws(MaxlyError) {}
            func refresh(chatId: String) async throws(MaxlyError) {}
            func markAsRead(chatId: String) async throws(MaxlyError) {}
        }
        let plain = Plain()
        #expect(plain.capabilities.isEmpty)
        await #expect(throws: MaxlyError.invalidRequest) { try await plain.setPinned(true, chatId: "a") }
        #expect(await (try? plain.loadMoreChats()) == false)
        #expect(await (try? plain.search(query: "a")) == [])
        var folders: [[ChatFolder]] = []
        for await value in plain.folders() { folders.append(value) }
        #expect(folders == [[]])
    }
}
