import Foundation
import OrbitleDomain

/// Хранилище исходящих для очереди. Его реализует `MessageRepositoryImpl`.
///
/// Очередь персистентна через SwiftData: всё, что лежит в базе со статусом
/// `sending`, считается неотправленным и подхватывается при следующем `process()`,
/// в том числе после перезапуска приложения.
public protocol OutboxStore: Actor {
    /// Все исходящие со статусом `sending`, от старых к новым.
    func pendingOutgoing() async -> [MessageRecord]
    /// Исходящее по локальному id, если оно всё ещё ждёт отправки.
    func outgoing(localId: String) async -> MessageRecord?
    func markSent(localId: String, serverId: String, timestamp: Date) async
    func markFailed(localId: String) async
}

/// Очередь исходящих сообщений (architecture.md, «Ошибки и офлайн»).
///
/// Отправляет по одному в порядке постановки. Временные ошибки повторяются
/// с экспоненциальной задержкой. Без сети очередь останавливается, сообщения
/// остаются в статусе `sending`, а `SyncEngine` запускает `process()` снова,
/// когда сеть вернётся. После исчерпания попыток сообщение получает статус `failed`.
public actor OutboxQueue {
    public struct RetryPolicy: Sendable {
        public var maxAttempts: Int
        public var baseDelay: Duration
        public var maxDelay: Duration

        public init(maxAttempts: Int = 5, baseDelay: Duration = .seconds(1), maxDelay: Duration = .seconds(30)) {
            self.maxAttempts = maxAttempts
            self.baseDelay = baseDelay
            self.maxDelay = maxDelay
        }

        /// Задержка перед повтором: 1, 2, 4, 8… секунд, но не больше `maxDelay`.
        public func delay(afterAttempt attempt: Int) -> Duration {
            let factor = 1 << min(max(attempt - 1, 0), 16)
            return min(baseDelay * factor, maxDelay)
        }
    }

    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let api: any MaxAPI
    private let policy: RetryPolicy
    private let sleep: Sleep
    private weak var store: (any OutboxStore)?

    /// Локальные id в порядке отправки.
    private var pending: [String] = []
    private var isProcessing = false

    public init(
        api: any MaxAPI,
        policy: RetryPolicy = RetryPolicy(),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.api = api
        self.policy = policy
        self.sleep = sleep
    }

    public func attach(store: any OutboxStore) {
        self.store = store
    }

    /// Сколько сообщений сейчас ждут отправки в памяти очереди.
    public var pendingCount: Int { pending.count }

    /// Ставит сообщение в очередь и сразу пытается отправить.
    public func enqueue(_ localId: String) async {
        if !pending.contains(localId) {
            pending.append(localId)
        }
        await process()
    }

    /// Отправляет всё, что ждёт. Повторный вызов во время работы ничего не делает:
    /// новые сообщения подхватит уже идущий цикл.
    public func process() async {
        guard !isProcessing, let store else { return }
        isProcessing = true
        defer { isProcessing = false }

        // Подхватываем то, что осталось в базе со статусом sending.
        for record in await store.pendingOutgoing() where !pending.contains(record.id) {
            pending.append(record.id)
        }

        while let localId = pending.first {
            guard let record = await store.outgoing(localId: localId) else {
                // Уже отправлено или удалено.
                pending.removeFirst()
                continue
            }

            var attempt = 0
            attempts: while true {
                if Task.isCancelled { return }
                let result = await api.sendMessage(chatId: record.chatId, text: record.text, clientId: record.id)
                switch result {
                case .success(let sent):
                    await store.markSent(localId: localId, serverId: sent.serverId, timestamp: sent.timestamp)
                    pending.removeFirst()
                    break attempts
                case .failure(.offline), .failure(.cancelled):
                    // Сети нет или вызов отменён: оставляем сообщение в sending и ждём SyncEngine.
                    return
                case .failure(let error):
                    attempt += 1
                    if !error.isRetryable || attempt >= policy.maxAttempts {
                        Log.warning(.messages, "Сообщение не отправлено после \(attempt) попыток: \(error)")
                        await store.markFailed(localId: localId)
                        pending.removeFirst()
                        break attempts
                    }
                    do {
                        try await sleep(policy.delay(afterAttempt: attempt))
                    } catch {
                        return // задача отменена
                    }
                }
            }
        }
    }
}
