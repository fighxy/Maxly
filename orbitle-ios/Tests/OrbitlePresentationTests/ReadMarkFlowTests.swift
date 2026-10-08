import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

/// Виртуальные часы для паузы отметки: сон кончается, когда время дошло до его срока.
private final class ReadClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now: Duration = .zero
    /// Сколько снов ждут сейчас.
    var waiting: Int { lock.withLock { waiters.count } }
    private var waiters: [UUID: (deadline: Duration, continuation: CheckedContinuation<Void, Error>)] = [:]
    private var cancelled: Set<UUID> = []

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let early = lock.withLock { () -> Bool in
                    if cancelled.remove(id) != nil { return true }
                    waiters[id] = (now + duration, continuation)
                    return false
                }
                if early { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let waiter = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                if let waiter = waiters.removeValue(forKey: id) { return waiter.continuation }
                cancelled.insert(id)
                return nil
            }
            waiter?.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            now += duration
            let ready = waiters.filter { $0.value.deadline <= now }
            ready.keys.forEach { waiters.removeValue(forKey: $0) }
            return ready.values.map(\.continuation)
        }
        due.forEach { $0.resume() }
    }
}

/// Сообщение с серверным id `id` и временем `id` секунд.
private func message(_ id: Int, author: String = "bob") -> Message {
    Message(id: "\(id)", serverId: "\(id)", chatId: "c", authorId: author, text: "m\(id)",
            timestamp: Date(timeIntervalSince1970: Double(id)), status: .sent)
}

@Suite("Отметка прочтения из экрана чата")
@MainActor
struct ReadMarkFlowTests {
    private let clock = ReadClock()
    private let repository = FakeMessageRepository()
    private let chats = FakeChatRepository()

    private func opened(unread: Int = 3, feed: [Message] = (1...5).map { message($0) }) async -> ChatViewModel {
        let clock = clock
        let model = ChatViewModel(
            chatId: "c", currentUserId: "me", messages: repository, chats: chats,
            readMarkSleep: { try await clock.sleep($0) }
        )
        model.noteUnreadOnOpen(unread)
        await model.loadLatest()
        model.activate()
        repository.emit(feed)
        _ = await eventually { model.messages.count == feed.count }
        model.setScreenActive(true)
        return model
    }

    /// Отпустить главный актор: задача паузы успевает уснуть или отправить.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    /// Виртуальное время идёт, когда пауза ждущей отметки уже заведена: сон начинается в
    /// задаче, и без этого время могло уйти раньше него.
    private func pass(_ milliseconds: Int, _ model: ChatViewModel) async {
        _ = await eventually { model.readMarks?.pending == nil || clock.waiting > 0 }
        clock.advance(by: .milliseconds(milliseconds))
        await settle()
    }

    private var sent: [String] { get async { await chats.readMarks } }

    @Test("Отметка уходит через 200 мс после того, как сообщение увидено, через ядро с id и временем")
    func sendsAfterDelay() async {
        let model = await opened()
        model.noteVisible(newestSeen: "3", atBottom: false)
        await pass(199, model)
        #expect(await sent.isEmpty)
        await pass(1, model)
        #expect(await eventually { await sent == ["c:3@3000"] })
        model.deactivate()
    }

    @Test("Ушли с экрана раньше 200 мс — ничего не уходит; вернулись — читается видимое")
    func leavingCancels() async {
        let model = await opened()
        model.noteVisible(newestSeen: "4", atBottom: false)
        await pass(150, model)
        model.endReadSession()
        await pass(1_000, model)
        #expect(await sent.isEmpty)
        // Новый показ экрана сообщает своё.
        model.setScreenActive(true)
        model.noteVisible(newestSeen: "2", atBottom: false)
        await pass(200, model)
        #expect(await eventually { await sent == ["c:2@2000"] })
        model.deactivate()
    }

