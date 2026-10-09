import Foundation
import Observation
import MaxlyDomain

/// Экран «Сведения» одного сообщения: когда отправлено и изменено, откуда переслано, а в
/// личном чате и группе — кто его прочитал (docs/readers.md).
@MainActor
@Observable
public final class MessageInfoViewModel: Identifiable {
    /// Раздел «Кем прочитано».
    public enum ReadersState: Equatable, Sendable {
        /// Раздела нет: не группа, большая группа или сообщение ещё не на сервере.
        case hidden
        case loading
        case loaded([MessageReader])
        case failed(String)
    }

    /// Строка «Изменено» без времени: сервер не прислал `updateTime`, но правка была.
    public static let editedWithoutTime = "Изменено"
    public static let emptyReaders = "Пока никто не прочитал"
    public static let readersTitle = "Кем прочитано"

    public nonisolated let id: String
    public let message: Message
    public let chatType: ChatType
    public let isOwn: Bool
    public private(set) var readers: ReadersState = .hidden

    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(
        message: Message,
        chatType: ChatType,
        isOwn: Bool,
        repository: any MessageRepository,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.id = message.id
        self.message = message
        self.chatType = chatType
        self.isOwn = isOwn
        self.repository = repository
        self.now = now
        self.calendar = calendar
    }

    /// Сведения есть у сообщений, принятых сервером: не у отправляемых, неудачных и отложенных.
    public static func isAvailable(for message: Message) -> Bool {
        message.status == .sent && message.serverId.flatMap { Int64($0) } != nil && message.content.pin == nil
    }

    private var state: MessageReaders.MessageState {
        switch message.status {
        case .sent: message.serverId.flatMap { Int64($0) } != nil ? .sent : .sending
        case .sending: .sending
        case .failed: .failed
        }
    }

    // MARK: Строки

    public var sentText: String { Self.moment(message.timestamp, now: now(), calendar: calendar) }

    /// Время правки, `editedWithoutTime`, если время неизвестно, и `nil` без правки.
    public var editedText: String? {
        if let editedAt = message.editedAt {
            return Self.moment(editedAt, now: now(), calendar: calendar)
        }
        return message.content.edited == true ? Self.editedWithoutTime : nil
    }

    /// Автор пересланного оригинала. `nil` — не пересылка.
    public var forwardedFrom: String? {
        guard let forward = message.content.forward else { return nil }
        let name = forward.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Неизвестный отправитель" : name
    }

    /// «Прочитано» или «Доставлено» — только своё сообщение в личном чате (не «Избранное»).
    public var readStatus: PrivateReadStatus? {
        guard chatType == .private else { return nil }
        let time = message.timestamp.unixMillisecondsValue
        return MessageReaders.privateStatus(
            chatId: message.chatId,
            chatType: "DIALOG",
            isOwn: isOwn,
            messageState: state,
            messageTime: time,
            peerMark: message.isRead ? time : 0
        )
    }

    // MARK: Загрузка

    /// Раздел «Кем прочитано» только в группе, где он есть по данным ядра.
    public func load() async {
        guard chatType == .group, state == .sent else {
            readers = .hidden
            return
        }
        guard await repository.readersAvailable(chatId: message.chatId) else {
            readers = .hidden
            return
        }
        readers = .loading
        do {
            readers = .loaded(try await repository.messageReaders(messageId: message.id))
        } catch {
            guard error != .cancelled else { return }
            readers = .failed("Не удалось загрузить список")
        }
    }

    /// Имя строки: без профиля — «Пользователь» и id.
    public static func name(of reader: MessageReader) -> String {
        let name = reader.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Пользователь \(reader.userId)" : name
    }

    /// Подпись под именем: когда дочитал до этого места. Отметка — время последнего прочитанного
    /// сообщения, поэтому это «прочитано до», а не момент чтения. `nil` — только реакция.
    public func readerDetail(_ reader: MessageReader) -> String? {
        guard let mark = reader.readMark, mark > 0 else { return nil }
        return "Прочитано · \(Self.moment(Date(timeIntervalSince1970: TimeInterval(mark) / 1000), now: now(), calendar: calendar))"
    }

    /// «сегодня в 14:05», «вчера в 14:05», «12 марта в 14:05», в другом году — «12 марта 2025 в 14:05».
    public static func moment(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return "сегодня в \(time)"
        case 1: return "вчера в \(time)"
        default:
            let month = monthsGenitive[((parts.month ?? 1) - 1 + 12) % 12]
            let sameYear = parts.year == calendar.component(.year, from: now)
            return sameYear ? "\(parts.day ?? 1) \(month) в \(time)" : "\(parts.day ?? 1) \(month) \(parts.year ?? 0) в \(time)"
        }
    }

    private static let monthsGenitive = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря",
    ]
}

private extension Date {
    var unixMillisecondsValue: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}
