import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Кэш карточек профиля")
struct ChatProfileCacheTests {
    @Test("Карточка переживает перезапуск, а «в сети» из кэша — «недавно»")
    func roundTrip() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let card = ChatProfile(
            kind: .bot, chatId: "-42", peerId: "9", title: "Помощник",
            link: "helper_bot", presence: .online, commands: [.init(name: "start", description: "Начать")]
        )
        await ChatProfileCache(directory: directory).save(card)
        let restored = await ChatProfileCache(directory: directory).profile(chatId: "-42")
        #expect(restored?.title == "Помощник")
        #expect(restored?.commands.first?.name == "start")
        #expect(restored?.presence == .recently)
    }

    @Test("Выход из аккаунта стирает карточки")
    func erase() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = ChatProfileCache(directory: directory)
        await cache.save(ChatProfile(kind: .user, chatId: "1", title: "Анна"))
        await cache.removeAll()
        #expect(await ChatProfileCache(directory: directory).profile(chatId: "1") == nil)
    }
}
