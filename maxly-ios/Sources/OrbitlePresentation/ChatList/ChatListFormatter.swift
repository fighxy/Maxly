import Foundation
import OrbitleDomain

/// Что нарисовать в круге аватара.
public struct ChatAvatar: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Буквы на градиенте цвета `colorIndex`.
        case initials(String)
        /// Фото; пока оно грузится или не загрузилось, видны буквы.
        case photo(URL, initials: String)
        /// «Избранное»: закладка на синем круге.
        case savedMessages
        /// Строка архива.
        case archive
    }

    /// Сколько цветов в палитре аватаров. Цвет зависит только от id, поэтому не прыгает.
    public static let paletteSize = 7

    public var kind: Kind
    public var colorIndex: Int

    public init(kind: Kind, colorIndex: Int) {
        self.kind = kind
        self.colorIndex = colorIndex
    }

    /// Устойчивый номер цвета: числовой id берётся по модулю, строковый — по сумме символов.
    /// `hashValue` не годится, он меняется от запуска к запуску.
    public static func colorIndex(for id: String) -> Int {
        if let number = Int64(id) {
            return Int(number.magnitude % UInt64(paletteSize))
        }
        let sum = id.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) & 0x7fff_ffff }
        return sum % paletteSize
    }

    public static func initials(for title: String) -> String {
        let words = title.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).prefix(2)
        let letters = words.compactMap { $0.first(where: { $0.isLetter || $0.isNumber }) }.map(String.init).joined()
        if !letters.isEmpty { return letters.uppercased() }
        return String(title.prefix(1)).uppercased()
    }
}

/// Бейдж справа во второй строке.
public enum ChatBadge: Hashable, Sendable {
    /// Число непрочитанных в компактной записи (`7`, `150`, `68.3K`).
    case count(String)
    /// Чат помечен непрочитанным вручную: точка без числа.
    case dot
}

/// Строка списка чатов, уже в виде текста для экрана.
public struct ChatListItem: Identifiable, Hashable, Sendable {
    /// Как читать нижние строки.
    public enum PreviewStyle: Hashable, Sendable {
        case message
        /// «Черновик:» красным, дальше текст.
        case draft
        /// «печатает…» цветом акцента.
        case typing
        /// В чате нет сообщений.
        case empty
    }

    public let id: String
    public let title: String
    public let type: ChatType
    public let avatar: ChatAvatar
    public let isOnline: Bool
    public let isMuted: Bool
    public let isVerified: Bool
    public let isBot: Bool
    public let isPinned: Bool
    /// Автор над текстом (вторая строка в группах): имя или «Вы». `nil` — текст занимает обе строки.
    public let sender: String?
    /// Текст превью в одну строку (без префикса черновика).
    public let preview: String
    public let previewStyle: PreviewStyle
    /// Подпись вложения («Фотография»), если текст сообщения пуст — она же стоит в `preview`.
    public let media: MessageMediaKind?
    public let thumbnailURL: URL?
    /// Галочки своего последнего сообщения. В каналах и «Избранном» их нет.
    public let delivery: DeliveryState?
    /// Время последней активности: `14:05`, `вчера`, `пн`, `5 мар`, `05.03.2024`.
    public let time: String
    public let unreadCount: Int
    /// Текст бейджа: `nil` без непрочитанных.
    public let unreadBadge: String?
    public let badge: ChatBadge?
    /// Бейдж серый: уведомления выключены.
    public let badgeMuted: Bool
    public let hasMention: Bool
    public let accessibilityLabel: String
    /// Последнее сообщение — пересылка: перед текстом стрелка.
    public var isForwarded = false
    /// Последнее сообщение своё. По нему приватный режим пишет «Вы отправили сообщение».
    public var lastIsOutgoing = false
    /// То же «печатает…», но без имён («2 участника печатают…»): его показывает приватный режим.
    public var anonymousTyping: String?
    /// Диалог с ботом, у которого есть мини-приложение: справа в строке кнопка «Открыть».
    public var hasWebApp = false

    /// Булавка видна у закреплённых, пока нет бейджа.
    public var showsPin: Bool { isPinned && badge == nil && !hasMention }
}

/// Тексты строки списка чатов. Форматы фиксированы и не зависят от языка системы,
/// поэтому одинаковы на устройстве и в тестах.
public struct ChatListFormatter: Sendable {
    public var calendar: Calendar

    static let weekdays = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
    static let months = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    public static let savedMessagesTitle = "Избранное"

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

