import Foundation
import OrbitlDomain

/// Контакты аккаунта из ядра: список `contacts` ответа `LOGIN` с последним известным статусом.
///
/// Каждая подписка сразу получает последний загруженный список (если он есть) и затем свежий
/// из ядра. Список живёт только в памяти: `reset()` забывает его при выходе и смене аккаунта.
public actor CoreContactRepository: ContactRepository {
    private let core: any MaxCore
    private var cached: [Contact]?

    public init(core: any MaxCore) {
        self.core = core
    }

    public nonisolated var capabilities: ContactCapabilities { [.list, .presence] }

    public nonisolated func contacts() -> AsyncStream<[Contact]> {
        AsyncStream { continuation in
            let task = Task { await self.feed(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func reset() {
        cached = nil
    }

    private func feed(_ continuation: AsyncStream<[Contact]>.Continuation) async {
        if let cached { continuation.yield(cached) }
        do {
            let list = try await core.loadContacts().map { CoreMapping.contact($0) }
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

/// Журнал звонков из ядра (`VIDEO_CHAT_HISTORY`). Устроен как `CoreContactRepository`.
public actor CoreCallHistoryRepository: CallHistoryRepository {
    private let core: any MaxCore
    private var cached: [CallRecord]?

    public init(core: any MaxCore) {
        self.core = core
    }

    public nonisolated var capabilities: CallCapabilities { [.history] }

    public nonisolated func calls() -> AsyncStream<[CallRecord]> {
        AsyncStream { continuation in
            let task = Task { await self.feed(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func reset() {
        cached = nil
    }

    private func feed(_ continuation: AsyncStream<[CallRecord]>.Continuation) async {
        if let cached { continuation.yield(cached) }
        do {
            let list = try await core.loadCallHistory().map(CoreMapping.call)
                .sorted { $0.date > $1.date }
            Log.info(.calls, "Звонков в журнале: \(list.count)")
            cached = list
            continuation.yield(list)
        } catch {
            Log.warning(.calls, "Журнал звонков не загрузился: \(error)")
            if cached == nil { continuation.yield([]) }
        }
        continuation.finish()
    }
}

/// Карточки чатов из ядра: собеседник, бот, группа или канал.
public struct CoreChatProfileRepository: ChatProfileRepository {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func profile(chatId: String) async throws(OrbitlError) -> ChatProfile {
        do {
            let profile = CoreMapping.profile(try await core.loadProfile(chatId: chatId))
            Log.info(.chats, "Карточка чата \(chatId): \(profile.kind.rawValue)")
            return profile
        } catch {
            Log.warning(.chats, "Карточка чата \(chatId) не загрузилась: \(error)")
            throw CoreMapping.apiError(error).orbitlError
        }
    }
}
