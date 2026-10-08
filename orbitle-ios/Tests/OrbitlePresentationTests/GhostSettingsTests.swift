import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

/// Ядро с режимом призрака: флаги в памяти, свой статус — заданный, запросы считаются.
final class FakeGhostControls: GhostControls, @unchecked Sendable {
    private let lock = NSLock()
    private var state = GhostState()
    private var presence: Contact.Presence = .online
    private var asked = 0
    private var watchers: [AsyncStream<GhostState>.Continuation] = []

    var presenceValue: Contact.Presence {
        get { lock.withLock { presence } }
        set { lock.withLock { presence = newValue } }
    }

    var presenceChecks: Int { lock.withLock { asked } }

    func ghostMode() -> Bool { lock.withLock { state.ghostMode } }
    func setGhostMode(_ enabled: Bool) async { publish { $0.ghostMode = enabled } }
    func hideReadReceipts() -> Bool { lock.withLock { state.hideReadReceipts } }
    func setHideReadReceipts(_ hidden: Bool) async { publish { $0.hideReadReceipts = hidden } }

    func ghostChanges() -> AsyncStream<GhostState> {
        let (stream, continuation) = AsyncStream<GhostState>.makeStream()
        let current = lock.withLock { () -> GhostState in
            watchers.append(continuation)
            return state
        }
        continuation.yield(current)
        return stream
    }

    func checkOwnPresence() async throws(OrbitleError) -> Contact.Presence {
        lock.withLock {
            asked += 1
            return presence
        }
    }

    /// Изменение, пришедшее из ядра (например, с другого экрана).
    func publish(_ change: (inout GhostState) -> Void) {
        let (value, list) = lock.withLock { () -> (GhostState, [AsyncStream<GhostState>.Continuation]) in
            change(&state)
            return (state, watchers)
        }
        for watcher in list { watcher.yield(value) }
    }
}

final class MemorySelfCheckStore: SelfCheckStore, @unchecked Sendable {
    var value = true
    func showsOwnPresence() -> Bool { value }
    func setShowsOwnPresence(_ shows: Bool) { value = shows }
}

/// Часы опроса, которые двигает тест: каждый сон ждёт `advance()`, отмена будит с ошибкой.
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
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
                    waiters[id] = continuation
                    return false
                }
                if early { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let waiter = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                if let waiter = waiters.removeValue(forKey: id) { return waiter }
                cancelled.insert(id)
                return nil
            }
            waiter?.resume(throwing: CancellationError())
        }
    }

    /// Проходит один интервал: все ждущие сны заканчиваются.
    func advance() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            let list = Array(waiters.values)
            waiters.removeAll()
            return list
        }
        for waiter in all { waiter.resume() }
    }
}

@MainActor
private func makeModel(
    _ controls: FakeGhostControls = FakeGhostControls(),
    store: MemorySelfCheckStore = MemorySelfCheckStore(),
    sleeper: ManualSleeper,
    foreground: Bool = true
) -> GhostSettingsModel {
    let zone = TimeZone(identifier: "Europe/Moscow")!
    return GhostSettingsModel(
        controls: controls,
        store: store,
        isAppForeground: foreground,
        formatter: ContactsFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: zone)),
        sleep: { try await sleeper.sleep($0) }
    )
}

@MainActor
@Suite("Режим призрака и свой статус")
struct GhostSettingsModelTests {
    @Test("Пока шапка на экране, статус спрашивается сразу и потом каждые 15 секунд")
    func cadence() async {
        let controls = FakeGhostControls()
        let sleeper = ManualSleeper()
        let model = makeModel(controls, sleeper: sleeper)
        #expect(controls.presenceChecks == 0)
        model.setScreenVisible(true)
        #expect(await eventually { controls.presenceChecks == 1 && sleeper.pending == 1 })
        #expect(sleeper.requested == [.seconds(15)])
        #expect(model.ownPresenceText(now: Date()) == "в сети")
        sleeper.advance()
        #expect(await eventually { controls.presenceChecks == 2 && sleeper.pending == 1 })
        sleeper.advance()
        #expect(await eventually { controls.presenceChecks == 3 && sleeper.pending == 1 })
        #expect(sleeper.requested == [.seconds(15), .seconds(15), .seconds(15)])
        #expect(model.isPolling)
    }

