import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Аккаунт и папки через ядро")
struct AccountRepositoryTests {
    @Test("Полоса над списком получает серверные папки без «Все», с правилами")
    func folderStrip() async {
        let api = MaxAPIClient(core: FakeMaxCore())
        var received: [[ChatFolder]] = []
        for await folders in api.folderUpdates() { received.append(folders) }
        #expect(received.count == 1)
        let folder = received.first?.first
        #expect(received.first?.count == 1)
        #expect(folder?.id == "w")
        #expect(folder?.title == "Работа")
        let channel = Chat(id: "c", title: "c", type: .channel, updatedAt: Date())
        let group = Chat(id: "g", title: "g", type: .group, updatedAt: Date())
        let dialog = Chat(id: "p", title: "p", type: .private, updatedAt: Date())
        #expect(folder?.contains(channel) == true)
        #expect(folder?.contains(group) == true)
        #expect(folder?.contains(dialog) == false)
    }

    @Test("Сеансы: текущий первым, остальные от недавних")
    func sessionsOrder() async throws {
        let core = FakeMaxCore()
        await core.setSessions([
            DeviceSession(id: "old", client: "Web", lastSeen: Date(timeIntervalSince1970: 10)),
            DeviceSession(id: "me", client: "iOS", isCurrent: true, lastSeen: Date(timeIntervalSince1970: 1)),
            DeviceSession(id: "new", client: "Android", lastSeen: Date(timeIntervalSince1970: 50)),
        ])
        let list = try await CoreAccountRepository(core: core).sessions()
        #expect(list.map(\.id) == ["me", "new", "old"])
    }

    @Test("Неверный пароль при смене почты — понятный текст")
    func wrongPassword() async {
        let repo = CoreAccountRepository(core: FakeMaxCore())
        await #expect(throws: MaxlyError.rejected("Неверный пароль")) {
            try await repo.startEmailChange(password: "nope")
        }
        #expect((try? await repo.startEmailChange(password: "ok")) == "track-1")
    }

    @Test("Без ядра настройки недоступны: вызовы отклоняются")
    func unavailable() async {
        let repo = CoreAccountRepository(core: FakeMaxCore())
        await #expect(throws: MaxlyError.self) { try await repo.profile() }
    }
}
