import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

/// Аккаунт для заглушки приватности: настройки сервера, которые тест меняет сам.
private final class ServerSettingsFake: AccountRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var value: AccountSettings
    private var watchers: [AsyncStream<AccountSettings>.Continuation] = []
    private(set) var calls: [String] = []

    init(_ value: AccountSettings) {
        self.value = value
    }

    var current: AccountSettings { lock.withLock { value } }

    /// Сервер прислал новый конфиг.
    func push(_ change: (inout AccountSettings) -> Void) {
        let (next, list) = lock.withLock { () -> (AccountSettings, [AsyncStream<AccountSettings>.Continuation]) in
            change(&value)
            return (value, watchers)
        }
        for watcher in list { watcher.yield(next) }
    }

    private func apply(_ name: String, _ change: (inout AccountSettings) -> Void) -> AccountSettings {
        lock.withLock { calls.append(name) }
        push(change)
        return current
    }

    func settings() -> AsyncStream<AccountSettings> {
        let (stream, continuation) = AsyncStream<AccountSettings>.makeStream()
        let now = lock.withLock { () -> AccountSettings in
            watchers.append(continuation)
            return value
        }
        continuation.yield(now)
        return stream
    }

    func setPhonePrivacy(_ access: PrivacyAccess) async throws(OrbitleError) -> AccountSettings {
        apply("phone") { $0.phonePrivacy = access }
    }
    func setOnlineHidden(_ hidden: Bool) async throws(OrbitleError) -> AccountSettings {
        apply("hidden") { $0.onlineHidden = hidden }
    }
    func setSafeMode(_ enabled: Bool) async throws(OrbitleError) -> AccountSettings {
        apply("safe") { settings in
            settings.safeMode = enabled
            if enabled {
                settings.searchByPhone = .contacts
                settings.incomingCall = .contacts
                settings.chatsInvite = .contacts
                settings.safeContentOnly = true
            }
        }
    }

    func profile() async throws(OrbitleError) -> MyProfile { throw .invalidRequest }
    func updateProfile(firstName: String, lastName: String, about: String) async throws(OrbitleError) -> MyProfile { throw .invalidRequest }
    func uploadAvatar(jpeg: Data) async throws(OrbitleError) -> MyProfile { throw .invalidRequest }
    func removeAvatar() async throws(OrbitleError) -> MyProfile { throw .invalidRequest }
    func deleteAccount() async throws(OrbitleError) -> Date? { throw .invalidRequest }
    func setInactiveTTL(_ ttl: InactiveTTL) async throws(OrbitleError) -> AccountSettings { throw .invalidRequest }
    func setQuickReaction(_ emoji: String) async throws(OrbitleError) -> AccountSettings { throw .invalidRequest }
    func sessions() async throws(OrbitleError) -> [DeviceSession] { throw .invalidRequest }
    func closeOtherSessions() async throws(OrbitleError) { throw .invalidRequest }
    func approveQrLogin(_ link: String) async throws(OrbitleError) { throw .invalidRequest }
    func blockedUsers() async throws(OrbitleError) -> [BlockedUser] { throw .invalidRequest }
    func unblock(userId: String) async throws(OrbitleError) { throw .invalidRequest }
    func twoFactorStatus() async throws(OrbitleError) -> TwoFactorStatus { throw .invalidRequest }
    func startEmailChange(password: String) async throws(OrbitleError) -> String { throw .invalidRequest }
    func sendEmailCode(trackId: String, email: String) async throws(OrbitleError) -> Int { throw .invalidRequest }
    func confirmEmail(trackId: String, code: String) async throws(OrbitleError) -> TwoFactorStatus { throw .invalidRequest }
    func launchMiniApp(_ kind: MiniApp.Kind) async throws(OrbitleError) -> MiniApp { throw .invalidRequest }
    func miniAppCallback(url: URL) async throws(OrbitleError) -> MiniApp { throw .invalidRequest }
}

/// Первое значение потока, которое подходит под условие (не дольше 3 с).
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

