import Foundation
import OrbitleDomain

/// Режим призрака и приватность, пока в ядре нет своего API (docs/privacy.md, «Заглушка»).
///
/// - Флаги режима призрака и отметок о прочтении лежат в `UserDefaults` и сеть **не меняют**:
///   `PING`, `LOGIN`, `MSG_TYPING` и `CHAT_MARK` уходят как раньше. Гасить их будет ядро.
/// - Свой статус спрашивается тем, что уже есть в ядре (`ownPresence`, обычно `loadPresence`
///   со своим id).
/// - `HIDDEN`, `PHONE_NUMBER_PRIVACY` и `SAFE_MODE` ядро уже меняет: они идут через
///   `AccountRepository` на сервер.
/// - `SEARCH_BY_PHONE`, `INCOMING_CALL`, `CHATS_INVITE` и `CONTENT_LEVEL_ACCESS` ядро только
///   читает. Выбор пользователя запоминается на устройстве поверх значения сервера, на сервер
///   не уходит. Безопасный режим и выход из аккаунта такие отметки стирают.
///
/// Настоящая реализация заменит этот тип одним адаптером поверх моста ядра.
public final class StubPrivacyControls: GhostControls, PrivacyControls, @unchecked Sendable {
    public static let ghostKey = "orbitle.ghost.enabled"
    public static let readReceiptsKey = "orbitle.ghost.hideReadReceipts"
    /// Префикс отметок «выбрано на устройстве» для ключей без сеттера в ядре.
    public static let localPrefix = "orbitle.privacy.local."

