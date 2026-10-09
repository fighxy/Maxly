import Foundation
import Testing
@testable import MaxlyDomain

/// Часы, которые двигает тест: сон кончается, когда виртуальное время дошло до его срока.
final class VirtualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var now: Duration = .zero
    private var waiters: [UUID: (deadline: Duration, continuation: CheckedContinuation<Void, Error>)] = [:]
    private var cancelled: Set<UUID> = []
    private var durations: [Duration] = []

    /// Все запрошенные сны по порядку.
    var requested: [Duration] { lock.withLock { durations } }
    /// Сколько снов ждут сейчас.
    var pending: Int { lock.withLock { waiters.count } }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let early = lock.withLock { () -> Bool in
                    durations.append(duration)
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

    /// Время идёт вперёд: сны со сроком не позже нового времени кончаются.
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

/// Отпустить главный актор: задачи планировщика успевают начать сон или отправить отметку.
@MainActor
func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

/// Ждёт условия до `timeout` реального времени.
@MainActor
func until(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else { return false }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

/// Двигает виртуальное время, когда пауза ждущего кандидата уже заведена: сон начинается в
/// задаче, и без этого время могло уйти раньше, чем он заведён.
@MainActor
func advance(_ sleeper: VirtualSleeper, _ scheduler: ReadMarkScheduler, by duration: Duration) async {
    _ = await until { scheduler.pending == nil || sleeper.pending > 0 }
    sleeper.advance(by: duration)
    await settle()
}

@Suite("Отметка прочтения: видимость")
struct ReadVisibilityTests {
    private let screen = ReadSpan(minY: 0, maxY: 1000)

    private func row(_ id: String, order: Int, at minY: Double, height: Double = 100) -> ReadRowFrame {
        ReadRowFrame(id: id, order: order, minY: minY, height: height)
    }

    @Test("Правила в одном месте: 200 мс и 30 %")
    func constants() {
        #expect(ReadMarkRules.delay == .milliseconds(200))
        #expect(ReadMarkRules.minVisibleFraction == 0.3)
    }

    @Test("29 % высоты — не увидено, 30 % — увидено")
    func threshold() {
        #expect(!ReadVisibility.isSeen(row("a", order: 0, at: 971), in: screen))
        #expect(ReadVisibility.isSeen(row("a", order: 0, at: 970), in: screen))
        // То же сверху: строка уходит за верх области.
        #expect(!ReadVisibility.isSeen(row("a", order: 0, at: -71), in: screen))
        #expect(ReadVisibility.isSeen(row("a", order: 0, at: -70), in: screen))
        // Дробные точки: ровно 30 % не теряются на округлении.
        #expect(ReadVisibility.isSeen(row("a", order: 0, at: 1000 - 13.2, height: 44), in: screen))
        #expect(abs(ReadVisibility.visibleFraction(minY: 971, height: 100, in: screen) - 0.29) < 1e-9)
    }

    @Test("Нулевая высота и пустая область ничего не показывают")
    func degenerate() {
        #expect(ReadVisibility.visibleFraction(minY: 10, height: 0, in: screen) == 0)
        #expect(ReadVisibility.visibleFraction(minY: 10, height: 100, in: ReadSpan(minY: 500, maxY: 500)) == 0)
        #expect(ReadVisibility.visibleFraction(minY: 2000, height: 100, in: screen) == 0)
    }

    @Test("Область без шапки, поля ввода и клавиатуры")
    func areaExcludesChrome() {
        // Лента на весь экран, шапка до 100, поле ввода с 900.
        let open = ReadVisibility.area(viewport: screen, headerBottom: 100, composerTop: 900)
        #expect(open == ReadSpan(minY: 100, maxY: 900))
        // Открыта клавиатура: всё ниже 600 закрыто.
        let typing = ReadVisibility.area(viewport: screen, headerBottom: 100, composerTop: 900, keyboardTop: 600)
        #expect(typing == ReadSpan(minY: 100, maxY: 600))

        // Под шапкой: видно 29 из 100 — не прочитано, 30 — прочитано.
        #expect(!ReadVisibility.isSeen(row("a", order: 0, at: 29), in: open))
        #expect(ReadVisibility.isSeen(row("a", order: 0, at: 30), in: open))
        // Под полем ввода.
        #expect(!ReadVisibility.isSeen(row("b", order: 1, at: 871), in: open))
        #expect(ReadVisibility.isSeen(row("b", order: 1, at: 870), in: open))
        // Та же строка над закрытой клавиатурой видна, под открытой — нет.
        let underKeyboard = row("c", order: 2, at: 571)
        #expect(ReadVisibility.isSeen(underKeyboard, in: open))
        #expect(!ReadVisibility.isSeen(underKeyboard, in: typing))
    }

    @Test("Безопасные отступы ленты и явные границы не вычитаются дважды")
    func safeInsets() {
        // Лента уходит под панель навигации (88) и поле ввода (80): отступы её рамки.
        let area = ReadVisibility.area(viewport: screen, safeTop: 88, safeBottom: 80)
        #expect(area == ReadSpan(minY: 88, maxY: 920))
        // Те же границы ещё и явно: область не меняется.
        #expect(ReadVisibility.area(viewport: screen, safeTop: 88, safeBottom: 80, headerBottom: 88, composerTop: 920) == area)
        // Плашка закрепа под шапкой опускает верх.
        #expect(ReadVisibility.area(viewport: screen, safeTop: 88, headerBottom: 140).minY == 140)
        // Неизмеренное поле ввода (0) не режет область.
        #expect(ReadVisibility.area(viewport: screen, composerTop: 0) == screen)
        // Клавиатура выше шапки: читать нечего.
        let closed = ReadVisibility.area(viewport: screen, headerBottom: 300, keyboardTop: 200)
        #expect(closed.isEmpty)
        #expect(ReadVisibility.newestSeen([row("a", order: 0, at: 250)], in: closed) == nil)
    }

    @Test("Самое новое увиденное: наибольшее место среди строк, видных на 30 %")
    func newest() {
        let area = ReadSpan(minY: 100, maxY: 900)
        let rows = [
            row("1", order: 1, at: 50),   // половина под шапкой — видно
            row("2", order: 2, at: 400),
            row("3", order: 3, at: 871),  // выглядывает из-под поля ввода на 29 %
        ]
        #expect(ReadVisibility.newestSeen(rows, in: area) == "2")
        // Порядок в массиве не важен, важно место в ленте.
        #expect(ReadVisibility.newestSeen(rows.reversed(), in: area) == "2")
        #expect(ReadVisibility.newestSeen([row("3", order: 3, at: 870)] + rows, in: area) == "3")
        #expect(ReadVisibility.newestSeen([], in: area) == nil)
    }
}

@Suite("Отметка прочтения: какая новее")
struct ReadMarkOrderTests {
    @Test("Новее по времени, при равном времени — по id сервера")
    func newer() {
        let base = ReadMark(messageId: "100", time: 5_000)
        #expect(ReadMark(messageId: "90", time: 6_000).isNewer(than: base))
        #expect(!ReadMark(messageId: "200", time: 4_000).isNewer(than: base))
        #expect(ReadMark(messageId: "101", time: 5_000).isNewer(than: base))
        #expect(!ReadMark(messageId: "100", time: 5_000).isNewer(than: base))
        #expect(!ReadMark(messageId: "local", time: 5_000).isNewer(than: base))
        #expect(base.isNewer(than: nil))
    }

    @Test("Отметка только у сообщения с сервера: своё неотправленное — нет")
    func fromMessage() {
        let at = Date(timeIntervalSince1970: 1_790_000_000.123)
        let incoming = Message(id: "77", chatId: "c", authorId: "bob", text: "x", timestamp: at, status: .sent)
        #expect(ReadMark(message: incoming) == ReadMark(messageId: "77", time: 1_790_000_000_123))
        let delivered = Message(id: "local-1", serverId: "78", chatId: "c", authorId: "me", text: "x", timestamp: at, status: .sent)
        #expect(ReadMark(message: delivered)?.messageId == "78")
        let sending = Message(id: "local-2", chatId: "c", authorId: "me", text: "x", timestamp: at, status: .sending)
        #expect(ReadMark(message: sending) == nil)
    }
}

@Suite("Отметка прочтения: пауза и порядок")
@MainActor
struct ReadMarkSchedulerTests {
    private func mark(_ id: Int) -> ReadMark {
        ReadMark(messageId: String(id), time: Int64(id) * 1_000)
    }

    private func make(_ sleeper: VirtualSleeper) -> (ReadMarkScheduler, Box) {
        let box = Box()
        let scheduler = ReadMarkScheduler(sleep: { try await sleeper.sleep($0) }) { mark in
            box.sent.append(mark)
            return box.delivers
        }
        return (scheduler, box)
    }

    /// Ушедшие отметки и ответ отправки.
    final class Box {
        var sent: [ReadMark] = []
        var delivers = true
    }

    @Test("Уход с экрана раньше 200 мс — ничего не уходит")
    func leaveBeforeDelay() async {
        let sleeper = VirtualSleeper()
        let (scheduler, box) = make(sleeper)
        scheduler.propose(mark(5))
        await advance(sleeper, scheduler, by: .milliseconds(199))
        scheduler.cancel()
        await advance(sleeper, scheduler, by: .seconds(5))
        #expect(box.sent.isEmpty)
        #expect(scheduler.pending == nil)
        #expect(sleeper.pending == 0)
        #expect(sleeper.requested == [ReadMarkRules.delay])
    }

    @Test("Быстрая прокрутка через несколько сообщений шлёт одну отметку — о последнем")
    func fastScroll() async {
        let sleeper = VirtualSleeper()
        let (scheduler, box) = make(sleeper)
        for id in 1...4 {
            scheduler.propose(mark(id))
            await advance(sleeper, scheduler, by: .milliseconds(150))
        }
        // Последний кандидат ждёт свои 200 мс с момента своей смены.
        #expect(box.sent.isEmpty)
        await advance(sleeper, scheduler, by: .milliseconds(49))
        #expect(box.sent.isEmpty)
        await advance(sleeper, scheduler, by: .milliseconds(1))
        #expect(await until { box.sent == [mark(4)] })
        #expect(scheduler.sent == mark(4))
        await advance(sleeper, scheduler, by: .seconds(1))
        #expect(box.sent == [mark(4)])
    }

    @Test("Отметка не новее отправленной не уходит")
    func olderOrEqualSuppressed() async {
        let sleeper = VirtualSleeper()
        let (scheduler, box) = make(sleeper)
        scheduler.propose(mark(3))
        await advance(sleeper, scheduler, by: .milliseconds(200))
        #expect(await until { box.sent == [mark(3)] })
        // Та же и более старая: таймер даже не заводится.
        scheduler.propose(mark(3))
        scheduler.propose(mark(2))
        #expect(scheduler.pending == nil)
        await advance(sleeper, scheduler, by: .seconds(1))
        #expect(box.sent == [mark(3)])
        #expect(sleeper.requested.count == 1)
        // Новее — уходит.
        scheduler.propose(mark(4))
        await advance(sleeper, scheduler, by: .milliseconds(200))
        #expect(await until { box.sent == [mark(3), mark(4)] })
    }

    @Test("Кандидат старее ждущего не перезапускает паузу и не заменяет его")
    func olderThanPending() async {
        let sleeper = VirtualSleeper()
        let (scheduler, box) = make(sleeper)
        scheduler.propose(mark(5))
        await advance(sleeper, scheduler, by: .milliseconds(150))
        scheduler.propose(mark(4))
        scheduler.propose(mark(5))
        #expect(scheduler.pending == mark(5))
        await advance(sleeper, scheduler, by: .milliseconds(50))
        #expect(await until { box.sent == [mark(5)] })
        #expect(sleeper.requested.count == 1)
    }

    @Test("Неудачная отметка не считается отправленной; новый заход забывает прежнюю")
    func failureAndReset() async {
        let sleeper = VirtualSleeper()
        let (scheduler, box) = make(sleeper)
        box.delivers = false
        scheduler.propose(mark(2))
        await advance(sleeper, scheduler, by: .milliseconds(200))
        #expect(await until { box.sent == [mark(2)] && scheduler.sent == nil })
        box.delivers = true
        scheduler.propose(mark(2))
        await advance(sleeper, scheduler, by: .milliseconds(200))
        #expect(await until { box.sent == [mark(2), mark(2)] && scheduler.sent == mark(2) })
        scheduler.reset()
        #expect(scheduler.sent == nil)
        scheduler.propose(mark(1))
        await advance(sleeper, scheduler, by: .milliseconds(200))
        #expect(await until { box.sent.last == mark(1) })
    }
}
