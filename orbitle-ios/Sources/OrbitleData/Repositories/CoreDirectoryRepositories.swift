import Foundation
import OrbitleDomain

/// Контакты аккаунта из ядра: список `contacts` ответа `LOGIN` с последним известным статусом.
///
/// Каждая подписка сразу получает последний загруженный список (если он есть) и затем свежий
/// из ядра. Список живёт только в памяти: `reset()` забывает его при выходе и смене аккаунта.
public actor CoreContactRepository: ContactRepository {
    private let core: any MaxCore
    private var cached: [Contact]?
    /// Добавлены локально и ещё не пришли в ответе `loadContacts`.
    private var pendingAdds: [String: Contact] = [:]

    public init(core: any MaxCore) {
        self.core = core
    }

    public nonisolated var capabilities: ContactCapabilities { [.list, .presence, .add] }

    public nonisolated func contacts() -> AsyncStream<[Contact]> {
        AsyncStream { continuation in
            let task = Task { await self.feed(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func reset() {
        cached = nil
        pendingAdds = [:]
    }

    /// Короче семи цифр запрос не уходит. Нет человека — `nil`, а не ошибка сети.
    public func findByPhone(_ phone: String) async throws(OrbitleError) -> Contact? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 7 else { throw .invalidRequest }
        do {
            let found = try await core.findByPhone(phone: "+\(digits)")
            guard !found.id.isEmpty else { return nil }
            return CoreMapping.contact(found)
        } catch let failure as CoreFailure where Self.isMissingPerson(failure) {
            return nil
        } catch let error as OrbitleError {
            throw error
        } catch {
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    /// Фамилия в проверенное тело не входит: уходит только непустое имя.
    public func addContact(phone: String, firstName: String, lastName: String) async throws(OrbitleError) -> Contact {
        _ = lastName
        guard let person = try await findByPhone(phone) else {
            throw .rejected("Человек с таким номером не найден")
        }
        return try await addFoundContact(userId: person.id, firstName: firstName)
    }

    public func addFoundContact(userId: String, firstName: String) async throws(OrbitleError) -> Contact {
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let saved = try await core.addContact(userId: userId, firstName: name)
            guard !saved.id.isEmpty else { throw OrbitleError.invalidRequest }
            let contact = CoreMapping.contact(saved)
            remember(contact)
            return contact
        } catch let error as OrbitleError {
            throw error
        } catch {
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    /// Сервер не нашёл человека или ответ без контакта.
    static func isMissingPerson(_ failure: CoreFailure) -> Bool {
        if failure.kind == "NOT_FOUND" || failure.kind == "MALFORMED_REPLY" { return true }
        let key = failure.key?.lowercased() ?? ""
        return key.contains("not.found") || key.contains("not_found")
    }

    private func remember(_ contact: Contact) {
        pendingAdds[contact.id] = contact
        var list = cached ?? []
        list.removeAll { $0.id == contact.id }
        list.append(contact)
        cached = list
    }

    /// Серверный список плюс локальные добавления, которых в нём ещё нет.
    /// Удалённый аккаунт (`accountStatus != 0`) в список не входит.
    private func listed(_ contacts: [CoreContact]) -> [Contact] {
        let server = contacts.compactMap { core -> Contact? in
            guard (core.accountStatus ?? 0) == 0 else { return nil }
            return CoreMapping.contact(core)
        }
        var merged = server
        let ids = Set(server.map(\.id))
        var stillPending: [String: Contact] = [:]
        for (id, contact) in pendingAdds {
            if ids.contains(id) { continue }
            stillPending[id] = contact
            merged.append(contact)
        }
        pendingAdds = stillPending
        return merged
    }

    /// Запросить у сервера свежий список (`CONTACT_UPDATE` с `contactsSync`) и запомнить его.
    /// Следующая подписка получит уже его. Если сервер отказал, остаётся прежний список.
    public func sync() async throws(OrbitleError) {
        do {
            let raw = try await core.syncContacts()
            Log.info(.contacts, "Синхронизация контактов: \(raw.count)")
            guard !raw.isEmpty else { return }
            cached = listed(raw)
        } catch {
            Log.warning(.contacts, "Синхронизация контактов не удалась: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    private func feed(_ continuation: AsyncStream<[Contact]>.Continuation) async {
        if let cached { continuation.yield(cached) }
        do {
            let list = listed(try await core.loadContacts())
            Log.info(.contacts, "Контакты с сервера: \(list.count)")
            cached = list
            continuation.yield(list)
        } catch {
            Log.warning(.contacts, "Контакты не загрузились: \(error)")
            // Экран не должен вечно показывать загрузку.
            if cached == nil { continuation.yield([]) }
        }
        continuation.finish()
    }
}

/// Журнал звонков из ядра (`VIDEO_CHAT_HISTORY`).
///
/// Подписка сразу получает последний загруженный список (если он есть), затем свежий из ядра
/// и дальше каждый следующий: `refresh()` грузит историю заново и раздаёт её всем живым
/// подпискам, так что звонки, удалённые на другом устройстве, пропадают без перезапуска.
/// Список живёт только в памяти: `reset()` забывает его при выходе и смене аккаунта.
public actor CoreCallHistoryRepository: CallHistoryRepository {
    private let core: any MaxCore
    private var cached: [CallRecord]?
    private var subscribers: [UUID: AsyncStream<[CallRecord]>.Continuation] = [:]
    private var loading: Task<Void, Never>?
    private var loads = 0
    /// Растёт при `reset()`: ответ, начатый до выхода, не попадает к следующему аккаунту.
    private var generation = 0

    public init(core: any MaxCore) {
        self.core = core
    }

    public nonisolated var capabilities: CallCapabilities { [.history] }

    public nonisolated func calls() -> AsyncStream<[CallRecord]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [CallRecord].self)
        let id = UUID()
        let task = Task { await self.subscribe(id, continuation) }
        continuation.onTermination = { _ in
            task.cancel()
            Task { await self.unsubscribe(id) }
        }
        return stream
    }

    /// Загрузка, начатая уже после вызова: идущая сейчас могла уйти до удаления на сервере.
    public func refresh() async {
        if let loading { await loading.value }
        await load()
    }

    public func reset() {
        generation += 1
        cached = nil
    }

    private func subscribe(_ id: UUID, _ continuation: AsyncStream<[CallRecord]>.Continuation) async {
        guard !Task.isCancelled else { return }
        subscribers[id] = continuation
        if let cached { continuation.yield(cached) }
        await load()
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    /// Одна загрузка на всех: вызов во время загрузки ждёт её же.
    private func load() async {
        if let loading {
            await loading.value
            return
        }
        loads += 1
        let token = loads
        let started = generation
        // Задача сама снимает себя до завершения: кто дождался её, уже видит `loading == nil`.
        let task = Task {
            await self.fetch(started)
            await self.finishLoad(token)
        }
        loading = task
        await task.value
    }

    private func finishLoad(_ token: Int) {
        if token == loads { loading = nil }
    }

    private func fetch(_ started: Int) async {
        do {
            let list = try await core.loadCallHistory().map(CoreMapping.call)
                .sorted { $0.date > $1.date }
            guard started == generation else { return }
            Log.info(.calls, "Звонков в журнале: \(list.count)")
            cached = list
            broadcast(list)
        } catch {
            Log.warning(.calls, "Журнал звонков не загрузился: \(error)")
            // Экран не должен вечно показывать загрузку, а известный список остаётся.
            guard started == generation, cached == nil else { return }
            broadcast([])
        }
    }

    private func broadcast(_ list: [CallRecord]) {
        subscribers.values.forEach { $0.yield(list) }
    }
}

/// Карточки чатов из ядра: собеседник, бот, группа или канал.
public struct CoreChatProfileRepository: ChatProfileRepository {
    private let core: any MaxCore
    private let cache: ChatProfileCache?

    public init(core: any MaxCore, cache: ChatProfileCache? = nil) {
        self.core = core
        self.cache = cache
    }

    public func profile(chatId: String) async throws(OrbitleError) -> ChatProfile {
        do {
            let profile = CoreMapping.profile(try await core.loadProfile(chatId: chatId))
            Log.info(.chats, "Карточка чата \(chatId): \(profile.kind.rawValue)")
            await cache?.save(profile)
            return profile
        } catch {
            Log.warning(.chats, "Карточка чата \(chatId) не загрузилась: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    public func cachedProfile(chatId: String) async -> ChatProfile? {
        await cache?.profile(chatId: chatId)
    }
}