    private let defaults: UserDefaults
    private let accounts: any AccountRepository
    private let ownPresence: @Sendable () async throws -> Contact.Presence
    private let lock = NSLock()
    private var ghostWatchers: [UUID: AsyncStream<GhostState>.Continuation] = [:]
    private var privacyWatchers: [UUID: AsyncStream<AccountSettings>.Continuation] = [:]
    /// Последние настройки сервера, без отметок устройства.
    private var server: AccountSettings?
    private var serverWatch: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        accounts: any AccountRepository,
        ownPresence: @escaping @Sendable () async throws -> Contact.Presence
    ) {
        self.defaults = defaults
        self.accounts = accounts
        self.ownPresence = ownPresence
    }

    deinit {
        serverWatch?.cancel()
    }

    // MARK: GhostControls

    public func ghostMode() -> Bool {
        defaults.bool(forKey: Self.ghostKey)
    }

    public func setGhostMode(_ enabled: Bool) async {
        guard enabled != ghostMode() else { return }
        defaults.set(enabled, forKey: Self.ghostKey)
        Log.info(.settings, "Режим призрака: \(enabled ? "включён" : "выключен") (только на устройстве, ядро без режима)")
        publishGhost()
    }

    public func hideReadReceipts() -> Bool {
        defaults.bool(forKey: Self.readReceiptsKey)
    }

    public func setHideReadReceipts(_ hidden: Bool) async {
        guard hidden != hideReadReceipts() else { return }
        defaults.set(hidden, forKey: Self.readReceiptsKey)
        Log.info(.settings, "Отметки о прочтении: \(hidden ? "не отправлять" : "отправлять") (только на устройстве, ядро без режима)")
        publishGhost()
    }

    public func ghostChanges() -> AsyncStream<GhostState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<GhostState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.yield(ghostState)
        lock.withLock { ghostWatchers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.ghostWatchers.removeValue(forKey: id) }
        }
        return stream
    }

    public func checkOwnPresence() async throws(OrbitleError) -> Contact.Presence {
        do {
            return try await ownPresence()
        } catch let error as OrbitleError {
            throw error
        } catch {
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    private var ghostState: GhostState {
        GhostState(ghostMode: ghostMode(), hideReadReceipts: hideReadReceipts())
    }

    private func publishGhost() {
        let state = ghostState
        let watchers = lock.withLock { Array(ghostWatchers.values) }
        for watcher in watchers { watcher.yield(state) }
    }

    // MARK: PrivacyControls

    public func privacySettings() -> AsyncStream<AccountSettings> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AccountSettings>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let known = lock.withLock { () -> AccountSettings? in
            privacyWatchers[id] = continuation
            return server
        }
        if let known { continuation.yield(overlay(known)) }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.privacyWatchers.removeValue(forKey: id) }
        }
        startWatchingServer()
        return stream
    }

    public func setPrivacy(_ key: PrivacyKey, _ value: PrivacyValue) async throws(OrbitleError) -> AccountSettings {
        let result: AccountSettings
        switch (key, value) {
        case (.hidden, .flag(let hidden)):
            result = try await accounts.setOnlineHidden(hidden)
        case (.phoneNumberPrivacy, .access(let access)):
            result = try await accounts.setPhonePrivacy(access)
        case (.safeMode, .flag(let enabled)):
            result = try await accounts.setSafeMode(enabled)
            // Сервер сам переписал ключи безопасного режима: отметки устройства больше не верны.
            clearLocal()
        case (.searchByPhone, .access), (.incomingCall, .access), (.chatsInvite, .access), (.contentLevelAccess, .flag):
            guard let known = lock.withLock({ server }) else { throw .invalidRequest }
            defaults.set(value.wire, forKey: Self.localPrefix + key.rawValue)
            Log.info(.settings, "\(key.rawValue) = \(value.wire): только на устройстве, в ядре нет setPrivacy")
            let shown = overlay(known)
            publishPrivacy(shown)
            return shown
        default:
            throw .invalidRequest
        }
        record(server: result)
        return overlay(result)
    }

    /// Выход из аккаунта: отметки устройства относятся к прежнему аккаунту.
    public func reset() {
        clearLocal()
        lock.withLock { server = nil }
    }

    /// Значение, выбранное на устройстве для ключа без сеттера в ядре. `nil` — нет отметки.
    public func localValue(for key: PrivacyKey) -> PrivacyValue? {
        guard PrivacyKey.guarded.contains(key), let raw = defaults.string(forKey: Self.localPrefix + key.rawValue) else { return nil }
        if key.isFlag {
            switch raw {
            case "true": return .flag(true)
            case "false": return .flag(false)
            default: return nil
            }
        }
        return PrivacyAccess(rawValue: raw).map(PrivacyValue.access)
    }

    /// Настройки сервера с отметками устройства. Пока включён безопасный режим, отметки не действуют.
    func overlay(_ settings: AccountSettings) -> AccountSettings {
        guard !settings.safeMode else { return settings }
        var shown = settings
        for key in PrivacyKey.guarded {
            guard let local = localValue(for: key) else { continue }
            if settings.value(for: key) == local {
                // Сервер уже говорит то же: отметка больше не нужна.
                defaults.removeObject(forKey: Self.localPrefix + key.rawValue)
            } else {
                shown.set(key, local)
            }
        }
        return shown
    }

    private func clearLocal() {
        for key in PrivacyKey.guarded {
            defaults.removeObject(forKey: Self.localPrefix + key.rawValue)
        }
    }

    private func startWatchingServer() {
        let start = lock.withLock { () -> Bool in
            guard serverWatch == nil else { return false }
            serverWatch = Task {}
            return true
        }
        guard start else { return }
        let stream = accounts.settings()
        let task = Task { [weak self] in
            for await value in stream {
                guard let self else { return }
                self.record(server: value)
            }
        }
        lock.withLock { serverWatch = task }
    }

    private func record(server value: AccountSettings) {
        lock.withLock { server = value }
        publishPrivacy(overlay(value))
    }

    private func publishPrivacy(_ settings: AccountSettings) {
        let watchers = lock.withLock { Array(privacyWatchers.values) }
        for watcher in watchers { watcher.yield(settings) }
    }
}

public extension StubPrivacyControls {
    /// Свой статус через ядро как есть: `loadPresence` со своим id (`CONTACT_PRESENCE` 35).
    /// Без id статус неизвестен.
    static func corePresence(
        core: any MaxCore,
        userId: @escaping @Sendable () async -> String
    ) -> @Sendable () async throws -> Contact.Presence {
        {
            let id = await userId()
            guard Int64(id) != nil else { return .unknown }
            let list = try await core.loadPresence(userIds: [id])
            return list.first { $0.userId == id }?.presence ?? .unknown
        }
    }
}

/// «Показывать мой онлайн» в `UserDefaults`. По умолчанию включено.
public final class UserDefaultsSelfCheckStore: SelfCheckStore, @unchecked Sendable {
    public static let key = "orbitle.ghost.showsOwnPresence"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func showsOwnPresence() -> Bool {
        defaults.object(forKey: Self.key) == nil ? true : defaults.bool(forKey: Self.key)
    }

    public func setShowsOwnPresence(_ shows: Bool) {
        defaults.set(shows, forKey: Self.key)
    }
}
