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
    /// Только что вошли по коду (не восстановили сессию): экран показывает ограничения нового сеанса.
    var showsNewSessionNotice = false

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
    /// Диалоги, открытые из контактов: по ним экран знает имя собеседника, пока чата нет в списке.
    @ObservationIgnored private var dialogDrafts: [String: DialogDraft] = [:]
    @ObservationIgnored private var contactsModel: ContactsViewModel?
    @ObservationIgnored private var callsModel: CallsViewModel?
    // Контакты и журнал звонков из ядра. До сборки зависимостей экраны видят «недоступно».
    @ObservationIgnored private var contacts: any ContactRepository = UnavailableContactRepository()
    @ObservationIgnored private var calls: any CallHistoryRepository = UnavailableCallHistoryRepository()
    @ObservationIgnored private var coreContacts: CoreContactRepository?
    @ObservationIgnored private var coreCalls: CoreCallHistoryRepository?
    @ObservationIgnored private var profiles: (any ChatProfileRepository)?
    @ObservationIgnored private var phaseTask: Task<Void, Never>?
    /// Журнал для отладки. `nil`, если каталог журнала не удалось открыть.
    let logs: FileLogStore?

    static let loggingKey = "orbitl.debug.logging"

    /// Отчёт о сбое прошлого запуска. Пока он есть, экран показывает его вместо запуска ядра.
    private(set) var crashReport: String?

    init() {
        let enabled = UserDefaults.standard.object(forKey: Self.loggingKey) as? Bool ?? true
        let directory = try? FileLogStore.defaultDirectory()
        // Аварийный журнал включается первым: сбой при запуске тоже должен оставить отчёт.
        if let directory {
            CrashReporter.loadPreviousSignalReport(directory: directory)
            CrashReporter.install(directory: directory)
            crashReport = CrashReporter.pendingReport()
        }
        MaxIosCore.installCrashHandler()
        logs = directory.map { FileLogStore(directory: $0, enabled: enabled) }
        if let logs { Log.sink = logs.sink }
        Log.info(.app, "Запуск: \(Self.appVersion), \(ProcessInfo.processInfo.operatingSystemVersionString)")
        if let crashReport {
            Log.error(.app, "Прошлый запуск завершился сбоем:\n\(crashReport)")
        }
    }

    /// Отчёт показан: забыть его и запустить приложение как обычно.
    func continueAfterCrash() async {
        CrashReporter.clearPendingReport()
        crashReport = nil
        await bootstrap()
    }

    /// `1.0 (7)` из Info.plist.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Orbitl \(version) (\(build))"
    }

    /// Писать журнал в файлы. Настройка живёт на устройстве.
    func setLogging(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.loggingKey)
        Log.info(.app, "Запись журнала: \(enabled ? "включена" : "выключена")")
        logs?.isEnabled = enabled
    }

    func bootstrap() async {
        guard boot == .loading, crashReport == nil else { return }
        Log.info(.app, "Подготовка базы и ядра")
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
            let coreContacts = CoreContactRepository(core: core)
            let coreCalls = CoreCallHistoryRepository(core: core)
            self.coreContacts = coreContacts
            self.coreCalls = coreCalls
            self.contacts = coreContacts
            self.calls = coreCalls
            self.profiles = CoreChatProfileRepository(core: core)
            self.session = session
            self.chats = chats
            self.messages = messages
            self.sync = sync
            boot = .ready
            phaseTask = Task {
                for await next in session.phases() {
                    let previous = self.phase
                    self.phase = next
                    Log.info(.auth, "Фаза входа: \(Self.describe(next))")
                    switch next {
                    case .signedOut, .expired:
                        self.dropScreenModels()
                    case .signedIn(let id):
                        if Self.isLoginStep(previous) {
                            Log.info(.auth, "Новый сеанс на этом устройстве")
                            self.showsNewSessionNotice = true
                        }
                        // Кэш показывался под запомненным id, а ядро вошло другим аккаунтом
                        // (или вход после истёкшей сессии): модели чатов помнят прежнего автора.
                        if case .signedIn(let old) = previous, old != id {
                            self.dropScreenModels()
                        }
                    default:
                        break
                    }
                }
            }
            await session.restoreSession()
        } catch {
            Log.error(.app, "Не удалось открыть локальную базу: \(error)")
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

    /// Диалог с контактом: существующий открывается как есть, новый запоминается, чтобы
    /// после первого сообщения сразу появиться в списке.
    func openDialog(_ draft: DialogDraft) {
        let known = listModel?.chat(id: draft.chatId) != nil
        Log.info(.chats, "Диалог с контактом \(draft.peerId): \(known ? "уже есть" : "новый")")
        guard !known else { return }
        dialogDrafts[draft.chatId] = draft
        let chats = chats
        Task { await chats?.prepareDialog(draft) }
    }

    /// Профиль чата. Шапка сразу берётся из списка чатов или из черновика диалога.
    func profileViewModel(chatId: String) -> ChatProfileViewModel? {
        guard let profiles else { return nil }
        let chat = listModel?.chat(id: chatId)
        let kind: ChatProfile.Kind?
        switch chat?.type {
        case .private?: kind = chat?.isBot == true ? .bot : .user
        case .group?: kind = .group
        case .channel?: kind = .channel
        case nil: kind = dialogDrafts[chatId] == nil ? nil : .user
        }
        return ChatProfileViewModel(
            chatId: chatId,
            title: chatTitle(id: chatId),
            avatarURL: chat?.avatarURL ?? dialogDrafts[chatId]?.avatarURL,
            kind: kind,
            repository: profiles
        )
    }

    /// Профиль контакта из вкладки «Контакты»: до открытия диалога его может не быть в списке.
    func profileViewModel(dialog: DialogDraft) -> ChatProfileViewModel? {
        guard let profiles else { return nil }
        return ChatProfileViewModel(
            chatId: dialog.chatId,
            title: dialog.title,
            avatarURL: dialog.avatarURL,
            kind: .user,
            repository: profiles
        )
    }

    /// Заголовок экрана чата: из списка, а для нового диалога — имя контакта.
    func chatTitle(id: String) -> String {
        if listModel?.chat(id: id) == nil, let draft = dialogDrafts[id] { return draft.title }
        return listModel?.title(chatId: id) ?? "Чат"
    }

    func chatViewModel(id: String) -> ChatViewModel? {
        if let existing = chatModels[id] { return existing }
        guard let messages else { return nil }
        let me: String
        if case .signedIn(let userId) = phase { me = userId } else { me = "" }
        let isNew = dialogDrafts[id] != nil && listModel?.chat(id: id) == nil
        let model = ChatViewModel(chatId: id, currentUserId: me, messages: messages, drafts: chats, isNewDialog: isNew)
        chatModels[id] = model
        return model
    }

    func contactsViewModel() -> ContactsViewModel {
        if let contactsModel { return contactsModel }
        let model = ContactsViewModel(contacts: contacts, currentUserId: currentUserId)
        contactsModel = model
        return model
    }

    func callsViewModel() -> CallsViewModel {
        if let callsModel { return callsModel }
        let model = CallsViewModel(calls: calls)
        callsModel = model
        return model
    }

    /// Шаг входа по коду: из него `signedIn` значит новый сеанс, а не восстановление.
    static func isLoginStep(_ phase: AuthPhase) -> Bool {
        switch phase {
        case .codeSent, .password, .registration: true
        case .restoring, .signedOut, .signedIn, .expired: false
        }
    }

    /// Фаза для журнала: без номера и прочих личных данных.
    static func describe(_ phase: AuthPhase) -> String {
        switch phase {
        case .restoring: "restoring"
        case .signedOut: "signedOut"
        case .codeSent(let length): "codeSent(length: \(length.map { String($0) } ?? "nil"))"
        case .password: "password"
        case .registration: "registration"
        case .signedIn(let id): "signedIn(\(id))"
        case .expired: "expired"
        }
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
        dialogDrafts.removeAll()
        let contacts = coreContacts
        let calls = coreCalls
        Task {
            await contacts?.reset()
            await calls?.reset()
        }
        chatModels.values.forEach { $0.deactivate() }
        chatModels.removeAll()
        listModel?.deactivate()
        listModel = nil
        contactsModel?.deactivate()
        contactsModel = nil
        callsModel?.deactivate()
        callsModel = nil
    }
}
