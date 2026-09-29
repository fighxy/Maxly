import Foundation
import Observation
import OrbitlDomain

/// Список чатов: живой поток из репозитория, обновление, отметка прочитанного и
/// индикатор соединения. Экран только рисует `content`, `items` и `banner`.
@MainActor
@Observable
public final class ChatListViewModel {
    /// Что показать вместо списка, когда строк нет.
    public enum Content: Equatable, Sendable {
        case loading
        case list
        case empty
        case offline
        case failed(String)
    }

    /// Чаты по убыванию `updatedAt`, при равенстве по id.
    public private(set) var chats: [Chat] = []
    public private(set) var items: [ChatListItem] = []
    public private(set) var isRefreshing = false
    public private(set) var error: OrbitlError?
    public private(set) var connection: ConnectionState
    /// Чат, открытый сейчас на экране. Его новые сообщения сразу отмечаются прочитанными.
    public private(set) var openChatId: String?
    /// Идёт догрузка после восстановления соединения: плашка говорит «Обновление…».
    public private(set) var isCatchingUp = false

    /// Первое значение из репозитория уже пришло.
    private var hasSnapshot = false
    /// Хотя бы одно обновление с сервера закончилось (успешно или нет).
    private var hasRefreshed = false

    @ObservationIgnored private let repository: any ChatRepository
    @ObservationIgnored private let status: (any ConnectionStatusProvider)?
    @ObservationIgnored private let formatter: ChatListFormatter
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var watches: [Task<Void, Never>] = []
    @ObservationIgnored private var marking: Set<String> = []

    public init(
        chats: any ChatRepository,
        connection: (any ConnectionStatusProvider)? = nil,
        formatter: ChatListFormatter = ChatListFormatter(),
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = chats
        self.status = connection
        self.formatter = formatter
        self.now = now
        self.connection = connection == nil ? .online : .connecting
    }

    // MARK: Состояние для экрана

    public var content: Content {
        if !items.isEmpty { return .list }
        if !hasSnapshot || (isRefreshing && !hasRefreshed) { return .loading }
        if connection == .offline { return .offline }
        if let message = error?.userMessage { return .failed(message) }
        if !hasRefreshed, connection == .connecting { return .loading }
        return .empty
    }

    /// Плашка над списком. Когда список пуст из-за сети, об этом уже говорит `content`.
    public var banner: String? {
        guard content != .offline else { return nil }
        switch connection {
        case .online: return isCatchingUp && content == .list ? "Обновление…" : nil
        case .connecting: return "Подключение…"
        case .offline: return "Нет соединения. Показаны сохранённые чаты"
        }
    }

    /// Ошибка поверх непустого списка. Сетевую ошибку уже показывает плашка.
    public var inlineError: String? {
        guard content == .list, let error else { return nil }
        if error == .networkUnavailable, connection != .online { return nil }
        return error.userMessage
    }

    public var totalUnread: Int {
        chats.reduce(0) { $0 + max($1.unreadCount, 0) }
    }

    // MARK: Жизненный цикл

    /// Подписка на чаты и соединение. Повторный вызов ничего не делает.
    public func activate() {
        guard watches.isEmpty else { return }
        let stream = repository.chats()
        watches.append(Task { [weak self] in
            for await chats in stream {
                guard let self else { return }
                self.apply(chats)
            }
        })
        if let status {
            let states = status.connectionStates()
            watches.append(Task { [weak self] in
                for await state in states {
                    guard let self else { return }
                    let previous = self.connection
                    self.connection = state
                    if state == .online, previous != .online, self.hasRefreshed {
                        // Связь вернулась после обрыва: список мог устареть, догружаем сразу.
                        await self.catchUp()
                    }
                }
            })
        }
    }

    public func deactivate() {
        watches.forEach { $0.cancel() }
        watches.removeAll()
    }

    // MARK: Действия

    /// Обновление с сервера (потянуть вниз, вход на экран, кнопка «Повторить»).
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            hasRefreshed = true
        }
        do {
            try await repository.refresh()
            error = nil
        } catch {
            if error != .cancelled { self.error = error }
        }
        // Метки времени зависят от текущего дня: пересчитываем после обновления.
        rebuildItems()
    }

    /// Чат открыт на экране (`nil`, если закрыт). Непрочитанные сбрасываются сразу.
    public func open(chatId: String?) async {
        openChatId = chatId
        guard let chatId else { return }
        if let chat = chats.first(where: { $0.id == chatId }), chat.unreadCount == 0 { return }
        await markRead(chatId)
    }

    private func catchUp() async {
        isCatchingUp = true
        defer { isCatchingUp = false }
        await refresh()
    }

    public func dismissError() {
        error = nil
    }

    // MARK: Внутреннее

    func apply(_ next: [Chat]) {
        chats = next.sorted { lhs, rhs in
            lhs.updatedAt != rhs.updatedAt ? lhs.updatedAt > rhs.updatedAt : lhs.id < rhs.id
        }
        hasSnapshot = true
        rebuildItems()
        if let open = openChatId,
           let chat = chats.first(where: { $0.id == open }),
           chat.unreadCount > 0,
           !marking.contains(open) {
            // Новое сообщение пришло в открытый чат: он уже на экране, значит прочитан.
            Task { [weak self] in await self?.markRead(open) }
        }
    }

    private func rebuildItems() {
        let date = now()
        items = chats.map { formatter.item(for: $0, now: date) }
    }

    private func markRead(_ chatId: String) async {
        guard !marking.contains(chatId) else { return }
        marking.insert(chatId)
        defer { marking.remove(chatId) }
        // Бейдж пропадает сразу, не дожидаясь ответа базы.
        if let index = chats.firstIndex(where: { $0.id == chatId }), chats[index].unreadCount > 0 {
            chats[index].unreadCount = 0
            rebuildItems()
        }
        do {
            try await repository.markAsRead(chatId: chatId)
        } catch {
            // Без сети отметка догонит сервер при следующем открытии, экран её не показывает.
            if error != .cancelled, error != .networkUnavailable {
                self.error = error
            }
        }
    }
}
