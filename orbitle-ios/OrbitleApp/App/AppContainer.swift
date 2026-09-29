import Foundation
import Observation
import OrbitleData
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

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
    @ObservationIgnored private var media: MediaRepositoryImpl?
    @ObservationIgnored private let voicePlayer = SystemVoicePlayer()
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
    // Свой аккаунт и серверные папки для «Настроек» (docs/settings.md).
    @ObservationIgnored private var accounts: any AccountRepository = UnavailableAccountRepository()
    @ObservationIgnored private var folderRepository: any FolderRepository = UnavailableFolderRepository()
    @ObservationIgnored private var accountModel: AccountSettingsModel?
    @ObservationIgnored private var securityModel: SecuritySettingsModel?
    @ObservationIgnored private var devicesScreenModel: DevicesModel?
    @ObservationIgnored private var foldersScreenModel: FoldersModel?
    @ObservationIgnored private var phaseTask: Task<Void, Never>?
    /// Журнал для отладки. `nil`, если каталог журнала не удалось открыть.
    let logs: FileLogStore?
    /// Архив отчётов о сбоях для «О приложении». `nil` без каталога журнала.
    let crashDumps: CrashDumpStore?
    /// Размер текста и тема: одни на устройство, выход из аккаунта их не трогает.
    let appearance: AppearanceSettings

    static let loggingKey = "orbitle.debug.logging"

    /// Отчёт о сбое прошлого запуска. Пока он есть, экран показывает его вместо запуска ядра.
    private(set) var crashReport: String?

    /// Бывший переключатель «Папки по типам чатов»: папки теперь только серверные.
    private static let retiredLocalFiltersKey = "orbitle.chatList.localFilters"

    init() {
        let enabled = UserDefaults.standard.object(forKey: Self.loggingKey) as? Bool ?? true
        let directory = try? FileLogStore.defaultDirectory()
        // Аварийный журнал включается первым: сбой при запуске тоже должен оставить отчёт.
        var pending: String?
        if let directory {
            CrashReporter.loadPreviousSignalReport(directory: directory)
            CrashReporter.install(directory: directory)
            pending = CrashReporter.pendingReport()
        }
        crashReport = pending
        let dumps = directory.map { CrashDumpStore(logsDirectory: $0) }
        // Отчёт остаётся в архиве и после «Продолжить запуск».
        if let pending { dumps?.save(pending) }
        crashDumps = dumps
        appearance = AppearanceSettings(store: UserDefaultsAppearanceStore())
        UserDefaults.standard.removeObject(forKey: Self.retiredLocalFiltersKey)
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
        return "Orbitle \(version) (\(build))"
    }

    /// `0.1.0 (1)` для настроек и «О приложении».
    static var versionNumber: String {
        appVersion.replacingOccurrences(of: "Orbitle ", with: "")
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
        // Ядро Kotlin впервые трогается здесь, а не в init: если сбой случается уже при его
        // запуске, экран прошлого сбоя всё равно откроется, не трогая ядро.
        MaxIosCore.installCrashHandler()
        Log.info(.app, "Обработчик сбоев ядра установлен")
        do {
            let stack = try SwiftDataStack()
            let core = MaxIosCore()
            Log.info(.app, "Ядро создано")
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
            self.accounts = CoreAccountRepository(core: core)
            self.folderRepository = CoreFolderRepository(core: core)
            self.session = session
            self.chats = chats
            self.messages = messages
            self.media = media
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

    /// Комментарии есть у постов канала.
    func allowsComments(id: String) -> Bool {
        listModel?.chat(id: id)?.type == .channel
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
        let model = ChatViewModel(
            chatId: id,
            currentUserId: me,
            messages: messages,
            drafts: chats,
            media: media,
            voice: voicePlayer,
            isNewDialog: isNew
        )
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
        let userId = currentUserId
        // Время просмотра вкладки и скрытые звонки у каждого аккаунта свои.
        let marks: any CallHistoryMarks
        if userId.isEmpty {
            marks = InMemoryCallHistoryMarks()
        } else {
            marks = UserDefaultsCallHistoryMarks(userId: userId)
        }
        let model = CallsViewModel(calls: calls, marks: marks)
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

    // MARK: Настройки

    /// Шапка и настройки аккаунта. Одна модель на вход: номер скрыт при каждом входе.
    func accountSettingsModel() -> AccountSettingsModel {
        if let accountModel { return accountModel }
        let model = AccountSettingsModel(repository: accounts)
        accountModel = model
        return model
    }

    func securitySettingsModel() -> SecuritySettingsModel {
        if let securityModel { return securityModel }
        let model = SecuritySettingsModel(repository: accounts)
        securityModel = model
        return model
    }

    /// Каждая смена почты начинается заново: шаги сервера живут в одном треке.
    func recoveryEmailFlow() -> RecoveryEmailFlow {
        RecoveryEmailFlow(repository: accounts)
    }

    func devicesModel() -> DevicesModel {
        if let devicesScreenModel { return devicesScreenModel }
        let model = DevicesModel(repository: accounts)
        devicesScreenModel = model
        return model
    }

    func foldersModel() -> FoldersModel {
        if let foldersScreenModel { return foldersScreenModel }
        let model = FoldersModel(repository: folderRepository)
        foldersScreenModel = model
        return model
    }

    /// Новый запуск мини-приложения на каждое открытие листа.
    func miniAppModel(_ kind: MiniApp.Kind) -> MiniAppModel {
        MiniAppModel(kind: kind, repository: accounts)
    }

    /// Строка «Контакты»: `CONTACTS_GET` и свежий список во вкладке. Ошибка не мешает переходу.
    func syncContacts() async {
        await contactsViewModel().sync()
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
        let userId = currentUserId
        await session?.logout()
        if !userId.isEmpty { UserDefaultsCallHistoryMarks.erase(userId: userId) }
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
        voicePlayer.stop()
        chatModels.values.forEach { $0.deactivate() }
        chatModels.removeAll()
        listModel?.deactivate()
        listModel = nil
        contactsModel?.deactivate()
        contactsModel = nil
        callsModel?.deactivate()
        callsModel = nil
        accountModel?.deactivate()
        accountModel = nil
        securityModel = nil
        devicesScreenModel = nil
        foldersScreenModel?.deactivate()
        foldersScreenModel = nil
    }
}