    @Test("Приложение ушло в фон — ждущая отметка снята; вернулось — уходит заново")
    func backgroundCancels() async {
        let model = await opened()
        model.noteVisible(newestSeen: "4", atBottom: false)
        await pass(100, model)
        model.setScreenActive(false)
        await pass(1_000, model)
        #expect(await sent.isEmpty)
        model.setScreenActive(true)
        await pass(199, model)
        #expect(await sent.isEmpty)
        await pass(1, model)
        #expect(await eventually { await sent == ["c:4@4000"] })
        model.deactivate()
    }

    @Test("Быстрая прокрутка через несколько сообщений — одна отметка о последнем")
    func fastScroll() async {
        let model = await opened()
        for id in ["1", "2", "3", "4"] {
            model.noteVisible(newestSeen: id, atBottom: false)
            await pass(150, model)
        }
        #expect(await sent.isEmpty)
        await pass(50, model)
        #expect(await eventually { await sent == ["c:4@4000"] })
        await pass(1_000, model)
        #expect(await sent == ["c:4@4000"])
        model.deactivate()
    }

    @Test("Отметка не новее отправленной не уходит: прокрутка вверх ничего не шлёт")
    func olderSuppressed() async {
        let model = await opened()
        model.noteVisible(newestSeen: "4", atBottom: false)
        await pass(200, model)
        #expect(await eventually { await sent == ["c:4@4000"] })
        model.noteVisible(newestSeen: "1", atBottom: false)
        await pass(500, model)
        model.noteVisible(newestSeen: "4", atBottom: false)
        await pass(500, model)
        #expect(await sent == ["c:4@4000"])
        model.noteVisible(newestSeen: "5", atBottom: false)
        await pass(200, model)
        #expect(await eventually { await sent == ["c:4@4000", "c:5@5000"] })
        model.deactivate()
    }

    @Test("Лента у низа: новое сообщение читается само, после паузы")
    func followingReadsNewMessages() async {
        let model = await opened()
        model.noteVisible(newestSeen: "5", atBottom: true)
        await pass(200, model)
        #expect(await eventually { await sent == ["c:5@5000"] })
        repository.emit((1...6).map { message($0) })
        _ = await eventually { model.messages.count == 6 }
        await pass(200, model)
        #expect(await eventually { await sent == ["c:5@5000", "c:6@6000"] })
        model.deactivate()
    }

    @Test("Лента не у низа: новое сообщение ниже экрана не читается")
    func notFollowingKeepsNewUnread() async {
        let model = await opened()
        model.noteVisible(newestSeen: "3", atBottom: false)
        await pass(200, model)
        #expect(await eventually { await sent == ["c:3@3000"] })
        repository.emit((1...6).map { message($0) })
        _ = await eventually { model.messages.count == 6 }
        await pass(1_000, model)
        #expect(await sent == ["c:3@3000"])
        model.deactivate()
    }

    @Test("Пометка «непрочитано» снимает ждущую отметку и не даёт новой")
    func markUnreadBlocks() async {
        let model = await opened()
        model.noteVisible(newestSeen: "3", atBottom: false)
        await pass(100, model)
        model.requestMarkUnread(message(2))
        model.noteVisible(newestSeen: "5", atBottom: true)
        await pass(1_000, model)
        #expect(await sent.isEmpty)
        // Экран закрылся; следующее открытие читает как обычно.
        model.endReadSession()
        model.noteUnreadOnOpen(4)
        model.setScreenActive(true)
        model.noteVisible(newestSeen: "4", atBottom: false)
        await pass(200, model)
        #expect(await eventually { await sent == ["c:4@4000"] })
        model.deactivate()
    }

    @Test("Ошибка отметки не считается отправленной: следующий кандидат повторяет")
    func failureRetries() async {
        let model = await opened()
        await chats.set(readMarkError: .networkUnavailable)
        model.noteVisible(newestSeen: "3", atBottom: false)
        await pass(200, model)
        #expect(await eventually { await sent == ["c:3@3000"] })
        await chats.set(readMarkError: nil)
        model.noteVisible(newestSeen: "3", atBottom: false)
        await pass(200, model)
        #expect(await eventually { await sent == ["c:3@3000", "c:3@3000"] })
        #expect(model.error == nil)
        model.deactivate()
    }
}
