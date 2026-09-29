import Foundation
import OrbitlDomain

/// Синхронизация с сервером (architecture.md, «Синхронизация с сервером»).
///
/// Когда соединение ядра онлайн, движок отправляет очередь и опрашивает открытый чат.
/// Пуши пишутся в базу сразу. Опрос остаётся запасным путём, если пуш потерялся.
/// Состояние сети передаёт `SessionManager` по фазе ядра.
public actor SyncEngine {
    private let outbox: OutboxQueue
    private let chats: ChatRepositoryImpl
    private let messages: MessageRepositoryImpl
    private let pollInterval: Duration

    private var pollTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    /// Пока ложь, подписка на пуши молчит. Прямой `consume` для тестов это не смотрит.
    private var acceptEvents = false
    /// Сколько пушей из потока сейчас пишется в базу. `stopEvents` ждёт, пока их не станет.
    private var eventsInFlight = 0
    /// Кто ждёт в `stopEvents`, пока допишутся начатые пуши.
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    /// Последний сигнал о сети. `networkLost`, пришедший, пока `networkBecameAvailable`
    /// отправляла очередь, отменяет запуск опроса.
    private var isOnline = false
    private var watchedChats: Set<String> = []
    private var focused: String?

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

    /// Чаты, история которых сейчас опрашивается.
    public var watched: Set<String> { watchedChats }

    /// Сеть появилась: отправить очередь и включить опрос.
    public func networkBecameAvailable() async {
        isOnline = true
        await outbox.process()
        guard isOnline else { return }
        startPolling()
    }

    /// Сеть пропала: остановить опрос и дождаться уже начатого цикла, чтобы он не записал поверх очистки.
    public func networkLost() async {
        isOnline = false
        let task = pollTask
        pollTask = nil
        task?.cancel()
        await task?.value
    }

    /// Подписка на пуши ядра. Повторный вызов снова включает запись: поток горячий и живёт вместе с клиентом.
    public func startEvents(_ core: any MaxCore) {
        acceptEvents = true
        guard eventTask == nil else { return }
        // Сильная ссылка берётся только на время одного пуша: поток ядра бесконечен.
        eventTask = Task { [weak self] in
            guard let events = await self?.coreEvents(core) else { return }
            for await event in events {
                guard let self else { return }
                await self.deliver(event)
            }
        }
    }

    /// Выход и смена аккаунта. Следующие пуши не попадают в базу, а уже начатая запись
    /// заканчивается до возврата, чтобы не лечь поверх очистки базы.
    public func stopEvents() async {
        acceptEvents = false
        guard eventsInFlight > 0 else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    /// Забыть открытые чаты. Выход и смена аккаунта не должны опрашивать чужие чаты.
    public func reset() {
        watchedChats.removeAll()
        focused = nil
    }

    /// Свои сообщения сразу сдвигают строку чата: при постановке в очередь меняются
    /// превью и время, после ответа сервера ещё и `lastMessageId`. Вызывается один раз
    /// при сборке зависимостей.
    public func connectOutgoing() async {
        let chats = chats
        await messages.setOutgoingHandler { change in
            switch change {
            case .queued(let record):
                _ = try? await chats.noteMessage(
                    chatId: record.chatId, messageId: nil, preview: record.text, at: record.timestamp, incoming: false,
                    authorId: record.authorId, outgoing: true, delivery: .sending, localId: record.id
                )
            case .sent(let record):
                try? await chats.noteSent(
                    chatId: record.chatId, localId: record.id, serverId: record.serverId, preview: record.text,
                    at: record.timestamp, authorId: record.authorId
                )
            case .failed(let record):
                try? await chats.noteSendFailed(chatId: record.chatId, localId: record.id)
            }
        }
    }

    /// Пуш из потока ядра. Молчит, пока запись выключена.
    private func deliver(_ event: CoreEvent) async {
        guard acceptEvents else { return }
        eventsInFlight += 1
        await consume(event)
        eventsInFlight -= 1
        guard eventsInFlight == 0 else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    /// Записывает одно событие ядра в базу. Опрос остаётся запасным путём.
    public func consume(_ event: CoreEvent) async {
        switch event.kind {
        case .message:
            guard let record = MessageRecord(event) else { return }
            let inserted: Set<String> = (try? await messages.upsert([record])) ?? []
            let mine = await messages.currentUser()
            let fromOther = !mine.isEmpty && !event.authorId.isEmpty && event.authorId != mine
            let own = !mine.isEmpty && event.authorId == mine
            // Пришло сообщение — автор больше не печатает.
            await chats.stopTyping(chatId: event.chatId, userId: event.authorId)
            let known = (try? await chats.noteMessage(
                chatId: event.chatId,
                messageId: event.messageId,
                preview: event.text,
                at: Date(unixMillis: event.timeMs),
                incoming: fromOther && inserted.contains(record.id),
                authorId: event.authorId.isEmpty ? nil : event.authorId,
                outgoing: own,
                delivery: own ? .sent : nil
            )) ?? false
            if !known {
                // Чата ещё нет в базе: подтянуть его строку, иначе сообщение не будет видно в списке.
                try? await chats.refresh(chatId: event.chatId)
            }
        case .edited:
            guard let record = MessageRecord(event) else { return }
            _ = try? await messages.applyEdit(record)
            try? await chats.noteEdit(chatId: event.chatId, messageId: event.messageId, text: event.text)
        case .deleted:
            guard !event.messageId.isEmpty else { return }
            let last = event.chatId.isEmpty ? nil : await chats.lastMessageId(chatId: event.chatId)
            try? await messages.delete(messageId: event.messageId)
            guard last == event.messageId else { return }
            // Превью показывало удалённое сообщение. Сервер знает новое последнее,
            // если он недоступен или
            // ещё не знает об удалении, берём самое свежее из кэша.
            try? await chats.refresh(chatId: event.chatId)
            if await chats.lastMessageId(chatId: event.chatId) == event.messageId {
                let latest = await messages.latest(chatId: event.chatId)
                let mine = await messages.currentUser()
                try? await chats.replaceLast(chatId: event.chatId, with: latest, currentUser: mine)
            }
        case .chat:
            guard let record = ChatRecord(event) else { return }
            try? await chats.upsert([record])
        case .read:
            // Пуш прочтения приходит и когда собеседник прочитал наши сообщения. Наш счётчик
            // непрочитанных меняет только своя отметка (с другого устройства).
            // Отметка собеседника ставит галочки «прочитано» на свои сообщения.
            let mine = await messages.currentUser()
            guard !mine.isEmpty, !event.authorId.isEmpty else { return }
            if event.authorId != mine {
                try? await chats.applyPeerRead(chatId: event.chatId, mark: event.timeMs)
                return
            }
            try? await chats.applyOwnRead(chatId: event.chatId, mark: event.timeMs, setAsUnread: event.unread > 0)
        case .typing:
            let mine = await messages.currentUser()
            guard !event.authorId.isEmpty, event.authorId != mine else { return }
            await chats.noteTyping(chatId: event.chatId, userId: event.authorId)
        }
    }

    /// Чат, который сейчас на экране. Опрос свежей истории идёт только по нему.
    public func focus(_ chatId: String?) {
        if let focused, focused != chatId {
            watchedChats.remove(focused)
        }
        focused = chatId
        if let chatId {
            watchedChats.insert(chatId)
        }
    }

    /// Один цикл опроса. Ошибки не прерывают синхронизацию, следующий цикл повторит запрос.
    public func pollOnce() async {
        try? await chats.refresh()
        for chatId in watchedChats {
            try? await messages.fetchLatest(chatId: chatId)
        }
        await outbox.process()
    }

    private func coreEvents(_ core: any MaxCore) -> AsyncStream<CoreEvent> {
        core.events()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = makePollTask(interval: pollInterval)
    }

    /// Задача вне этого актора: `networkLost` ждёт её завершения и не должен занимать актор.
    private nonisolated func makePollTask(interval: Duration) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }
}
