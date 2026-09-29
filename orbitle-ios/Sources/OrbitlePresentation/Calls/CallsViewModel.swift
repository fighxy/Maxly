import Foundation
import Observation
import OrbitleDomain

/// Строка истории: один звонок или несколько подряд с тем же собеседником.
public struct CallRow: Identifiable, Hashable, Sendable {
    /// Id первого (самого свежего) звонка группы.
    public let id: String
    public let callIds: [String]
    /// Имя со счётчиком: «Иван (2)».
    public let title: String
    public let name: String
    public let peerId: String
    public let avatarURL: URL?
    public let isGroup: Bool
    public let isMissed: Bool
    public let status: String
    /// SF Symbol направления.
    public let directionSymbol: String
    public let dateText: String
    public let chatId: String?
    public let accessibilityLabel: String
}

/// Вкладка «Звонки»: переключатель «Все» / «Пропущенные», история с группировкой.
@MainActor
@Observable
public final class CallsViewModel {
    public enum Filter: String, CaseIterable, Identifiable, Hashable, Sendable {
        case all
        case missed

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: "Все"
            case .missed: "Пропущенные"
            }
        }
    }

    public enum State: Equatable, Sendable {
        case loading
        /// Источник не умеет отдавать историю.
        case unavailable
        case empty
        case ready
    }

    public var filter: Filter = .all {
        didSet { if filter != oldValue { rebuild() } }
    }

    public private(set) var state: State = .loading
    public private(set) var rows: [CallRow] = []
    public private(set) var errorMessage: String?
    /// Ссылка на только что созданный звонок: экран предлагает ею поделиться.
    public var createdLink: URL?

    public var canCreateCall: Bool { repository.capabilities.contains(.createLink) }
    public var canJoin: Bool { repository.capabilities.contains(.join) }
    /// Бейдж вкладки: пропущенные звонки новее последнего просмотра вкладки, без удалённых
    /// и скрытых. Хранимое свойство, чтобы панель вкладок перерисовывалась при его смене.
    public private(set) var unseenMissedCount = 0

    @ObservationIgnored private let repository: any CallHistoryRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var records: [CallRecord] = []
    /// Удалённые на экране, пока сервер не подтвердил (или навсегда, если сервер не умеет).
    /// Хранятся в `marks`, чтобы скрытые звонки не возвращались после перезапуска.
    @ObservationIgnored private var hidden: Set<String>
    @ObservationIgnored private let marks: any CallHistoryMarks
    /// Вкладка «Звонки» на экране: всё, что пришло, пока она видна, считается просмотренным.
    @ObservationIgnored private var isVisible = false

    public init(
        calls: any CallHistoryRepository,
        marks: any CallHistoryMarks = InMemoryCallHistoryMarks(),
        calendar: Calendar = ChatListFormatter.defaultCalendar(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.repository = calls
        self.marks = marks
        self.hidden = marks.hiddenIds
        self.calendar = calendar
        self.now = now
    }

    public func activate() {
        guard watch == nil else { return }
        guard repository.capabilities.contains(.history) else {
            state = .unavailable
            return
        }
        // Первый запуск у аккаунта: прежняя история считается просмотренной, бейдж —
        // только для звонков, пропущенных после этого.
        if marks.lastSeen == nil { marks.lastSeen = now() }
        let stream = repository.calls()
        watch = Task { [weak self] in
            for await list in stream {
                guard let self else { return }
                self.receive(list)
            }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
        isVisible = false
    }

    /// Вкладка «Звонки» открылась: пропущенные просмотрены, история грузится заново.
    public func appeared() async {
        isVisible = true
        markSeen()
        await repository.refresh()
    }

    /// Вкладка ушла с экрана: новые пропущенные снова попадают в бейдж.
    public func disappeared() {
        isVisible = false
    }

    /// Загрузить историю заново (например, приложение вернулось на передний план).
    public func refresh() async {
        await repository.refresh()
    }

    /// Удаляет строку со всеми звонками группы. Без поддержки сервера запись
    /// скрывается только на устройстве.
    public func delete(_ row: CallRow) async {
        let ids = Set(row.callIds)
        hidden.formUnion(ids)
        marks.hiddenIds = hidden
        rebuild()
        guard repository.capabilities.contains(.delete) else { return }
        do {
            try await repository.delete(ids: row.callIds)
        } catch {
            hidden.subtract(ids)
            marks.hiddenIds = hidden
            errorMessage = error.userMessage
            rebuild()
        }
    }

    public func createCallLink() async {
        do {
            createdLink = try await repository.createCallLink()
            errorMessage = nil
        } catch {
            errorMessage = error.userMessage
        }
    }

    public func join(link: String) async {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await repository.join(link: trimmed)
            errorMessage = nil
        } catch {
            errorMessage = error.userMessage
        }
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: Внутреннее

    private var visible: [CallRecord] {
        records.filter { !hidden.contains($0.id) }
    }

    private func receive(_ list: [CallRecord]) {
        records = list
        // Звонки, которых больше нет на сервере, скрывать уже незачем. Пустой список может
        // быть ошибкой загрузки, по нему скрытые не чистятся.
        if !list.isEmpty {
            let pruned = hidden.intersection(list.map(\.id))
            if pruned != hidden {
                hidden = pruned
                marks.hiddenIds = pruned
            }
        }
        rebuild()
    }

    /// Всё видимое сейчас просмотрено: отметка сдвигается до самого нового звонка.
    private func markSeen() {
        if let newest = visible.map(\.date).max(), newest > (marks.lastSeen ?? .distantPast) {
            marks.lastSeen = newest
        }
        updateBadge()
    }

    private func updateBadge() {
        let seen = marks.lastSeen ?? .distantPast
        let count = visible.filter { $0.isMissed && $0.date > seen }.count
        if count != unseenMissedCount { unseenMissedCount = count }
    }

    private func rebuild() {
        guard repository.capabilities.contains(.history) else { return }
        if isVisible { markSeen() } else { updateBadge() }
        let list = visible
            .filter { filter == .all || $0.isMissed }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
        rows = group(list).map(row(for:))
        state = rows.isEmpty ? .empty : .ready
    }

    /// Соседние звонки одного собеседника одного вида и одного дня — одна строка.
    private func group(_ list: [CallRecord]) -> [[CallRecord]] {
        var groups: [[CallRecord]] = []
        for record in list {
            if let last = groups.last?.last,
               last.peerId == record.peerId,
               Self.kind(of: last) == Self.kind(of: record),
               calendar.isDate(last.date, inSameDayAs: record.date) {
                groups[groups.count - 1].append(record)
            } else {
                groups.append([record])
            }
        }
        return groups
    }

    private func row(for group: [CallRecord]) -> CallRow {
        let first = group[0]
        let name = first.title.isEmpty ? (first.isGroup ? "Групповой звонок" : "Без имени") : first.title
        let title = group.count > 1 ? "\(name) (\(group.count))" : name
        let kind = Self.kind(of: first)
        let status = Self.status(kind, isVideo: first.isVideo)
        let date = dateText(first.date)
        return CallRow(
            id: first.id,
            callIds: group.map(\.id),
            title: title,
            name: name,
            peerId: first.peerId,
            avatarURL: first.avatarURL,
            isGroup: first.isGroup,
            isMissed: kind == .missed,
            status: status,
            directionSymbol: Self.symbol(kind),
            dateText: date,
            chatId: first.chatId,
            accessibilityLabel: [title, status, date].joined(separator: ", ")
        )
    }

    enum Kind: Hashable {
        case outgoing, incoming, missed, cancelled, declined
    }

    static func kind(of record: CallRecord) -> Kind {
        switch (record.direction, record.outcome) {
        case (.outgoing, .answered): .outgoing
        case (.incoming, .answered): .incoming
        case (.incoming, .missed): .missed
        case (.incoming, .declined): .declined
        case (.outgoing, _), (.incoming, .cancelled): .cancelled
        }
    }

    static func status(_ kind: Kind, isVideo: Bool) -> String {
        let base: String
        switch kind {
        case .outgoing: base = "Исходящий"
        case .incoming: base = "Входящий"
        case .missed: base = "Пропущенный"
        case .cancelled: base = "Отменённый"
        case .declined: base = "Отклонённый"
        }
        return isVideo ? "\(base) видеозвонок" : base
    }

    static func symbol(_ kind: Kind) -> String {
        switch kind {
        case .outgoing: "phone.arrow.up.right"
        case .incoming, .missed: "phone.arrow.down.left"
        case .cancelled, .declined: "phone.down"
        }
    }

    /// Сегодня — время, в этом году — «28 сен», раньше — полная дата.
    func dateText(_ date: Date) -> String {
        let current = now()
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if calendar.isDate(date, inSameDayAs: current) {
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        let day = parts.day ?? 1
        let month = parts.month ?? 1
        if parts.year == calendar.component(.year, from: current) {
            return "\(day) \(ChatListFormatter.months[(month - 1) % 12])"
        }
        return String(format: "%02d.%02d.%04d", day, month, parts.year ?? 0)
    }
}
