import Foundation

/// Синхронизация с сервером (architecture.md, «Синхронизация с сервером»).
///
/// Когда сеть появляется, движок отправляет накопленные исходящие и запускает
/// периодический опрос: список чатов и свежие сообщения открытых чатов.
/// Когда сети нет, опрос останавливается.
// TODO: заменить опрос на поток событий ядра (новые сообщения, статусы),
// оставив опрос как запасной вариант. Состояние сети передаёт OrbitlApp
// (например, через NWPathMonitor).
public actor SyncEngine {
    private let outbox: OutboxQueue
    private let chats: ChatRepositoryImpl
    private let messages: MessageRepositoryImpl
    private let pollInterval: Duration

    private var pollTask: Task<Void, Never>?
    private var watchedChats: Set<String> = []

    public init(
        outbox: OutboxQueue,
        chats: ChatRepositoryImpl,
        messages: MessageRepositoryImpl,
        pollInterval: Duration = .seconds(30)
    ) {
        self.outbox = outbox
        self.chats = chats
        self.messages = messages
        self.pollInterval = pollInterval
    }

    public var isPolling: Bool { pollTask != nil }

    /// Сеть появилась: отправить очередь и включить опрос.
    public func networkBecameAvailable() async {
        await outbox.process()
        startPolling()
    }

    /// Сеть пропала: остановить опрос. Исходящие остаются в очереди.
    public func networkLost() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Чат открыт на экране, его сообщения нужно опрашивать.
    public func watch(chatId: String) {
        watchedChats.insert(chatId)
    }

    public func unwatch(chatId: String) {
        watchedChats.remove(chatId)
    }

    /// Один цикл опроса. Ошибки не прерывают синхронизацию, следующий цикл повторит запрос.
    public func pollOnce() async {
        try? await chats.refresh()
        for chatId in watchedChats {
            try? await messages.fetchLatest(chatId: chatId)
        }
        await outbox.process()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }
}
