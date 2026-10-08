import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

/// Мост ядра с режимом призрака и приватностью: всё в памяти, вызовы записываются.
private final class FakeGhostPrivacyCore: GhostPrivacyCore, @unchecked Sendable {
    private let lock = NSLock()
    private var ghost = false
    private var hidden = false
    private var settings: AccountSettings
    private var eventWatchers: [AsyncStream<CoreEvent>.Continuation] = []
    private var settingsWatchers: [AsyncStream<AccountSettings>.Continuation] = []
    private var log: [String] = []
    var ownPresence: Result<CorePresence?, CoreFailure> = .success(nil)
    var readOnly: Set<String> = []
    var localMarks: [String: Int64] = [:]
    var failure: CoreFailure?

    init(_ settings: AccountSettings = AccountSettings(isKnown: true)) {
        self.settings = settings
    }

    var calls: [String] { lock.withLock { log } }

    private func record(_ call: String) {
        lock.withLock { log.append(call) }
    }

    /// Событие ядра, как из `watchEvents`.
    func push(_ kind: CoreEvent.Kind, _ text: String) {
        let event = CoreEvent(kind: kind, chatId: "", messageId: "", authorId: "", text: text, title: "", chatType: "", timeMs: 0, unread: -1)
        for watcher in lock.withLock({ eventWatchers }) { watcher.yield(event) }
    }

    /// Флаг поменялся в ядре без события (для незнакомого `text`).
    func setQuietly(ghost value: Bool) {
        lock.withLock { ghost = value }
    }

    func setGhostMode(_ enabled: Bool) async {
        record("setGhostMode(\(enabled))")
        lock.withLock { ghost = enabled }
        push(.ghostMode, enabled ? "on" : "off")
    }

    func ghostMode() -> Bool { lock.withLock { ghost } }

    func setHideReadReceipts(_ enabled: Bool) async {
        record("setHideReadReceipts(\(enabled))")
        lock.withLock { hidden = enabled }
        push(.hideReadReceipts, enabled ? "on" : "off")
    }

    func hideReadReceipts() -> Bool { lock.withLock { hidden } }

    func localReadMarkOf(chatId: String) -> Int64 {
        record("localReadMarkOf(\(chatId))")
        return localMarks[chatId] ?? 0
    }

    func checkOwnPresence() async throws -> CorePresence? {
        record("checkOwnPresence")
        return try ownPresence.get()
    }

    func setPrivacy(key: String, value: String) async throws -> AccountSettings {
        record("setPrivacy(\(key), \(value))")
        if let failure { throw failure }
        return lock.withLock { settings }
    }

    func setPrivacyFlag(key: String, enabled: Bool) async throws -> AccountSettings {
        record("setPrivacyFlag(\(key), \(enabled))")
        if let failure { throw failure }
        return lock.withLock { settings }
    }

    func isPrivacyReadOnly(key: String) -> Bool {
        record("isPrivacyReadOnly(\(key))")
        return readOnly.contains(key)
    }

    func accountSettings() -> AsyncStream<AccountSettings> {
        let (stream, continuation) = AsyncStream<AccountSettings>.makeStream()
        let now = lock.withLock { () -> AccountSettings in
            settingsWatchers.append(continuation)
            return settings
        }
        continuation.yield(now)
        return stream
    }

    /// Новый конфиг с сервера.
    func pushSettings(_ change: (inout AccountSettings) -> Void) {
        let (next, list) = lock.withLock { () -> (AccountSettings, [AsyncStream<AccountSettings>.Continuation]) in
            change(&settings)
            return (settings, settingsWatchers)
        }
        for watcher in list { watcher.yield(next) }
    }

    func events() -> AsyncStream<CoreEvent> {
        let (stream, continuation) = AsyncStream<CoreEvent>.makeStream()
        lock.withLock { eventWatchers.append(continuation) }
        return stream
    }
}

/// Первое значение потока, для которого `match` истинно; `nil` — не дождались за 3 с.
private func first<T: Sendable>(_ stream: AsyncStream<T>, where match: @escaping @Sendable (T) -> Bool) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            for await value in stream where match(value) { return value }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(3))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

