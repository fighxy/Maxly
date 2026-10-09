import Foundation
import Observation
import MaxlyDomain

/// Что сейчас показывают экраны: всё, заглушки или размытие.
public enum PrivateModeDisplay: Hashable, Sendable {
    case visible
    case placeholder
    case blur

    public init(_ preferences: PrivateModePreferences) {
        guard preferences.isEnabled else {
            self = .visible
            return
        }
        switch preferences.style {
        case .placeholder: self = .placeholder
        case .blur: self = .blur
        }
    }

    /// Данные спрятаны: заглушками или размытием.
    public var isMasked: Bool { self != .visible }
}

/// Приватный режим на устройстве. Корень приложения кладёт `display` в окружение экранов,
/// «Безопасность», кнопка в списке чатов и плашка в чате переключают его.
@MainActor
@Observable
public final class PrivateModeSettings {
    public private(set) var preferences: PrivateModePreferences

    @ObservationIgnored private let store: any PrivateModeStore

    public init(store: any PrivateModeStore) {
        self.store = store
        preferences = store.load()
    }

    public var isEnabled: Bool { preferences.isEnabled }
    public var style: PrivateModeStyle { preferences.style }
    public var showsQuickToggle: Bool { preferences.showsQuickToggle }
    public var display: PrivateModeDisplay { PrivateModeDisplay(preferences) }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != preferences.isEnabled else { return }
        preferences.isEnabled = enabled
        save()
        Log.info(.settings, "Приватный режим: \(enabled ? "включён" : "выключен")")
    }

    public func toggle() {
        setEnabled(!preferences.isEnabled)
    }

    public func setStyle(_ style: PrivateModeStyle) {
        guard style != preferences.style else { return }
        preferences.style = style
        save()
        Log.info(.settings, "Приватный режим: вид \(style.rawValue)")
    }

    public func setShowsQuickToggle(_ shows: Bool) {
        guard shows != preferences.showsQuickToggle else { return }
        preferences.showsQuickToggle = shows
        save()
    }

    private func save() {
        store.save(preferences)
    }
}

/// Сообщения, которые пользователь открыл касанием в приватном режиме. Открытое снова
/// прячется через `duration`, при уходе с экрана или сворачивании приложения — сразу (`hideAll`).
@MainActor
@Observable
public final class PrivateModeReveal {
    public static let defaultDuration: Duration = .seconds(15)

    public private(set) var revealed: Set<String> = []

    @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        duration: Duration = PrivateModeReveal.defaultDuration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.duration = duration
        self.sleep = sleep
    }

    public func isRevealed(_ id: String) -> Bool {
        revealed.contains(id)
    }

    /// Касание: закрытое открывается, открытое прячется.
    public func toggle(_ id: String) {
        if revealed.contains(id) {
            hide(id)
        } else {
            reveal(id)
        }
    }

    /// Открывает сообщение. Повторное открытие начинает отсчёт заново.
    public func reveal(_ id: String) {
        revealed.insert(id)
        timers[id]?.cancel()
        let sleep = sleep
        let duration = duration
        timers[id] = Task { [weak self] in
            do {
                try await sleep(duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.hide(id)
        }
    }

    public func hide(_ id: String) {
        revealed.remove(id)
        timers.removeValue(forKey: id)?.cancel()
    }

    public func hideAll() {
        guard !revealed.isEmpty || !timers.isEmpty else { return }
        revealed.removeAll()
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
    }
}