/// Ждёт условие не дольше 3 с.
private func waitUntil(_ condition: @Sendable () -> Bool) async -> Bool {
    for _ in 0..<600 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@Suite("Заглушка режима призрака и приватности")
struct PrivacyControlsTests {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test("Флаги режима лежат в UserDefaults и приходят событием")
    func ghostFlags() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controls = StubPrivacyControls(defaults: defaults, accounts: ServerSettingsFake(AccountSettings(isKnown: true)), ownPresence: { .online })
        #expect(!controls.ghostMode())
        #expect(!controls.hideReadReceipts())
        let changes = controls.ghostChanges()
        await controls.setGhostMode(true)
        await controls.setHideReadReceipts(true)
        #expect(defaults.bool(forKey: StubPrivacyControls.ghostKey))
        #expect(defaults.bool(forKey: StubPrivacyControls.readReceiptsKey))
        let state = await first(changes) { $0.ghostMode && $0.hideReadReceipts }
        #expect(state == GhostState(ghostMode: true, hideReadReceipts: true))
        // Новый объект (перезапуск) читает то же.
        let again = StubPrivacyControls(defaults: defaults, accounts: ServerSettingsFake(.unknown), ownPresence: { .online })
        #expect(again.ghostMode())
        #expect(again.hideReadReceipts())
    }

    @Test("Свой статус — из переданного запроса, ошибка ядра становится OrbitleError")
    func ownPresence() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let seen = Date(timeIntervalSince1970: 1_790_674_800)
        let controls = StubPrivacyControls(defaults: defaults, accounts: ServerSettingsFake(.unknown), ownPresence: { .lastSeen(seen) })
        #expect(try await controls.checkOwnPresence() == .lastSeen(seen))
        let failing = StubPrivacyControls(defaults: defaults, accounts: ServerSettingsFake(.unknown), ownPresence: { throw OrbitleError.networkUnavailable })
        await #expect(throws: OrbitleError.networkUnavailable) { try await failing.checkOwnPresence() }
    }

    @Test("HIDDEN, номер и безопасный режим уходят на сервер")
    func serverKeys() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = ServerSettingsFake(AccountSettings(isKnown: true))
        let controls = StubPrivacyControls(defaults: defaults, accounts: server, ownPresence: { .unknown })
        _ = await first(controls.privacySettings()) { $0.isKnown }
        var result = try await controls.setPrivacy(.hidden, .flag(true))
        #expect(result.onlineHidden)
        result = try await controls.setPrivacy(.phoneNumberPrivacy, .access(.nobody))
        #expect(result.phonePrivacy == .nobody)
        result = try await controls.setPrivacy(.safeMode, .flag(true))
        #expect(result.safeMode)
        #expect(server.calls == ["hidden", "phone", "safe"])
        await #expect(throws: OrbitleError.invalidRequest) { try await controls.setPrivacy(.hidden, .access(.contacts)) }
    }

    @Test("Ключи без сеттера в ядре запоминаются на устройстве поверх сервера")
    func localKeys() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = ServerSettingsFake(AccountSettings(isKnown: true))
        let controls = StubPrivacyControls(defaults: defaults, accounts: server, ownPresence: { .unknown })
        let stream = controls.privacySettings()
        _ = await first(controls.privacySettings()) { $0.isKnown }
        let result = try await controls.setPrivacy(.incomingCall, .access(.contacts))
        #expect(result.incomingCall == .contacts)
        #expect(server.current.incomingCall == .everybody)
        #expect(server.calls.isEmpty)
        #expect(controls.localValue(for: .incomingCall) == .access(.contacts))
        #expect(await first(stream) { $0.incomingCall == .contacts } != nil)
        // Новый конфиг сервера не стирает выбор устройства.
        server.push { $0.onlineHidden = true }
        let shown = await first(stream) { $0.onlineHidden }
        #expect(shown?.incomingCall == .contacts)
        // Сервер догнал выбор — отметка больше не нужна.
        server.push { $0.incomingCall = .contacts }
        #expect(await waitUntil { controls.localValue(for: .incomingCall) == nil })
        #expect(controls.overlay(server.current).incomingCall == .contacts)
    }

    @Test("Безопасный режим и выход из аккаунта стирают выбор устройства")
    func clearLocal() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = ServerSettingsFake(AccountSettings(isKnown: true))
        let controls = StubPrivacyControls(defaults: defaults, accounts: server, ownPresence: { .unknown })
        _ = await first(controls.privacySettings()) { $0.isKnown }
        _ = try await controls.setPrivacy(.contentLevelAccess, .flag(true))
        #expect(controls.localValue(for: .contentLevelAccess) == .flag(true))
        let safe = try await controls.setPrivacy(.safeMode, .flag(true))
        #expect(safe.searchByPhone == .contacts)
        #expect(controls.localValue(for: .contentLevelAccess) == nil)
        _ = try await controls.setPrivacy(.safeMode, .flag(false))
        _ = try await controls.setPrivacy(.chatsInvite, .access(.everybody))
        #expect(controls.localValue(for: .chatsInvite) == .access(.everybody))
        controls.reset()
        #expect(controls.localValue(for: .chatsInvite) == nil)
    }

    @Test("Пока безопасный режим включён на сервере, выбор устройства не показывается")
    func safeModeWins() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ALL", forKey: StubPrivacyControls.localPrefix + "SEARCH_BY_PHONE")
        let controls = StubPrivacyControls(defaults: defaults, accounts: ServerSettingsFake(.unknown), ownPresence: { .unknown })
        let settings = AccountSettings(isKnown: true, safeMode: true, searchByPhone: .contacts)
        #expect(controls.overlay(settings).searchByPhone == .contacts)
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
}