@Suite("Режим призрака и приватность через мост ядра")
struct PrivacyControlsTests {
    @Test("Флаги режима уходят в ядро и приходят его событиями")
    func ghostFlags() async {
        let core = FakeGhostPrivacyCore()
        let controls = CoreGhostPrivacyControls(core: core)
        #expect(!controls.ghostMode())
        #expect(!controls.hideReadReceipts())
        let changes = controls.ghostChanges()
        await controls.setGhostMode(true)
        await controls.setHideReadReceipts(true)
        #expect(core.calls == ["setGhostMode(true)", "setHideReadReceipts(true)"])
        #expect(controls.ghostMode())
        #expect(controls.hideReadReceipts())
        let state = await first(changes) { $0.ghostMode && $0.hideReadReceipts }
        #expect(state == GhostState(ghostMode: true, hideReadReceipts: true))
    }

    @Test("Поток флагов: сначала текущие, затем события; чужие события не мешают")
    func ghostEvents() async {
        let core = FakeGhostPrivacyCore()
        let controls = CoreGhostPrivacyControls(core: core)
        let changes = controls.ghostChanges()
        #expect(await first(changes) { _ in true } == GhostState())
        core.push(.presence, "on")
        core.push(.hideReadReceipts, "on")
        #expect(await first(changes) { $0.hideReadReceipts } == GhostState(ghostMode: false, hideReadReceipts: true))
        core.push(.ghostMode, "on")
        #expect(await first(changes) { $0.ghostMode } == GhostState(ghostMode: true, hideReadReceipts: true))
        core.push(.ghostMode, "off")
        #expect(await first(changes) { !$0.ghostMode } == GhostState(ghostMode: false, hideReadReceipts: true))
    }

    @Test("Незнакомый текст события — флаг перечитывается из ядра")
    func ghostEventFallback() {
        let core = FakeGhostPrivacyCore()
        core.setQuietly(ghost: true)
        let event = CoreEvent(kind: .ghostMode, chatId: "", messageId: "", authorId: "", text: "", title: "", chatType: "", timeMs: 0, unread: -1)
        let next = CoreGhostPrivacyControls.state(after: event, from: GhostState(), core: core)
        #expect(next == GhostState(ghostMode: true, hideReadReceipts: false))
        let other = CoreEvent(kind: .typing, chatId: "1", messageId: "", authorId: "2", text: "on", title: "", chatType: "", timeMs: 0, unread: -1)
        #expect(CoreGhostPrivacyControls.state(after: other, from: GhostState(), core: core) == nil)
    }

    @Test("Свой статус — свежий ответ ядра; молчание сервера — неизвестно; ошибка — OrbitleError")
    func ownPresence() async throws {
        let core = FakeGhostPrivacyCore()
        let controls = CoreGhostPrivacyControls(core: core)
        core.ownPresence = .success(CorePresence(userId: "7", status: 1))
        #expect(try await controls.checkOwnPresence() == .online)
        core.ownPresence = .success(CorePresence(userId: "7", status: 0, seenMs: 1_790_674_800_000))
        #expect(try await controls.checkOwnPresence() == .lastSeen(Date(timeIntervalSince1970: 1_790_674_800)))
        core.ownPresence = .success(nil)
        #expect(try await controls.checkOwnPresence() == .unknown)
        core.ownPresence = .failure(CoreFailure(kind: "NETWORK", key: nil))
        await #expect(throws: OrbitleError.networkUnavailable) { try await controls.checkOwnPresence() }
        #expect(core.calls.filter { $0 == "checkOwnPresence" }.count == 4)
    }

