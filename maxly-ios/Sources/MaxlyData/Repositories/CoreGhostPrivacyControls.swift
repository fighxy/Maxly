import Foundation
import MaxlyDomain

/// Режим призрака и приватность MAX поверх моста ядра (docs/privacy.md).
///
/// Единственный источник правды — ядро и сервер: адаптер переводит вызовы экранов в вызовы
/// моста и события моста в потоки экранов, ничего не хранит и сеть не трогает.
public final class CoreGhostPrivacyControls: GhostControls, PrivacyControls, Sendable {
    private let core: any GhostPrivacyCore

    public init(core: any GhostPrivacyCore) {
        self.core = core
    }

    // MARK: GhostControls

    public func ghostMode() -> Bool {
        core.ghostMode()
    }

    public func setGhostMode(_ enabled: Bool) async {
        await core.setGhostMode(enabled)
        Log.info(.settings, "Режим призрака: \(enabled ? "включён" : "выключен")")
    }

    public func hideReadReceipts() -> Bool {
        core.hideReadReceipts()
    }

    public func setHideReadReceipts(_ hidden: Bool) async {
        await core.setHideReadReceipts(hidden)
        Log.info(.settings, "Отметки о прочтении: \(hidden ? "не отправлять" : "отправлять")")
    }

    /// Флаги сразу, затем по событиям `ghostMode` / `hideReadReceipts` (`text` — `on` / `off`).
    /// Подписка на события открывается раньше чтения флагов: смена между ними не теряется.
    public func ghostChanges() -> AsyncStream<GhostState> {
        let core = core
        let events = core.events()
        let initial = GhostState(ghostMode: core.ghostMode(), hideReadReceipts: core.hideReadReceipts())
        let (stream, continuation) = AsyncStream<GhostState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.yield(initial)
        let task = Task {
            var state = initial
            for await event in events {
                guard let next = Self.state(after: event, from: state, core: core), next != state else { continue }
                state = next
                continuation.yield(next)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Флаги после события. `nil` — событие не про них. Незнакомый `text` — флаг из ядра.
    static func state(after event: CoreEvent, from state: GhostState, core: any GhostPrivacyCore) -> GhostState? {
        let on: Bool? = switch event.text.lowercased() {
        case "on": true
        case "off": false
        default: nil
        }
        var next = state
        switch event.kind {
        case .ghostMode: next.ghostMode = on ?? core.ghostMode()
        case .hideReadReceipts: next.hideReadReceipts = on ?? core.hideReadReceipts()
        default: return nil
        }
        return next
    }

    public func checkOwnPresence() async throws(MaxlyError) -> Contact.Presence {
        // До входа мост ждал бы сессию или ответил ошибкой: статус просто неизвестен.
        guard await !core.currentUserId().isEmpty else { return .unknown }
        do {
            // Сервер промолчал о себе: статус неизвестен, строка в шапке не показывается.
            return try await core.checkOwnPresence()?.presence ?? .unknown
        } catch {
            throw CoreMapping.apiError(error).maxlyError
        }
    }

    public func localReadMark(chatId: String) -> Int64 {
        core.localReadMarkOf(chatId: chatId)
    }

    // MARK: PrivacyControls

    public func privacySettings() -> AsyncStream<AccountSettings> {
        core.accountSettings()
    }

    /// Доступ — `setPrivacy` строкой `ALL` / `CONTACTS` / `NOBODY`, флаг — `setPrivacyFlag`.
    /// Значение не того вида и `NOBODY` вне `PHONE_NUMBER_PRIVACY` ядру не отправляются: ядро
    /// их отклоняет.
    public func setPrivacy(_ key: PrivacyKey, _ value: PrivacyValue) async throws(MaxlyError) -> AccountSettings {
        do {
            let result: AccountSettings
            switch value {
            case .access(let access) where !key.isFlag && Self.accepts(access, for: key):
                result = try await core.setPrivacy(key: key.rawValue, value: access.rawValue)
            case .flag(let enabled) where key.isFlag:
                result = try await core.setPrivacyFlag(key: key.rawValue, enabled: enabled)
            default:
                throw MaxlyError.invalidRequest
            }
            Log.info(.settings, "\(key.rawValue) = \(value.wire)")
            return result
        } catch let error as MaxlyError {
            throw error
        } catch {
            throw CoreMapping.apiError(error).maxlyError
        }
    }

    /// Какие значения доступа ядро принимает для ключа (`PrivacyConfig.payload`).
    static func accepts(_ access: PrivacyAccess, for key: PrivacyKey) -> Bool {
        access != .nobody || key == .phoneNumberPrivacy
    }

    public func isPrivacyReadOnly(_ key: PrivacyKey) -> Bool {
        core.isPrivacyReadOnly(key: key.rawValue)
    }
}
