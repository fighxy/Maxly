import Foundation
import MaxlyDomain

/// Звуки в открытом приложении: своё сообщение ушло, пришло чужое.
///
/// Свёрнутое приложение звучит системным звуком уведомления (`MessageNotificationRules`), а
/// открытое — своими короткими звуками. Оба по умолчанию включены и выключаются по отдельности
/// в «Уведомления и звук». Чат «без звука» молчит, во время звонка звуков нет. Пачка сообщений
/// (например, после переподключения) звучит один раз: тот же звук не чаще `SoundThrottle.interval`.
public enum InAppSound: String, CaseIterable, Sendable {
    /// Нажали «отправить»: текст, вложение, голосовое, стикер, опрос. Правка не звучит.
    case sent = "message_sent"
    /// Пришло чужое сообщение, пока приложение открыто.
    case incoming = "message_incoming"
}

public enum InAppSoundSettings {
    /// Ключи в `UserDefaults`; нет значения — звук включён.
    public static let sentKey = "maxly.sound.sent"
    public static let incomingKey = "maxly.sound.incoming"

    public static func key(for sound: InAppSound) -> String {
        switch sound {
        case .sent: sentKey
        case .incoming: incomingKey
        }
    }

    public static func isEnabled(_ sound: InAppSound, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key(for: sound)) as? Bool ?? true
    }
}

public enum InAppSoundRules {
    /// Входящее звучит в открытом приложении и не в чате «без звука». В фоне звучит уведомление.
    public static func playsIncoming(_ notice: IncomingMessageNotice, appActive: Bool) -> Bool {
        appActive && !notice.isMuted
    }
}

/// Один и тот же звук не чаще раза в `interval` секунд: десяток сообщений подряд — один сигнал.
public struct SoundThrottle: Sendable {
    public static let interval: TimeInterval = 0.8
    private var last: [InAppSound: TimeInterval] = [:]

    public init() {}

    /// Можно ли сыграть [sound] в момент [now] (монотонные секунды); если да — момент запоминается.
    public mutating func allows(_ sound: InAppSound, at now: TimeInterval) -> Bool {
        if let previous = last[sound], now - previous < Self.interval { return false }
        last[sound] = now
        return true
    }
}
