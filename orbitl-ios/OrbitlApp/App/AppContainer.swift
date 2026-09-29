import Foundation
import Observation
import OrbitlData
import OrbitlDomain
import OrbitlPresentation
import OrbitlUI

/// Собирает ядро, базу и репозитории. Экраны получают только протоколы.
@MainActor
@Observable
final class AppContainer {
    enum Boot: Equatable {
        case loading
        case failed(String)
        case ready
    }

    private(set) var boot: Boot = .loading
    private(set) var phase: AuthPhase = .restoring

    // Зависимости и кэш моделей экранов не наблюдаются: модели создаются лениво прямо
    // во время отрисовки `RootView`, и запись в наблюдаемое свойство там заставила бы
    // SwiftUI перерисовывать экран ещё раз. Экран следит только за `boot` и `phase`.
    @ObservationIgnored private var session: SessionManager?
    @ObservationIgnored private var chats: ChatRepositoryImpl?
    @ObservationIgnored private var messages: MessageRepositoryImpl?
    @ObservationIgnored private var sync: SyncEngine?
    private let recentSearches = RecentSearchesStore()
    @ObservationIgnored private var authModel: AuthViewModel?
    @ObservationIgnored private var listModel: ChatListViewModel?
    @ObservationIgnored private var chatModels: [String: ChatViewModel] = [:]
    @ObservationIgnored private var phaseTask: Task<Void, Never>?

    func bootstrap() async {
        guard boot == .loading else { return }
        do {
            let stack = try SwiftDataStack()
            let core = MaxIosCore()
            let api = MaxAPIClient(core: core)
            let chats = ChatRepositoryImpl.make(stack: stack, api: api)
            let messages = MessageRepositoryImpl.make(stack: stack, api: api)
            let outbox = OutboxQueue(api: api)
            await messages.attach(outbox: outbox)
            let media = MediaRepositoryImpl(http: URLSessionClient(), directory: try MediaRepositoryImpl.defaultDirectory())
            let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages)
            await sync.connectOutgoing()
            let session = SessionManager(
                core: core,
                stack: stack,
                chats: chats,
                messages: messages,
                sync: sync,
                media: media
            )
            self.session = session
            self.chats = chats
            self.messages = messages
            self.sync = sync
            boot = .ready
            phaseTask = Task {
                for await next in session.phases() {
                    self.phase = next
                    if case .signedOut = next {
                        self.dropScreenModels()
                    }
                }
            }
            await session.restoreSession()
        } catch {
            boot = .failed("Не удалось открыть локальную базу")
        }
    }

    func authViewModel() -> AuthViewModel? {
        guard let session else { return nil }
        if let authModel { return authModel }
        let model = AuthViewModel(auth: session)
        authModel = model
        return model
    }

    func chatListViewModel() -> ChatListViewModel? {
        guard let chats else { return nil }
        if let listModel { return listModel }
        let model = ChatListViewModel(chats: chats, connection: session, recentSearches: recentSearches)
        model.usesLocalFilters = UserDefaults.standard.bool(forKey: Self.localFiltersKey)
        listModel = model
        return model
    }

    func chatViewModel(id: String) -> ChatViewModel? {
        if let existing = chatModels[id] { return existing }
        guard let messages else { return nil }
        let me: String
        if case .signedIn(let userId) = phase { me = userId } else { me = "" }
        let model = ChatViewModel(chatId: id, currentUserId: me, messages: messages, drafts: chats)
        chatModels[id] = model
        return model
    }

    static let localFiltersKey = "orbitl.chatList.localFilters"

    /// Папки по типам чатов, когда серверных нет. Настройка живёт на устройстве.
    func setLocalFilters(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.localFiltersKey)
        listModel?.usesLocalFilters = enabled
    }

    var currentUserId: String {
        if case .signedIn(let userId) = phase { return userId }
        return ""
    }

    /// Открытый чат: опрос его истории и отметка прочтения, в том числе для сообщений,
    /// пришедших, пока он на экране (это делает `ChatListViewModel`).
    func focus(chatId: String?) async {
        await sync?.focus(chatId)
        await listModel?.open(chatId: chatId)
    }

    func logout() async {
        await session?.logout()
        await recentSearches.clear()
        await ImagePipeline.shared.removeAll()
        dropScreenModels()
        authModel?.deactivate()
        authModel = nil
    }

    /// Модели экранов прежнего аккаунта не должны пережить выход.
    private func dropScreenModels() {
        chatModels.values.forEach { $0.deactivate() }
        chatModels.removeAll()
        listModel?.deactivate()
        listModel = nil
    }
}