    @Test("Шапка не на экране — запросов нет; ушла с экрана — опрос стоит")
    func visibility() async {
        let controls = FakeGhostControls()
        let sleeper = ManualSleeper()
        let model = makeModel(controls, sleeper: sleeper)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controls.presenceChecks == 0)
        model.setScreenVisible(true)
        #expect(await eventually { controls.presenceChecks == 1 && sleeper.pending == 1 })
        model.setScreenVisible(false)
        #expect(await eventually { sleeper.pending == 0 })
        #expect(!model.isPolling)
        sleeper.advance()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controls.presenceChecks == 1)
        // Снова на экране — сразу запрос.
        model.setScreenVisible(true)
        #expect(await eventually { controls.presenceChecks == 2 })
    }

    @Test("В фоне опрос стоит, при возврате — сразу запрос")
    func foreground() async {
        let controls = FakeGhostControls()
        let sleeper = ManualSleeper()
        let model = makeModel(controls, sleeper: sleeper)
        model.setScreenVisible(true)
        #expect(await eventually { controls.presenceChecks == 1 && sleeper.pending == 1 })
        model.setAppForeground(false)
        #expect(await eventually { sleeper.pending == 0 })
        sleeper.advance()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controls.presenceChecks == 1)
        model.setAppForeground(true)
        #expect(await eventually { controls.presenceChecks == 2 && sleeper.pending == 1 })
    }

    @Test("Запуск в фоне: шапка на экране, но запросов нет до возврата")
    func startsInBackground() async {
        let controls = FakeGhostControls()
        let sleeper = ManualSleeper()
        let model = makeModel(controls, sleeper: sleeper, foreground: false)
        model.setScreenVisible(true)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controls.presenceChecks == 0)
        model.setAppForeground(true)
        #expect(await eventually { controls.presenceChecks == 1 })
    }

    @Test("Переключение режима призрака — сразу запрос и отсчёт 15 секунд заново")
    func ghostToggle() async {
        let controls = FakeGhostControls()
        let sleeper = ManualSleeper()
        let model = makeModel(controls, sleeper: sleeper)
        model.setScreenVisible(true)
        #expect(await eventually { controls.presenceChecks == 1 && sleeper.pending == 1 })
        controls.presenceValue = .lastSeen(Date(timeIntervalSince1970: 1_790_674_800))
        await model.setGhostMode(true)
        #expect(controls.ghostMode())
        #expect(model.ghostMode)
        #expect(await eventually { controls.presenceChecks == 2 && sleeper.pending == 1 })
        // Прежний сон отменён, новый один.
        #expect(sleeper.requested.count == 2)
        let now = Date(timeIntervalSince1970: 1_790_683_200)
        #expect(model.ownPresenceText(now: now) == "был(а) в 12:40")
        #expect(!model.isOwnPresenceOnline)
    }

    @Test("Переключение режима, пока шапки нет на экране, — один запрос без опроса")
    func ghostToggleOffScreen() async {
        let controls = FakeGhostControls()
        let sleeper = ManualSleeper()
        let model = makeModel(controls, sleeper: sleeper)
        await model.setGhostMode(true)
        #expect(await eventually { controls.presenceChecks == 1 })
        try? await Task.sleep(for: .milliseconds(20))
        #expect(sleeper.pending == 0)
        #expect(!model.isPolling)
    }

    @Test("«Показывать мой онлайн» выключено — строки и запросов нет; включили — сразу запрос")
    func selfCheckSwitch() async {
        let controls = FakeGhostControls()
        let store = MemorySelfCheckStore()
        let sleeper = ManualSleeper()
        let model = makeModel(controls, store: store, sleeper: sleeper)
        model.setScreenVisible(true)
        #expect(await eventually { controls.presenceChecks == 1 && sleeper.pending == 1 })
        model.setShowsOwnPresence(false)
        #expect(!store.value)
        #expect(model.ownPresenceText(now: Date()) == nil)
        #expect(await eventually { sleeper.pending == 0 })
        await model.setGhostMode(true)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controls.presenceChecks == 1)
        model.setShowsOwnPresence(true)
        #expect(store.value)
        #expect(await eventually { controls.presenceChecks == 2 && model.ownPresenceText(now: Date()) != nil })
    }

    @Test("Выключенная строка читается из хранилища при запуске")
    func storedSwitch() async {
        let controls = FakeGhostControls()
        let store = MemorySelfCheckStore()
        store.value = false
        let sleeper = ManualSleeper()
        let model = makeModel(controls, store: store, sleeper: sleeper)
        #expect(!model.showsOwnPresence)
        model.setScreenVisible(true)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controls.presenceChecks == 0)
    }

    @Test("Флаги ядра приходят в переключатели; отметки о прочтении меняются отдельно")
    func flags() async {
        let controls = FakeGhostControls()
        let model = makeModel(controls, sleeper: ManualSleeper())
        model.activate()
        controls.publish { $0.ghostMode = true }
        #expect(await eventually { model.ghostMode })
        await model.setHideReadReceipts(true)
        #expect(controls.hideReadReceipts())
        #expect(model.hideReadReceipts)
        #expect(controls.ghostMode())
        model.deactivate()
    }

    @Test("Неизвестный статус — строки нет")
    func unknownPresence() async {
        let controls = FakeGhostControls()
        controls.presenceValue = .unknown
        let model = makeModel(controls, sleeper: ManualSleeper())
        await model.checkNow()
        #expect(model.ownPresence == .unknown)
        #expect(model.ownPresenceText(now: Date()) == nil)
    }
}
