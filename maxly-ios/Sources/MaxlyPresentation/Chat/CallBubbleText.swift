import Foundation
import MaxlyDomain

/// Подписи звонка в ленте: заголовок, длительность, значок и текст для VoiceOver.
///
/// Исход берётся из `CallContent.outcome(outgoing:)`, поэтому пузырь и вкладка «Звонки»
/// называют один звонок одинаково.
public enum CallBubbleText: Sendable {
    /// «Исходящий звонок», «Пропущенный видеозвонок», «Групповой звонок»…
    public static func title(_ call: CallContent, outgoing: Bool) -> String {
        let noun = call.isVideo ? "видеозвонок" : "звонок"
        if call.isGroup { return "Групповой \(noun)" }
        let base: String
        switch call.outcome(outgoing: outgoing) {
        case .answered: base = outgoing ? "Исходящий" : "Входящий"
        case .missed: base = "Пропущенный"
        case .cancelled: base = "Отменённый"
        case .declined: base = "Отклонённый"
        }
        return "\(base) \(noun)"
    }

    /// Длительность состоявшегося разговора: «0:42», «12:05», «1:02:03». `nil`, если
    /// разговора не было.
    public static func duration(_ call: CallContent) -> String? {
        guard call.isConnected else { return nil }
        return clock(ms: call.durationMs)
    }

    /// Время из миллисекунд. Час и больше — с часами.
    public static func clock(ms: Int64) -> String {
        let seconds = Int(max(0, ms) / 1000)
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds % 60) }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }

    /// Выделять ли звонок красным: пропущенный входящий, как во вкладке «Звонки».
    public static func isAlert(_ call: CallContent, outgoing: Bool) -> Bool {
        call.isMissed(outgoing: outgoing)
    }

    /// SF Symbol для круга слева.
    public static func symbol(_ call: CallContent, outgoing: Bool) -> String {
        if call.isGroup { return call.isVideo ? "video.fill" : "phone.fill" }
        switch call.outcome(outgoing: outgoing) {
        case .answered:
            if call.isVideo { return "video.fill" }
            return outgoing ? "phone.arrow.up.right.fill" : "phone.arrow.down.left.fill"
        case .missed, .cancelled, .declined:
            return call.isVideo ? "video.slash.fill" : "phone.down.fill"
        }
    }

    /// Строка для VoiceOver: заголовок, длительность и время сообщения.
    public static func accessibility(_ call: CallContent, outgoing: Bool, time: String) -> String {
        var parts = [title(call, outgoing: outgoing)]
        if let duration = duration(call) { parts.append("длительность \(duration)") }
        if !time.isEmpty { parts.append(time) }
        return parts.joined(separator: ", ")
    }

    /// Строка списка чатов и цитата: «Звонок» или «Групповой звонок». Без направления и
    /// исхода, как и в других клиентах MAX.
    public static func preview(isGroup: Bool) -> String {
        isGroup ? "Групповой звонок" : "Звонок"
    }
}
