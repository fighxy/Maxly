import Foundation
import Observation
import OrbitlData
import OrbitlDomain

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

    private var session: SessionManager?
    private var chats: ChatRepositoryImpl?
    private var messages: MessageRepositoryImpl?
    private var sync: SyncEngine?
    private var authModel: AuthViewModel?
    private var listModel: ChatListViewModel?
    private var chatModels: [String: ChatViewModel] = [:]
    private var phaseTask: Task<Void, Never>?

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
                        self.chatModels.removeAll()
                        self.listModel = nil
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
        let model = ChatListViewModel(chats: chats)
        listModel = model
        return model
    }

    func chatViewModel(id: String) -> ChatViewModel? {
        if let existing = chatModels[id] { return existing }
        guard let messages else { return nil }
        let me: String
        if case .signedIn(let userId) = phase { me = userId } else { me = "" }
        let model = ChatViewModel(chatId: id, currentUserId: me, messages: messages)
        chatModels[id] = model
        return model
    }

    func focus(chatId: String?) async {
        await sync?.focus(chatId)
        if let chatId {
            try? await chats?.markAsRead(chatId: chatId)
        }
    }

    func logout() async {
        await session?.logout()
        chatModels.removeAll()
        listModel = nil
        authModel = nil
    }
}
