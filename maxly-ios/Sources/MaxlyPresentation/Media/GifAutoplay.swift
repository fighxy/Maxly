import Foundation

/// Настройка «Автовоспроизведение GIF».
public enum GifAutoplayMode: String, CaseIterable, Sendable, Identifiable {
    case always
    case wifiOnly
    case never

    /// Ключ в `UserDefaults`.
    public static let storageKey = "gifAutoplayMode"
    public static let defaultMode: GifAutoplayMode = .always

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .always: "Всегда"
        case .wifiOnly: "Только Wi‑Fi"
        case .never: "Никогда"
        }
    }

    /// Значение из `UserDefaults`; неизвестная строка — значение по умолчанию.
    public init(stored: String?) {
        self = stored.flatMap(GifAutoplayMode.init(rawValue:)) ?? Self.defaultMode
    }
}

/// Какая сеть сейчас у устройства (по `NWPathMonitor`).
public enum NetworkKind: Sendable, Equatable {
    case wifi
    /// Wi‑Fi или кабель без лимита трафика.
    case wired
    case cellular
    /// Сеть с ограниченным трафиком (режим экономии данных) или неизвестная.
    case other
    case offline
}

/// Решает, играть ли гифку в ленте.
public enum GifAutoplayPolicy {
    /// Разрешено ли автовоспроизведение при этой настройке и сети.
    /// «Только Wi‑Fi» не играет в сотовой и в сети с ограниченным трафиком.
    public static func allows(_ mode: GifAutoplayMode, network: NetworkKind, constrained: Bool = false) -> Bool {
        switch mode {
        case .never: return false
        case .always: return true
        case .wifiOnly:
            guard !constrained else { return false }
            return network == .wifi || network == .wired
        }
    }

    /// Играет ли конкретная плитка: автовоспроизведение разрешено, у гифки есть ролик,
    /// и плитка сейчас на экране. Иначе показывается статичная картинка.
    public static func shouldPlay(allowed: Bool, hasVideo: Bool, visible: Bool) -> Bool {
        allowed && hasVideo && visible
    }
}
