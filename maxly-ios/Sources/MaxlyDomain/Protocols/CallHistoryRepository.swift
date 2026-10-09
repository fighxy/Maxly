import Foundation

/// Что умеет источник звонков.
public struct CallCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// История звонков аккаунта.
    public static let history = CallCapabilities(rawValue: 1 << 0)
    /// Удаление записей на сервере. Без него запись скрывается только на устройстве.
    public static let delete = CallCapabilities(rawValue: 1 << 1)
    /// Ссылка на новый звонок.
    public static let createLink = CallCapabilities(rawValue: 1 << 2)
    /// Вход в звонок по ссылке.
    public static let join = CallCapabilities(rawValue: 1 << 3)
    /// Журнал приходит страницами (`loadMore`).
    public static let paging = CallCapabilities(rawValue: 1 << 4)
}

public protocol CallHistoryRepository: Sendable {
    var capabilities: CallCapabilities { get }
    /// История, новые звонки сверху, и все её изменения, пока подписка жива.
    func calls() -> AsyncStream<[CallRecord]>
    /// Загрузить историю с сервера заново: новый список приходит в `calls()`, звонки,
    /// удалённые на другом устройстве, из него пропадают.
    func refresh() async
    /// Следующая страница журнала (курсор сервера). `true` — за ней может быть ещё.
    func loadMore() async -> Bool
    func delete(ids: [String]) async throws(MaxlyError)
    func createCallLink() async throws(MaxlyError) -> URL
    func join(link: String) async throws(MaxlyError)
}

public extension CallHistoryRepository {
    func refresh() async {}
    func loadMore() async -> Bool { false }
    func delete(ids: [String]) async throws(MaxlyError) { throw .invalidRequest }
    func createCallLink() async throws(MaxlyError) -> URL { throw .invalidRequest }
    func join(link: String) async throws(MaxlyError) { throw .invalidRequest }
}

/// Отметки журнала звонков на устройстве, у каждого аккаунта свои.
@MainActor
public protocol CallHistoryMarks: AnyObject {
    /// Звонки не новее этого времени пользователь уже видел на вкладке «Звонки».
    /// `nil`, пока вкладка у этого аккаунта ещё ни разу не считала.
    var lastSeen: Date? { get set }
    /// Звонки, скрытые на устройстве: без удаления на сервере они иначе вернулись бы.
    var hiddenIds: Set<String> { get set }
}

/// Отметки только в памяти: для тестов и превью.
@MainActor
public final class InMemoryCallHistoryMarks: CallHistoryMarks {
    public var lastSeen: Date?
    public var hiddenIds: Set<String>

    public init(lastSeen: Date? = nil, hiddenIds: Set<String> = []) {
        self.lastSeen = lastSeen
        self.hiddenIds = hiddenIds
    }
}