    @Test("Доступ уходит строкой ядра (NOBODY), флаги — setPrivacyFlag")
    func setPrivacy() async throws {
        let core = FakeGhostPrivacyCore(AccountSettings(isKnown: true, phonePrivacy: .nobody))
        let controls = CoreGhostPrivacyControls(core: core)
        let result = try await controls.setPrivacy(.phoneNumberPrivacy, .access(.nobody))
        #expect(result.phonePrivacy == .nobody)
        _ = try await controls.setPrivacy(.incomingCall, .access(.contacts))
        _ = try await controls.setPrivacy(.searchByPhone, .access(.everybody))
        _ = try await controls.setPrivacy(.chatsInvite, .access(.contacts))
        _ = try await controls.setPrivacy(.contentLevelAccess, .flag(true))
        _ = try await controls.setPrivacy(.hidden, .flag(false))
        _ = try await controls.setPrivacy(.safeMode, .flag(true))
        #expect(core.calls == [
            "setPrivacy(PHONE_NUMBER_PRIVACY, NOBODY)",
            "setPrivacy(INCOMING_CALL, CONTACTS)",
            "setPrivacy(SEARCH_BY_PHONE, ALL)",
            "setPrivacy(CHATS_INVITE, CONTACTS)",
            "setPrivacyFlag(CONTENT_LEVEL_ACCESS, true)",
            "setPrivacyFlag(HIDDEN, false)",
            "setPrivacyFlag(SAFE_MODE, true)",
        ])
    }

    @Test("Значение не того вида в ядро не уходит; отказ ядра — OrbitleError")
    func setPrivacyErrors() async {
        let core = FakeGhostPrivacyCore()
        let controls = CoreGhostPrivacyControls(core: core)
        await #expect(throws: OrbitleError.invalidRequest) { try await controls.setPrivacy(.hidden, .access(.contacts)) }
        await #expect(throws: OrbitleError.invalidRequest) { try await controls.setPrivacy(.incomingCall, .flag(true)) }
        #expect(core.calls.isEmpty)
        core.failure = CoreFailure(kind: "SERVER", key: "privacy.locked")
        await #expect(throws: OrbitleError.server(code: "privacy.locked")) {
            try await controls.setPrivacy(.searchByPhone, .access(.contacts))
        }
    }

    @Test("Только для чтения и локальная отметка — вопросы к ядру")
    func readOnlyAndLocalMark() {
        let core = FakeGhostPrivacyCore()
        core.readOnly = ["SEARCH_BY_PHONE", "SAFE_MODE"]
        core.localMarks = ["42": 1_790_000_000_000]
        let controls = CoreGhostPrivacyControls(core: core)
        #expect(controls.isPrivacyReadOnly(.searchByPhone))
        #expect(controls.isPrivacyReadOnly(.safeMode))
        #expect(!controls.isPrivacyReadOnly(.hidden))
        #expect(controls.localReadMark(chatId: "42") == 1_790_000_000_000)
        #expect(controls.localReadMark(chatId: "43") == 0)
    }

    @Test("Настройки — поток ядра как есть, без отметок устройства")
    func settingsStream() async {
        let core = FakeGhostPrivacyCore(AccountSettings(isKnown: true, familyProtection: .manageable, privacyLocked: true))
        let controls = CoreGhostPrivacyControls(core: core)
        let stream = controls.privacySettings()
        let now = await first(stream) { $0.isKnown }
        #expect(now?.familyProtection == .manageable)
        #expect(now?.privacyLocked == true)
        core.pushSettings { $0.familyProtection = .off; $0.privacyLocked = false; $0.incomingCall = .contacts }
        let next = await first(stream) { !$0.privacyLocked }
        #expect(next?.incomingCall == .contacts)
    }
}

@Suite("Настройки устройства для режима призрака")
struct GhostDefaultsTests {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test("«Показывать мой онлайн» по умолчанию включено и сохраняется")
    func selfCheckStore() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSelfCheckStore(defaults: defaults)
        #expect(store.showsOwnPresence())
        store.setShowsOwnPresence(false)
        #expect(!UserDefaultsSelfCheckStore(defaults: defaults).showsOwnPresence())
    }

    @Test("Разовая чистка убирает старые ключи и сохраняет «Показывать мой онлайн»")
    func migration() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "orbitle.ghost.enabled")
        defaults.set(true, forKey: "orbitle.ghost.hideReadReceipts")
        defaults.set(false, forKey: "orbitle.ghost.showsOwnPresence")
        defaults.set("CONTACTS", forKey: "orbitle.privacy.local.INCOMING_CALL")
        defaults.set("keep", forKey: "orbitle.chatList.other")
        GhostDefaultsMigration.run(defaults)
        #expect(defaults.object(forKey: "orbitle.ghost.enabled") == nil)
        #expect(defaults.object(forKey: "orbitle.ghost.hideReadReceipts") == nil)
        #expect(defaults.object(forKey: "orbitle.ghost.showsOwnPresence") == nil)
        #expect(defaults.object(forKey: "orbitle.privacy.local.INCOMING_CALL") == nil)
        #expect(defaults.string(forKey: "orbitle.chatList.other") == "keep")
        #expect(!UserDefaultsSelfCheckStore(defaults: defaults).showsOwnPresence())
        #expect(defaults.bool(forKey: GhostDefaultsMigration.doneKey))
        // Второй запуск ничего не трогает.
        defaults.set(true, forKey: "orbitle.ghost.enabled")
        GhostDefaultsMigration.run(defaults)
        #expect(defaults.bool(forKey: "orbitle.ghost.enabled"))
    }
}
