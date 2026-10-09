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
    /// Полная синхронизация уже была в этом сеансе.
    private var synced = false
    /// Общий статус «в сети»: сюда уходит то, что пришло со списком контактов.
    private let presence: (any PresenceSink)?

    public init(core: any MaxCore, presence: (any PresenceSink)? = nil) {
        self.core = core
        self.presence = presence
    }

    public nonisolated var capabilities: ContactCapabilities { [.list, .presence, .add, .edit] }

    public nonisolated func contacts() -> AsyncStream<[Contact]> {
        AsyncStream { continuation in
            let task = Task { await self.feed(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func reset() {
        cached = nil
        pendingAdds = [:]
        synced = false
    }

    /// Короче семи цифр запрос не уходит. Нет человека — `nil`, а не ошибка сети.
    /// Одиннадцать цифр с восьмёрки — российский набор, на сервер уходит `+7`.
    public func findByPhone(_ phone: String) async throws(OrbitleError) -> Contact? {
        guard let payload = Self.queryPhone(phone) else { throw .invalidRequest }
        do {
            let found = try await core.findByPhone(phone: payload)
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

    /// Одним `CONTACT_ADD_BY_PHONE` 41 с именем и фамилией. Ядро без этого вызова —
    /// прежним путём: поиск по номеру и `CONTACT_UPDATE` с одним именем.
    public func addContact(phone: String, firstName: String, lastName: String) async throws(OrbitleError) -> Contact {
        guard let payload = Self.queryPhone(phone) else { throw .invalidRequest }
        do {
            let added = try await core.addContactByPhone(
                phone: payload,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !added.contact.id.isEmpty else { throw OrbitleError.rejected("Человек с таким номером не найден") }
            let contact = CoreMapping.contact(added.contact)
            remember(contact)
            return contact
        } catch let failure as CoreFailure where failure.key == "unsupported" {
            // Дальше — прежний путь.
        } catch let failure as CoreFailure where Self.isMissingPerson(failure) {
            throw .rejected("Человек с таким номером не найден")
        } catch let error as OrbitleError {
            throw error
        } catch {
            throw CoreMapping.apiError(error).orbitleError
        }
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

    public func rename(userId: String, firstName: String, lastName: String) async throws(OrbitleError) -> Contact {
        if let problem = ContactNameRules.problem(firstName: firstName, lastName: lastName) { throw .rejected(problem) }
        do {
            let saved = try await core.renameContact(
                userId: userId,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            var contact = CoreMapping.contact(saved)
            if contact.id.isEmpty, let known = cached?.first(where: { $0.id == userId }) {
                contact = known
                contact.firstName = firstName
                contact.lastName = lastName
            }
            if var list = cached, let index = list.firstIndex(where: { $0.id == userId }) {
                list[index] = contact
                cached = list
            }
            return contact
        } catch let error as OrbitleError {
            throw error
        } catch {
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    public func remove(userId: String) async throws(OrbitleError) {
        do {
            _ = try await core.removeContact(userId: userId)
            cached?.removeAll { $0.id == userId }
            pendingAdds[userId] = nil
        } catch let error as OrbitleError {
            throw error
        } catch {
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    /// `+` и цифры. Восемь в начале одиннадцати цифр заменяется на код `7`.
    static func queryPhone(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        if digits.count == 11, digits.first == "8" {
            return "+7\(digits.dropFirst())"
        }
        return "+\(digits)"
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
    /// Статусы списка — в общий `PresenceSink` (неизвестные он сам пропускает).
    private func remember(_ list: [Contact]) async {
        guard let presence, !list.isEmpty else { return }
        var batch: [String: Contact.Presence] = [:]
        for contact in list { batch[contact.id] = contact.presence }
        await presence.record(batch, at: Date())
    }

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
            synced = true
            guard !raw.isEmpty else { return }
            let list = listed(raw)
            await remember(list)
            cached = list
        } catch {
            Log.warning(.contacts, "Синхронизация контактов не удалась: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    /// Кэш, затем список ядра. В первый раз за сеанс — ещё и полная синхронизация: ядро не
    /// хранит контакты между запусками, а вход с отметкой `contactsSync` приносит только
    /// изменения. Раньше вкладка «Контакты» оставалась пустой, пока синхронизацию не запускала
    /// строка «Контакты» в настройках.
    private func feed(_ continuation: AsyncStream<[Contact]>.Continuation) async {
        if let cached { continuation.yield(cached) }
        do {
            var list = listed(try await core.loadContacts())
            await remember(list)
            Log.info(.contacts, "Контакты с сервера: \(list.count)")
            var shown = false
            if !synced {
                // Что уже есть — сразу, полный список следом.
                if !list.isEmpty {
                    cached = list
                    continuation.yield(list)
                    shown = true
                }
                if let raw = try? await core.syncContacts() {
                    synced = true
                    Log.info(.contacts, "Синхронизация контактов: \(raw.count)")
                    let fresh = listed(raw)
                    await remember(fresh)
                    if !raw.isEmpty, fresh != list {
                        list = fresh
                        shown = false
                    }
                }
            }
            if !shown {
                cached = list
                continuation.yield(list)
            }
        } catch {
            Log.warning(.contacts, "Контакты не загрузились: \(error)")
            // Экран не должен вечно показывать загрузку.
            if cached == nil { continuation.yield([]) }
        }
        continuation.finish()
    }
}

/// Пуши журнала звонков (`NOTIF_CALL_HISTORY` 165), которые раздаёт `SyncEngine`.
public protocol CallLogSink: Sendable {
    /// `action` — `add` или `remove`; `item.historyId` пуст, если пуш пришёл без записей.
    func callLogChanged(action: String, item: CallLogItem) async
}

/// Журнал звонков из ядра (`CALL_HISTORY` 163 по курсору, пуш 165).
///
/// Первый запрос идёт с пустым курсором, следующие — с курсором прошлого ответа: так приходят
/// следующие страницы (`loadMore`) и новые звонки (`refresh`). Ответ с `reset` заменяет журнал.
/// Пуш `add` перечитывает журнал с курсора, пуш `remove` сразу убирает записи.
/// Ядро без `callHistory` (фейки в тестах) читает прежний журнал `VIDEO_CHAT_HISTORY` 79.
///
/// Подписка сразу получает последний собранный список (если он есть), затем свежий. Имена и
/// аватары собеседников берутся из контактов ядра, остальные — из карточки диалога или чата.
/// Список живёт только в памяти: `reset()` забывает его при выходе и смене аккаунта.
public actor CoreCallHistoryRepository: CallHistoryRepository, CallLogSink {
    private let core: any MaxCore
    private var cached: [CallRecord]?
    private var log = CallLog()
    /// Ядро не умеет `CALL_HISTORY` 163: журнал целиком из `VIDEO_CHAT_HISTORY` 79.
    private var legacy = false
    private var me: String?
    /// Имена и аватары по id собеседника (у группового — по id чата).
    private var peers: [String: CallLogPeer] = [:]
    private var lookedUp: Set<String> = []
    private var subscribers: [UUID: AsyncStream<[CallRecord]>.Continuation] = [:]
    private var loading: Task<Void, Never>?
    private var loads = 0
    /// Растёт при `reset()`: ответ, начатый до выхода, не попадает к следующему аккаунту.
    private var generation = 0
    /// Сколько карточек спрашивать за один проход: остальные — при следующем.
    private let profileLookups = 20

    public init(core: any MaxCore) {
        self.core = core
    }

    /// Удаление уходит на сервер (`VIDEO_CHAT_DELETE_HISTORY`), ссылка создаётся там же.
    /// Вход по ссылке открывает звонок, поэтому его делает центр звонков, а не журнал.
    public nonisolated var capabilities: CallCapabilities { [.history, .delete, .createLink, .join, .paging] }

    /// Удаляет звонки на сервере (`historyIds`) и сразу убирает их из списка.
    public func delete(ids: [String]) async throws(OrbitleError) {
        let valid = ids.filter { Int64($0) != nil }
        guard !valid.isEmpty else { return }
        do {
            try await core.deleteCallHistory(ids: valid)
        } catch {
            Log.warning(.calls, "Звонки не удалились: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
        Log.info(.calls, "Удалено звонков: \(valid.count)")
        if legacy {
            cached = cached?.filter { !valid.contains($0.id) }
            if let cached { broadcast(cached) }
        } else if log.remove(valid) {
            await publish(generation)
        }
    }

    public func createCallLink() async throws(OrbitleError) -> URL {
        do {
            let link = try await core.createCallLink()
            guard let url = URL(string: link.url) else { throw OrbitleError.invalidRequest }
            return url
        } catch let error as OrbitleError {
            throw error
        } catch {
            Log.warning(.calls, "Ссылка на звонок не создалась: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }

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

    /// Следующая страница с курсора прошлого ответа.
    public func loadMore() async -> Bool {
        guard !legacy, log.hasMore else { return false }
        if let loading { await loading.value }
        guard log.hasMore else { return false }
        await load()
        return !legacy && log.hasMore
    }

    public func reset() {
        generation += 1
        cached = nil
        log = CallLog()
        legacy = false
        me = nil
        peers = [:]
        lookedUp = []
    }

    // MARK: Пуши

    public func callLogChanged(action: String, item: CallLogItem) async {
        guard !legacy else {
            await refresh()
            return
        }
        switch action {
        case "remove" where !item.historyId.isEmpty:
            if log.remove([item.historyId]) { await publish(generation) }
        case "add" where !item.historyId.isEmpty:
            // В пуше нет исхода и длительности: полная запись приходит с курсора.
            await refresh()
            if log.items[item.historyId] == nil, log.add([item]) { await publish(generation) }
        default:
            await refresh()
        }
    }

    // MARK: Загрузка

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
        if legacy {
            await fetchLegacy(started)
            return
        }
        do {
            let page = try await core.callHistory(sync: log.sync)
            guard started == generation else { return }
            log.apply(page)
            Log.info(.calls, "Журнал звонков: +\(page.items.count)\(page.reset ? ", заново" : ""), всего \(log.items.count)")
            await publish(started)
        } catch let failure as CoreFailure where failure.key == "unsupported" {
            guard started == generation else { return }
            legacy = true
            await fetchLegacy(started)
        } catch {
            Log.warning(.calls, "Журнал звонков не загрузился: \(error)")
            // Экран не должен вечно показывать загрузку, а известный список остаётся.
            guard started == generation, cached == nil else { return }
            broadcast([])
        }
    }

    private func fetchLegacy(_ started: Int) async {
        do {
            let list = try await core.loadCallHistory().map(CoreMapping.call)
                .sorted { $0.date > $1.date }
            guard started == generation else { return }
            Log.info(.calls, "Звонков в журнале: \(list.count)")
            cached = list
            broadcast(list)
        } catch {
            Log.warning(.calls, "Журнал звонков не загрузился: \(error)")
            guard started == generation, cached == nil else { return }
            broadcast([])
        }
    }

    /// Собирает строки из журнала и раздаёт их; незнакомые имена ищет и раздаёт ещё раз.
    private func publish(_ started: Int) async {
        let mine = await ownId()
        guard started == generation else { return }
        emit(mine)
        let unknown = unknownPeers(mine)
        guard !unknown.isEmpty else { return }
        lookedUp.formUnion(unknown.map(\.key))
        let found = await resolve(unknown, me: mine)
        guard started == generation, !found.isEmpty else { return }
        peers.merge(found) { _, new in new }
        emit(mine)
    }

    private func emit(_ mine: String) {
        let list = log.ordered.map { item in
            CallLog.record(item, me: mine, peer: peers[Self.peerKey(item, me: mine)])
        }
        cached = list
        broadcast(list)
    }

    private func ownId() async -> String {
        if let me, !me.isEmpty { return me }
        let id = await core.currentUserId()
        me = id
        return id
    }

    /// Ключ имени: собеседник, у группового — чат.
    private static func peerKey(_ item: CallLogItem, me: String) -> String {
        item.isGroup ? item.chatId : CallLog.peerId(of: item, me: me)
    }

    private struct Unknown: Sendable {
        var key: String
        var isGroup: Bool
    }

    private func unknownPeers(_ mine: String) -> [Unknown] {
        var seen: Set<String> = []
        var list: [Unknown] = []
        for item in log.ordered where item.callName.isEmpty {
            let key = Self.peerKey(item, me: mine)
            guard !key.isEmpty, peers[key] == nil, !lookedUp.contains(key), seen.insert(key).inserted else { continue }
            list.append(Unknown(key: key, isGroup: item.isGroup))
        }
        return list
    }

    /// Сначала контакты ядра (они уже в памяти), остальным — карточка диалога или чата.
    private func resolve(_ unknown: [Unknown], me mine: String) async -> [String: CallLogPeer] {
        var found: [String: CallLogPeer] = [:]
        if unknown.contains(where: { !$0.isGroup }), let contacts = try? await core.loadContacts() {
            let wanted = Set(unknown.filter { !$0.isGroup }.map(\.key))
            for contact in contacts where wanted.contains(contact.id) {
                let name = [contact.firstName, contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                guard !name.isEmpty else { continue }
                found[contact.id] = CallLogPeer(name: name, avatarURL: contact.avatarURL.isEmpty ? nil : URL(string: contact.avatarURL))
            }
        }
        for entry in unknown.filter({ found[$0.key] == nil }).prefix(profileLookups) {
            let chatId = entry.isGroup ? entry.key : CallLog.dialogChatId(me: mine, peerId: entry.key)
            guard !chatId.isEmpty, let profile = try? await core.loadProfile(chatId: chatId), !profile.title.isEmpty else { continue }
            found[entry.key] = CallLogPeer(name: profile.title, avatarURL: profile.avatarURL.isEmpty ? nil : URL(string: profile.avatarURL))
        }
        return found
    }

    private func broadcast(_ list: [CallRecord]) {
        subscribers.values.forEach { $0.yield(list) }
    }
}

/// Карточки чатов из ядра: собеседник, бот, группа или канал.
public struct CoreChatProfileRepository: ChatProfileRepository {
    private let core: any MaxCore
    private let cache: ChatProfileCache?
    /// Общий статус «в сети»: карточка собеседника приносит свежий.
    private let presence: (any PresenceSink)?

    public init(core: any MaxCore, cache: ChatProfileCache? = nil, presence: (any PresenceSink)? = nil) {
        self.core = core
        self.cache = cache
        self.presence = presence
    }

    public func profile(chatId: String) async throws(OrbitleError) -> ChatProfile {
        do {
            let profile = CoreMapping.profile(try await core.loadProfile(chatId: chatId))
            Log.info(.chats, "Карточка чата \(chatId): \(profile.kind.rawValue)")
            await cache?.save(profile)
            if profile.kind == .user, let peerId = profile.peerId, !peerId.isEmpty {
                await presence?.record([peerId: profile.presence], at: Date())
            }
            return profile
        } catch {
            Log.warning(.chats, "Карточка чата \(chatId) не загрузилась: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    public func cachedProfile(chatId: String) async -> ChatProfile? {
        await cache?.profile(chatId: chatId)
    }

    public func recentProfile(chatId: String, maxAge: TimeInterval) async -> ChatProfile? {
        await cache?.fresh(chatId: chatId, maxAge: maxAge)
    }
}
