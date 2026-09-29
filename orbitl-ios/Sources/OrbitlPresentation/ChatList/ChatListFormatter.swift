import Foundation
import OrbitlDomain

/// Строка списка чатов, уже в виде текста для экрана.
public struct ChatListItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let preview: String
    /// Время последней активности: `14:05`, `вчера`, `пн`, `5 мар`, `05.03.2024`.
    public let time: String
    public let unreadCount: Int
    /// Текст бейджа: `nil` без непрочитанных, `99+` для больших чисел.
    public let unreadBadge: String?
    public let accessibilityLabel: String
}

/// Тексты строки списка чатов. Форматы фиксированы и не зависят от языка системы,
/// поэтому одинаковы на устройстве и в тестах.
public struct ChatListFormatter: Sendable {
    public var calendar: Calendar

    static let weekdays = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
    static let months = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    public init(calendar: Calendar = ChatListFormatter.defaultCalendar()) {
        self.calendar = calendar
    }

    public static func defaultCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    public func item(for chat: Chat, now: Date) -> ChatListItem {
        let title = title(for: chat)
        let preview = preview(for: chat)
        let time = timeLabel(for: chat.updatedAt, now: now)
        var spoken = [title, preview]
        if !time.isEmpty { spoken.append(time) }
        if chat.unreadCount > 0 { spoken.append(Self.unreadPhrase(chat.unreadCount)) }
        return ChatListItem(
            id: chat.id,
            title: title,
            preview: preview,
            time: time,
            unreadCount: max(chat.unreadCount, 0),
            unreadBadge: Self.badge(chat.unreadCount),
            accessibilityLabel: spoken.joined(separator: ", ")
        )
    }

    /// Заголовок. У личных чатов ядро может не прислать имя, тогда подставляется тип.
    public func title(for chat: Chat) -> String {
        let title = chat.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        switch chat.type {
        case .private: return "Личный чат"
        case .group: return "Группа"
        case .channel: return "Канал"
        }
    }

    /// Превью в одну строку. Сообщение без текста считается вложением.
    public func preview(for chat: Chat) -> String {
        let text = (chat.preview ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !text.isEmpty { return text }
        return chat.lastMessageId == nil ? "Нет сообщений" : "Вложение"
    }

    /// Время для строки: сегодня часы, вчера «вчера», на этой неделе день недели,
    /// в этом году число и месяц, раньше полная дата. Пустая строка, если времени нет.
    public func timeLabel(for date: Date, now: Date) -> String {
        guard date.timeIntervalSince1970 > 0 else { return "" }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let year = parts.year ?? 0
        let month = parts.month ?? 1
        let dayOfMonth = parts.day ?? 1
        switch days {
        case 0:
            return String(format: "%02d:%02d", hour, minute)
        case 1:
            return "вчера"
        case 2...6:
            return Self.weekdays[((parts.weekday ?? 1) - 1) % 7]
        default:
            if days > 0, year == calendar.component(.year, from: now) {
                return "\(dayOfMonth) \(Self.months[(month - 1) % 12])"
            }
            // Прошлые годы и время из будущего (часы сервера и телефона расходятся).
            return String(format: "%02d.%02d.%04d", dayOfMonth, month, year)
        }
    }

    public static func badge(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }

    /// «1 непрочитанное сообщение», «3 непрочитанных сообщения», «5 непрочитанных сообщений».
    public static func unreadPhrase(_ count: Int) -> String {
        let tens = count % 100
        let ones = count % 10
        if (11...14).contains(tens) { return "\(count) непрочитанных сообщений" }
        switch ones {
        case 1: return "\(count) непрочитанное сообщение"
        case 2...4: return "\(count) непрочитанных сообщения"
        default: return "\(count) непрочитанных сообщений"
        }
    }
}