    /// Строка чата. `typing` — кто печатает прямо сейчас, по времени начала (`TypingFormatter`),
    /// `showDraft` — показывать ли черновик (в открытом чате он и так на экране).
    public func item(for chat: Chat, now: Date, typing: [TypingFormatter.Participant] = [], showDraft: Bool = true) -> ChatListItem {
        let title = title(for: chat)
        let isChannel = chat.type == .channel
        var style = ChatListItem.PreviewStyle.message
        var sender: String?
        var text: String
        var media: MessageMediaKind?
        var thumbnail: URL?
        let draftText = showDraft ? chat.draft.map { Self.singleLine($0.text) } ?? "" : ""
        let typingText = isChannel ? nil : TypingFormatter.text(chatType: chat.type, participants: typing)
        var anonymousTyping: String?
        if let typingText {
            style = .typing
            text = typingText
            let unnamed = typing.map { TypingFormatter.Participant(name: nil, type: $0.type) }
            anonymousTyping = TypingFormatter.text(chatType: chat.type, participants: unnamed)
        } else if !draftText.isEmpty {
            style = .draft
            text = draftText
        } else {
            text = Self.singleLine(chat.preview ?? "")
            media = chat.lastMessage?.media
            thumbnail = chat.lastMessage?.thumbnailURL
            if text.isEmpty {
                if let media {
                    text = Self.mediaLabel(media)
                } else if chat.lastMessageId == nil {
                    style = .empty
                    text = chat.isSavedMessages ? Self.savedMessagesEmpty : "Нет сообщений"
                } else {
                    text = "Вложение"
                }
            }
            sender = senderName(for: chat)
        }
        let delivery = delivery(for: chat, style: style)
        let time = timeLabel(for: style == .draft ? chat.activityDate : chat.updatedAt, now: now)
        let badge: ChatBadge? = if chat.unreadCount > 0 {
            .count(Self.compactCount(chat.unreadCount))
        } else if chat.isMarkedUnread {
            .dot
        } else {
            nil
        }
        let item = ChatListItem(
            id: chat.id,
            title: title,
            type: chat.type,
            avatar: avatar(for: chat, title: title),
            isOnline: chat.type == .private && chat.isOnline && !chat.isBot && !chat.isSavedMessages,
            isMuted: chat.isMuted,
            isVerified: chat.isVerified,
            isBot: chat.isBot,
            isPinned: chat.isPinned,
            sender: sender,
            preview: text,
            previewStyle: style,
            media: style == .message ? media : nil,
            thumbnailURL: style == .message ? thumbnail : nil,
            delivery: delivery,
            time: time,
            unreadCount: max(chat.unreadCount, 0),
            unreadBadge: Self.badge(chat.unreadCount),
            badge: badge,
            badgeMuted: chat.isMuted,
            hasMention: chat.unreadMentions > 0,
            accessibilityLabel: "",
            isForwarded: style == .message && chat.lastMessage?.isForwarded == true,
            lastIsOutgoing: chat.lastMessage?.isOutgoing == true,
            anonymousTyping: anonymousTyping
        )
        var spokenItem = item.withAccessibility(spoken(item, chat: chat))
        spokenItem.hasWebApp = chat.type == .private && chat.hasWebApp && !chat.isSavedMessages
        return spokenItem
    }

    /// Заголовок. У личных чатов ядро может не прислать имя, тогда подставляется тип.
    public func title(for chat: Chat) -> String {
        if chat.isSavedMessages { return Self.savedMessagesTitle }
        let title = chat.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        switch chat.type {
        case .private: return chat.isBot ? "Бот" : "Личный чат"
        case .group: return "Группа"
        case .channel: return "Канал"
        }
    }

    /// Превью в одну строку. Сообщение без текста считается вложением.
    public func preview(for chat: Chat) -> String {
        let text = Self.singleLine(chat.preview ?? "")
        if !text.isEmpty { return text }
        if let media = chat.lastMessage?.media { return Self.mediaLabel(media) }
        guard chat.lastMessageId == nil else { return "Вложение" }
        return chat.isSavedMessages ? Self.savedMessagesEmpty : "Нет сообщений"
    }

    /// Превью пустого «Избранного», как в Max.
    public static let savedMessagesEmpty = "Сохраните что-нибудь"

