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

    // Зависимости и кэш моделей экранов не наблюдаются: модели создаются лениво прямо
    // во время отрисовки `RootView`, и запись в наблюдаемое свойство там заставила бы
    // SwiftUI перерисовывать экран ещё раз. Экран следит только за `boot` и `phase`.
    @ObservationIgnored private var session: SessionManager?
    @ObservationIgnored private var chats: ChatRepositoryImpl?
    @ObservationIgnored private var messages: MessageRepositoryImpl?
    @ObservationIgnored private var media: MediaRepositoryImpl?
    /// Кэш медиа на устройстве: размеры, очистка и правила для «Данных и памяти».
    @ObservationIgnored private var storage: DeviceStorage?
    @ObservationIgnored private var storageScreenModel: StorageSettingsModel?
    @ObservationIgnored private var mediaLinks: CoreMediaLinkResolver?
    @ObservationIgnored private var commentsRepository: CoreCommentsRepository?
    @ObservationIgnored private let voicePlayer = SystemVoicePlayer()
    @ObservationIgnored private var sync: SyncEngine?
    private let recentSearches = RecentSearchesStore()
    @ObservationIgnored private var authModel: AuthViewModel?
    @ObservationIgnored private var listModel: ChatListViewModel?
    /// Карточки профилей на диске: шапка чата и профиль видны сразу.
    @ObservationIgnored private let profileCache = ChatProfileCache.standard()
    @ObservationIgnored private var chatModels: [String: ChatViewModel] = [:]
    /// Диалоги, открытые из контактов: по ним экран знает имя собеседника, пока чата нет в списке.
    @ObservationIgnored private var dialogDrafts: [String: DialogDraft] = [:]
    @ObservationIgnored private var contactsModel: ContactsViewModel?
    @ObservationIgnored private var newChat: NewChatModel?
    @ObservationIgnored private var callsModel: CallsViewModel?
    // Контакты и журнал звонков из ядра. До сборки зависимостей экраны видят «недоступно».
    @ObservationIgnored private var contacts: any ContactRepository = UnavailableContactRepository()
    @ObservationIgnored private var calls: any CallHistoryRepository = UnavailableCallHistoryRepository()
    @ObservationIgnored private var coreContacts: CoreContactRepository?
    @ObservationIgnored private var coreCalls: CoreCallHistoryRepository?
    @ObservationIgnored private var profiles: (any ChatProfileRepository)?
    /// Стикеры и анимодзи (docs/stickers.md); панель одна на все чаты: каталог грузится раз.
    @ObservationIgnored private var stickerRepository: CoreStickerRepository?
    @ObservationIgnored private let recentStickers = UserDefaultsRecentStickers()
    @ObservationIgnored private var stickerPanel: StickerPanelModel?
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
    /// Приватный режим: тоже настройка устройства, выход из аккаунта её не сбрасывает.
    let privateMode: PrivateModeSettings
    /// Ограничения нового сеанса: панель после входа и строка в настройках. Выход стирает отметку.
    let accountLimits: AccountLimitsSettings

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
        privateMode = PrivateModeSettings(store: UserDefaultsPrivateModeStore())
        accountLimits = AccountLimitsSettings(store: UserDefaultsAccountLimitsStore())
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
            // Адреса CDN (видео, файлы) выданы под Android-клиента ядра: без его User-Agent
            // сервер отвечает 400.
            MediaHTTP.userAgent = core.mediaUserAgent()
            let mediaSession = URLSessionConfiguration.default
            if let agent = MediaHTTP.userAgent { mediaSession.httpAdditionalHeaders = ["User-Agent": agent] }
            let layout = try StorageLayout.standard()
            let storage = Self.makeStorage(layout: layout)
            let media = MediaRepositoryImpl(
                http: URLSessionClient(configuration: mediaSession),
                layout: layout,
                onStored: { await storage.trimIfNeeded() }
            )
            self.storage = storage
            // Правила кэша (срок и предел) — при каждом запуске, в фоне.
            Task.detached(priority: .utility) { await storage.trim() }
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
            self.profiles = CoreChatProfileRepository(core: core, cache: self.profileCache)
            self.stickerRepository = CoreStickerRepository(core: core)
            self.accounts = CoreAccountRepository(core: core)
            self.folderRepository = CoreFolderRepository(core: core)
            self.session = session
            self.chats = chats
            self.messages = messages
            self.media = media
            self.mediaLinks = CoreMediaLinkResolver(core: core)
            self.commentsRepository = CoreCommentsRepository(core: core)
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
                        // Отметка относилась к прежнему сеансу. Истёкший токен её не стирает:
                        // следующий вход по коду всё равно заменит её новой.
                        if next == .signedOut { self.accountLimits.clear() }
                    case .signedIn(let id):
                        // Вход с шага кода, пароля или имени, а не восстановление: ограничения нового сеанса.
                        if let entry = previous.freshEntry {
                            self.accountLimits.grant(entry)
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

    /// Живые данные шапки чата: сеть, «печатает…», звук. Читаются из наблюдаемого списка,
    /// поэтому шапка обновляется сама.
    func headerLive(id: String) -> ChatHeaderLive {
        guard let list = listModel, let chat = list.chat(id: id) else { return ChatHeaderLive() }
        return ChatHeaderLive(
            isOnline: chat.isOnline,
            isMuted: chat.isMuted,
            isVerified: chat.isVerified,
            typingCount: list.typing[id]?.count ?? 0
        )
    }

    /// Панель эмодзи и стикеров под полем ввода.
    func stickerPanelModel() -> StickerPanelModel {
        if let stickerPanel { return stickerPanel }
        let model = StickerPanelModel(repository: stickerRepository, recents: recentStickers)
        stickerPanel = model
        return model
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
    /// Можно ли писать в чат. Если сервер не сказал: в канал — нет, в остальные — да.
    /// Новый диалог из контактов — да. `nil` — чата нет в списке (канал из поиска, группа
    /// по ссылке): экран чата решает по карточке, а не открывает поле ввода наугад.
    func canWrite(id: String) -> Bool? {
        guard let chat = listModel?.chat(id: id) else { return dialogDrafts[id] == nil ? nil : true }
        return chat.canWrite ?? (chat.type != .channel)
    }

    func isMuted(id: String) -> Bool {
        listModel?.chat(id: id)?.isMuted ?? false
    }

    func toggleMute(id: String) async {
        await listModel?.toggleMute(chatId: id)
    }

    /// Очистить переписку или удалить чат. `true` — чата больше нет, экран можно закрыть.
    func eraseChat(id: String, clearHistory: Bool, forEveryone: Bool) async -> Bool {
        if clearHistory {
            await listModel?.confirmClear(chatId: id, forEveryone: forEveryone)
            return false
        }
        return await listModel?.deleteNow(chatId: id, forEveryone: forEveryone) ?? false
    }

    /// Пометка «непрочитано» с сообщения. `true` — сервер принял её, чат можно закрывать.
    func markUnread(id: String, from date: Date) async -> Bool {
        await listModel?.markUnread(chatId: id, from: date) ?? false
    }

    /// Чаты для выбора при пересылке.
    /// Контакты для вкладки «Контакт» в листе вложений.
    func attachmentContacts() -> AsyncStream<[Contact]> {
        contacts.contacts()
    }

    func forwardTargets(excluding chatId: String) -> [ChatListItem] {
        listModel?.forwardTargets(excluding: chatId) ?? []
    }

    /// Тип открытого чата. Новый диалог из контактов — личный.
    func chatType(id: String) -> ChatType {
        listModel?.chat(id: id)?.type ?? .private
    }

    /// Комментарии канала по карточке с сервера. `nil`, если сервер не сказал.
    func commentsEnabled(id: String) -> Bool? {
        listModel?.chat(id: id)?.commentsEnabled
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
            links: mediaLinks,
            comments: commentsRepository,
            voice: voicePlayer,
            gallery: PhotoLibrarySaver(),
            isNewDialog: isNew,
            chats: chats
        )
        chatModels[id] = model
        return model
    }

    /// Лист «новое сообщение». Тот же на время сеанса. Список контактов поток отдаёт один раз,
    /// поэтому каждое открытие листа читает его заново.
    func newChatModel() -> NewChatModel? {
        guard let chats else { return nil }
        if let newChat { return newChat }
        let model = NewChatModel(contacts: contacts, chats: chats, currentUserId: currentUserId)
        newChat = model
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

    /// Каталог реакций для выбора быстрой. Пустой ответ сервера — запасной ряд.
    func reactionChoices() async -> [String] {
        let loaded = await messages?.reactionCatalog() ?? []
        var seen = Set<String>()
        let clean = loaded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return clean.isEmpty ? ReactionPalette.fallback : clean
    }

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

    /// Кэш: своя раскладка медиа, база сообщений отдельно, «Прочее» — подготовленные к
    /// отправке файлы (сутки после записи ещё нужны) и временные файлы старше часа.
    private static func makeStorage(layout: StorageLayout) -> DeviceStorage {
        let manager = FileManager.default
        var extras: [DeviceStorage.Extra] = []
        if let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            extras.append(.init(url: caches.appending(path: "Outgoing", directoryHint: .isDirectory), minimumAge: 86_400))
        }
        extras.append(.init(url: manager.temporaryDirectory, minimumAge: 3_600))
        let database = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Orbitle", directoryHint: .isDirectory)
        return DeviceStorage(layout: layout, database: database, extras: extras, includesSystemCache: true)
    }

    func storageModel() -> StorageSettingsModel? {
        guard let storage else { return nil }
        if let storageScreenModel { return storageScreenModel }
        let model = StorageSettingsModel(storage: storage) { categories in
            // Файлы фото стёрты: забыть и декодированные копии, иначе экран покажет старое.
            if categories.contains(.photos) { ImagePipeline.shared.removeMemory() }
        }
        storageScreenModel = model
        return model
    }

    /// Приложение ушло в фон: применить правила кэша.
    func trimStorage() {
        guard let storage else { return }
        Task.detached(priority: .utility) { await storage.trim() }
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
        // Непрочитанные до отметки прочтения: над первым из них лента ставит разделитель.
        if let chatId, let model = chatViewModel(id: chatId) {
            model.noteUnreadOnOpen(listModel?.chat(id: chatId)?.unreadCount ?? 0)
        }
        await sync?.focus(chatId)
        await listModel?.open(chatId: chatId)
    }

    /// Мини-приложение бота из чата: запуск по `WEB_APP_INIT_DATA` с ботом, чатом и параметром.
    func botAppModel(_ request: BotAppRequest) -> MiniAppModel {
        let accounts = accounts
        return MiniAppModel(title: request.title, repository: accounts) { () async throws(OrbitleError) -> MiniApp in
            try await accounts.launchBotApp(botId: request.botId, chatId: request.chatId, startParam: request.startParam)
        }
    }

    /// Приложение вернулось на экран: сверка с сервером того, что могло прийти без пушей.
    func appBecameActive() async {
        await sync?.appBecameActive()
    }

    func logout() async {
        let userId = currentUserId
        await session?.logout()
        if !userId.isEmpty { UserDefaultsCallHistoryMarks.erase(userId: userId) }
        await recentSearches.clear()
        await profileCache.removeAll()
        await stickerRepository?.removeAll()
        recentStickers.clear()
        LottieStore.shared.removeAll()
        stickerPanel = nil
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
        newChat = nil
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