    /// Автор над текстом. В группах — «Вы» или имя, если оно известно. В личных чатах,
    /// каналах и «Избранном» автор очевиден, строка отдаётся тексту.
    public func senderName(for chat: Chat) -> String? {
        guard chat.type == .group, let last = chat.lastMessage else { return nil }
        if last.isOutgoing { return "Вы" }
        let name = last.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    public func avatar(for chat: Chat, title: String) -> ChatAvatar {
        let color = ChatAvatar.colorIndex(for: chat.id)
        if chat.isSavedMessages { return ChatAvatar(kind: .savedMessages, colorIndex: color) }
        let initials = ChatAvatar.initials(for: title)
        if let url = chat.avatarURL { return ChatAvatar(kind: .photo(url, initials: initials), colorIndex: color) }
        return ChatAvatar(kind: .initials(initials), colorIndex: color)
    }

    private func delivery(for chat: Chat, style: ChatListItem.PreviewStyle) -> DeliveryState? {
        guard style == .message, chat.type != .channel, !chat.isSavedMessages,
              let last = chat.lastMessage, last.isOutgoing else { return nil }
        return last.delivery ?? .sent
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

    /// Полное число для VoiceOver и старых мест. `nil` без непрочитанных.
    public static func badge(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return compactCount(count)
    }

    /// Короткая запись счётчика: до тысячи как есть, дальше `1K`, `68.3K`, `2.5M`.
    /// Десятые отбрасываются, а не округляются: 999 999 не превращается в «1000K».
    public static func compactCount(_ count: Int) -> String {
        let value = max(count, 0)
        func scaled(_ divisor: Int, _ suffix: String) -> String {
            let tenths = value / (divisor / 10)
            let whole = tenths / 10
            let fraction = tenths % 10
            return fraction == 0 || whole >= 100 ? "\(whole)\(suffix)" : "\(whole).\(fraction)\(suffix)"
        }
        switch value {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return scaled(1_000, "K")
        default: return scaled(1_000_000, "M")
        }
    }

    public static func mediaLabel(_ kind: MessageMediaKind) -> String {
        switch kind {
        case .photo: "Фотография"
        case .video: "Видео"
        case .voice: "Голосовое сообщение"
        case .videoMessage: "Видеосообщение"
        case .audio: "Аудио"
        case .file: "Файл"
        case .sticker: "Стикер"
        case .gif: "GIF"
        case .location: "Геопозиция"
        case .contact: "Контакт"
        case .poll: "Опрос"
        case .call: CallBubbleText.preview(isGroup: false)
        case .groupCall: CallBubbleText.preview(isGroup: true)
        }
    }

    /// «печатает…» в личном чате, «2 участника печатают…» в группе — когда имён нет.
    /// Имена и тип действия учитывает `TypingFormatter`.
    public static func typingText(count: Int, type: ChatType) -> String {
        guard count > 1, type == .group else { return "печатает…" }
        return TypingFormatter.countText(count, kind: .text) + "…"
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

    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func spoken(_ item: ChatListItem, chat: Chat) -> String {
        var parts = [item.title]
        if item.isVerified { parts.append("подтверждённый") }
        if item.isBot { parts.append("бот") } else if item.type == .channel { parts.append("канал") }
        if item.isOnline { parts.append("в сети") }
        if item.isPinned { parts.append("закреплён") }
        if item.isMuted { parts.append("без звука") }
        switch item.previewStyle {
        case .draft: parts.append("черновик: \(item.preview)")
        case .typing, .empty: parts.append(item.preview)
        case .message:
            if let sender = item.sender {
                parts.append("\(sender): \(item.preview)")
            } else {
                parts.append(item.preview)
            }
        }
        if !item.time.isEmpty { parts.append(item.time) }
        switch item.delivery {
        case .sending: parts.append("отправляется")
        case .sent: parts.append("доставлено")
        case .read: parts.append("прочитано")
        case .failed: parts.append("не отправлено")
        case nil: break
        }
        if chat.unreadCount > 0 {
            parts.append(Self.unreadPhrase(chat.unreadCount))
        } else if chat.isMarkedUnread {
            parts.append("помечен непрочитанным")
        }
        if item.hasMention { parts.append("есть упоминание") }
        return parts.joined(separator: ", ")
    }
}

extension ChatListItem {
    func withAccessibility(_ label: String) -> ChatListItem {
        ChatListItem(
            id: id, title: title, type: type, avatar: avatar, isOnline: isOnline, isMuted: isMuted,
            isVerified: isVerified, isBot: isBot, isPinned: isPinned, sender: sender, preview: preview,
            previewStyle: previewStyle, media: media, thumbnailURL: thumbnailURL, delivery: delivery,
            time: time, unreadCount: unreadCount, unreadBadge: unreadBadge, badge: badge,
            badgeMuted: badgeMuted, hasMention: hasMention, accessibilityLabel: label,
            isForwarded: isForwarded, lastIsOutgoing: lastIsOutgoing, anonymousTyping: anonymousTyping,
            hasWebApp: hasWebApp
        )
    }
}
