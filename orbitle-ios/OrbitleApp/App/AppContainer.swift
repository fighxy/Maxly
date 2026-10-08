import Contacts
import Foundation
import Observation
import OrbitleCallMedia
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
    /// Плашка «слишком много входов» над списком. Экран входа читает то же пояснение сам.
    private(set) var loginNotice: LoginNotice?

    // Зависимости и кэш моделей экранов не наблюдаются: модели создаются лениво прямо
    // во время отрисовки `RootView`, и запись в наблюдаемое свойство там заставила бы
    // SwiftUI перерисовывать экран ещё раз. Экран следит только за `boot` и `phase`.
    @ObservationIgnored private var session: SessionManager?
    @ObservationIgnored private var chats: ChatRepositoryImpl?
    /// Черновики устройства, сверенные с черновиками сервера.
    @ObservationIgnored private var draftStore: ServerSyncedDraftStore?
    @ObservationIgnored private var messages: MessageRepositoryImpl?
    @ObservationIgnored private var media: MediaRepositoryImpl?
    /// Кэш медиа на устройстве: размеры, очистка и правила для «Данных и памяти».
    @ObservationIgnored private var storage: DeviceStorage?
    @ObservationIgnored private var storageScreenModel: StorageSettingsModel?
    @ObservationIgnored private var mediaLinks: CoreMediaLinkResolver?
    @ObservationIgnored private var commentsRepository: CoreCommentsRepository?
    /// Истории: одна модель на список, шапку чата и профиль.
    @ObservationIgnored private var storiesRepository: CoreStoriesRepository?
    @ObservationIgnored private var storiesModel: StoriesViewModel?
    @ObservationIgnored private let voicePlayer = SystemVoicePlayer()
    @ObservationIgnored private var sync: SyncEngine?
    /// Пуши закрепов сообщений: в базу не пишутся, их слушает открытый чат.
    @ObservationIgnored private let pinHub = PinHub()
    @ObservationIgnored private let scheduledHub = ScheduledHub()
    private let recentSearches = RecentSearchesStore()
    @ObservationIgnored private var authModel: AuthViewModel?
    @ObservationIgnored private var listModel: ChatListViewModel?
    /// Карточки профилей на диске: шапка чата и профиль видны сразу.
    @ObservationIgnored private let profileCache = ChatProfileCache.standard()
    /// Статус «в сети» по id человека: пишут контакты и карточки, позже — пуш присутствия ядра.
    @ObservationIgnored let presence = PresenceStore()
    /// Статусы через ядро: `loadPresence` для видимых людей, ответы и события — в `presence`.
    @ObservationIgnored private var presenceService: CorePresenceService?
    /// Ядро для `setAppActive`: от него сервер решает, «в сети» ли аккаунт.
    @ObservationIgnored private var activityCore: (any MaxCore)?
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
    /// «Имена из адресной книги»: книга телефона в ядро, на сервер — ничего. До ядра пусто.
    private(set) var addressBook: AddressBookNamesSync?
    @ObservationIgnored private var addressBookObserver: (any NSObjectProtocol)?
    /// «Я печатаю» для всех чатов: порог 6 с на чат общий, сколько бы экранов ни открывалось.
    @ObservationIgnored private var typingReporter: TypingReporter?
    /// Управление группой и каналом. До входа ядра пусто.
    @ObservationIgnored private(set) var chatAdmin: (any ChatAdminRepository)?
    @ObservationIgnored private var coreCalls: CoreCallHistoryRepository?
    /// Звонки (docs/calls.md): один центр на приложение и системный экран звонка.
    @ObservationIgnored private(set) var callCenter: CallCenter?
    @ObservationIgnored private var callKit: CallKitController?
    @ObservationIgnored private var profiles: (any ChatProfileRepository)?
    @ObservationIgnored private var profileActions: (any ProfileActionsRepository)?
    /// Стикеры и анимодзи (docs/stickers.md); панель одна на все чаты: каталог грузится раз.
    @ObservationIgnored private var stickerRepository: CoreStickerRepository?
    @ObservationIgnored private let recentStickers = UserDefaultsRecentStickers()
    @ObservationIgnored private var stickerPanel: StickerPanelModel?
    // Свой аккаунт и серверные папки для «Настроек» (docs/settings.md).
    @ObservationIgnored private var accounts: any AccountRepository = UnavailableAccountRepository()
    @ObservationIgnored private var folderRepository: any FolderRepository = UnavailableFolderRepository()
    @ObservationIgnored private var accountModel: AccountSettingsModel?
    @ObservationIgnored private var securityModel: SecuritySettingsModel?
    /// Режим призрака и приватность MAX (docs/privacy.md): адаптер над мостом ядра. Флаги и
    /// настройки живут в ядре и на сервере, приложение их не хранит.
    @ObservationIgnored private var privacyAdapter: CoreGhostPrivacyControls?
    @ObservationIgnored private var ghostScreenModel: GhostSettingsModel?
    @ObservationIgnored private var privacyScreenModel: PrivacySettingsModel?
    /// Приложение на экране (`scenePhase`): шапка настроек спрашивает свой статус только так.
    @ObservationIgnored private var isAppForeground = true
    @ObservationIgnored private var devicesScreenModel: DevicesModel?
    @ObservationIgnored private var foldersScreenModel: FoldersModel?
    @ObservationIgnored private var phaseTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
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
        // Флаги режима призрака теперь в ядре: старые ключи `UserDefaults` убираются один раз.
        GhostDefaultsMigration.run()
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
            // Флаг photo-url-refresh на мост не выведен, по умолчанию он выключен.
            // Пока его нет, просроченные адреса не спрашиваем.
            let sizing = CoreImageURLSizing()
            await messages.setPhotoURLRefresh(enabled: false, expired: sizing.isExpired)
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
            await sync.attachPins(pinHub)
            await sync.attachScheduled(scheduledHub)
            await sync.connectOutgoing()
            let session = SessionManager(
                core: core,
                stack: stack,
                chats: chats,
                messages: messages,
                sync: sync,
                media: media
            )
            let coreContacts = CoreContactRepository(core: core, presence: self.presence)
            self.presenceService = CorePresenceService(core: core, store: self.presence)
            self.activityCore = core
            let coreCalls = CoreCallHistoryRepository(core: core)
            typingReporter = TypingReporter(sender: CoreTypingSender(core: core))
            // Правило имён ядра живёт до перезапуска: задаётся при каждом старте.
            await core.setPreferAddressBookNames(Self.prefersAddressBookNames)
            let addressBook = AddressBookNamesSync(read: { await AddressBookReader.read() }, send: AddressBookReader.sender(core: core))
            self.addressBook = addressBook
            // Книга изменилась — ядро получает её заново целиком.
            addressBookObserver = NotificationCenter.default.addObserver(
                forName: .CNContactStoreDidChange, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in await addressBook.refresh() }
            }
            self.coreContacts = coreContacts
            self.coreCalls = coreCalls
            self.contacts = coreContacts
            self.calls = coreCalls
            let callKit = CallKitController()
            let directory = CallPeerDirectory(core: core)
            let center = CallCenter(
                service: CoreCallService(core: core),
                engine: SessionCallEngine { WebRTCCallMedia() },
                system: callKit,
                lookup: { await directory.peer($0) }
            )
            // Сервер кладёт звонок в журнал чуть позже конца разговора.
            center.onCallEnded = { [weak self] in
                guard let calls = self?.callsModel else { return }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await calls.refresh()
                }
            }
            self.callKit = callKit
            self.callCenter = center
            self.profiles = CoreChatProfileRepository(core: core, cache: self.profileCache, presence: self.presence)
            self.profileActions = CoreProfileActions(core: core)
            self.chatAdmin = CoreChatAdminRepository(core: core)
            self.stickerRepository = CoreStickerRepository(core: core)
            self.accounts = CoreAccountRepository(core: core)
            let privacyAdapter = CoreGhostPrivacyControls(core: core)
            self.privacyAdapter = privacyAdapter
            // Своя позиция чата для разделителя непрочитанных учитывает местную отметку ядра,
            // пока отметки о прочтении скрыты (docs/read-marks.md).
            chats.setLocalReadMarks { privacyAdapter.localReadMark(chatId: $0) }
            self.folderRepository = CoreFolderRepository(core: core)
            self.session = session
            self.chats = chats
            let draftStore = ServerSyncedDraftStore(local: chats, core: core)
            self.draftStore = draftStore
            // Черновики с других устройств (события `draft`) — в базу и в открытое поле.
            await sync.attachDrafts(draftStore)
            // Статусы людей: события `presence` и ответы `loadPresence` — в общий `presence`.
            await sync.attachPresence(self.presence)
            await core.setAppActive(true)
            self.messages = messages
            self.media = media
            self.mediaLinks = CoreMediaLinkResolver(core: core)
            self.commentsRepository = CoreCommentsRepository(core: core)
            self.storiesRepository = CoreStoriesRepository(core: core)
            self.sync = sync
            boot = .ready
            phaseTask = Task {
                for await next in session.phases() {
                    let previous = self.phase
                    self.phase = next
                    Log.info(.auth, "Фаза входа: \(Self.describe(next))")
                    switch next {
                    case .signedOut, .expired:
                        await self.callCenter?.deactivate()
                        self.dropScreenModels()
                        // Сессия закончилась: ограничения прежнего входа больше не действуют.
                        self.accountLimits.clear()
                    case .signedIn(let id):
                        // Вход с шага кода, пароля или имени, а не восстановление: ограничения нового сеанса.
                        if let entry = previous.freshEntry {
                            self.accountLimits.grant(entry)
                        }
                        // Кэш показывался под запомненным id, а ядро вошло другим аккаунтом
                        // (или вход после истёкшей сессии): модели чатов помнят прежнего автора.
                        if case .signedIn(let old) = previous, old != id {
                            await self.callCenter?.deactivate()
                            self.dropScreenModels()
                        }
                        self.callCenter?.activate()
                        // Ядро забывает книгу при выходе: после входа — снова.
                        await self.addressBook?.refresh()
                    default:
                        break
                    }
                }
            }
            noticeTask = Task {
                for await next in session.loginNotices() {
                    self.loginNotice = next
                }
            }
            connectionTask = Task {
                var wasOnline = false
                var previous: ConnectionState?
                for await state in session.connectionStates() {
                    defer { previous = state }
                    guard state == .online else { continue }
                    // Связь вернулась после обрыва (чаще всего приложение проснулось, а iOS успела
                    // закрыть сокет): журнал звонков и лента историй, запрошенные в этот момент, не
                    // загрузились. Первое подключение их грузит само.
                    if wasOnline, previous != .online { self.refreshAfterReconnect() }
                    wasOnline = true
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

    /// Лента историй, кольца и просмотр. `nil`, пока зависимости не собраны.
    func storiesViewModel() -> StoriesViewModel? {
        guard let storiesRepository else { return nil }
        if let storiesModel { return storiesModel }
        let model = StoriesViewModel(repository: storiesRepository)
        storiesModel = model
        return model
    }

    func chatListViewModel() -> ChatListViewModel? {
        guard let chats else { return nil }
        if let listModel { return listModel }
        let model = ChatListViewModel(chats: chats, connection: session, recentSearches: recentSearches)
        model.presence = presenceService
        model.currentUserId = currentUserId
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
            repository: profiles,
            actions: profileActions,
            presence: presenceService
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
            typing: list.typingParticipants(chatId: id)
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
            repository: profiles,
            actions: profileActions,
            presence: presenceService
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

    /// Выйти из группы или отписаться от канала. `true` — чата больше нет, экран можно закрыть.
    func leaveChat(id: String) async -> Bool {
        await listModel?.leave(chatId: id) ?? false
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
        let draftSource: (any ChatDraftStore)? = if let draftStore { draftStore } else { chats }
        let model = ChatViewModel(
            chatId: id,
            currentUserId: me,
            messages: messages,
            drafts: draftSource,
            media: media,
            links: mediaLinks,
            comments: commentsRepository,
            voice: voicePlayer,
            gallery: PhotoLibrarySaver(),
            isNewDialog: isNew,
            chats: chats
        )
        model.typingReporter = typingReporter
        model.attachPins(pinHub)
        model.attachScheduled(scheduledHub)
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
        let model = ContactsViewModel(contacts: contacts, currentUserId: currentUserId, presence: presenceService)
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

    /// До сборки зависимостей экранов приватности нет; на всякий случай — пустая реализация.
    private func ghostControls() -> any GhostControls {
        privacyAdapter ?? UnavailablePrivacyControls()
    }

    private func privacyControls() -> any PrivacyControls {
        privacyAdapter ?? UnavailablePrivacyControls()
    }

    /// «Дополнительно» в «Безопасности» и свой статус в шапке настроек. Одна модель на вход.
    func ghostSettingsModel() -> GhostSettingsModel {
        if let ghostScreenModel { return ghostScreenModel }
        let model = GhostSettingsModel(
            controls: ghostControls(),
            store: UserDefaultsSelfCheckStore(),
            isAppForeground: isAppForeground
        )
        model.activate()
        ghostScreenModel = model
        return model
    }

    /// Безопасный режим и строки приватности MAX.
    func privacySettingsModel() -> PrivacySettingsModel {
        if let privacyScreenModel { return privacyScreenModel }
        let model = PrivacySettingsModel(controls: privacyControls())
        privacyScreenModel = model
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

    /// Открытый чат: опрос его истории. Прочитанным его отмечает экран чата по тому, что
    /// видно (`ChatViewModel.noteVisible`, docs/read-marks.md).
    func focus(chatId: String?) async {
        // Непрочитанные и своя отметка прочтения до отметки этого захода: по ним лента ставит
        // разделитель. Отметка — самая свежая из ответа сервера, пуша и местной (`OwnReadMark`).
        if let chatId, let model = chatViewModel(id: chatId) {
            model.noteUnreadOnOpen(
                listModel?.chat(id: chatId)?.unreadCount ?? 0,
                ownReadMark: chats?.ownReadMark(chatId: chatId) ?? 0
            )
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

    // MARK: Звонки

    /// Позвонить пользователю: сначала разрешение на микрофон.
    func startCall(_ peer: CallCenter.Peer, video: Bool) {
        guard let center = callCenter else { return }
        Task {
            guard await CallPermissions.microphone() else {
                center.showError(CallPermissions.microphoneDenied)
                return
            }
            await center.startCall(to: peer, video: video)
        }
    }

    /// Войти в групповой звонок по ссылке.
    func joinCall(link: String) {
        guard let center = callCenter else { return }
        Task {
            guard await CallPermissions.microphone() else {
                center.showError(CallPermissions.microphoneDenied)
                return
            }
            await center.join(link: link)
        }
    }

    /// Ответить на входящий.
    func answerCall(video: Bool) {
        guard let center = callCenter else { return }
        Task {
            guard await CallPermissions.microphone() else {
                center.showError(CallPermissions.microphoneDenied)
                await center.decline()
                return
            }
            await center.answer(video: video)
        }
    }

    /// Имя из адресной книги важнее своего имени контакта (`preferAddressBookNames` ядра).
    /// Так по умолчанию; ключ настроек позволит поменять правило без новой сборки.
    static var prefersAddressBookNames: Bool {
        UserDefaults.standard.object(forKey: "preferAddressBookNames") as? Bool ?? true
    }

    /// Приложение вернулось на экран: сверка с сервером того, что могло прийти без пушей.
    /// Приложение на экране или в фоне (`scenePhase`): ядро передаёт это серверу в `PING`.
    func setAppActive(_ active: Bool) {
        isAppForeground = active
        ghostScreenModel?.setAppForeground(active)
        guard let core = activityCore else { return }
        Task { await core.setAppActive(active) }
    }

    func appBecameActive() async {
        await sync?.appBecameActive()
        // Разрешение на контакты могли выдать или забрать в настройках.
        if case .signedIn = phase { await addressBook?.refresh() }
    }

    /// После переподключения: журнал звонков и лента историй заново (список чатов и открытый чат
    /// сверяет `SyncEngine`).
    private func refreshAfterReconnect() {
        guard case .signedIn = phase else { return }
        if let callsModel { Task { await callsModel.refresh() } }
        if let storiesModel { Task { await storiesModel.refresh() } }
    }

    func retryHeldLogin() async {
        await session?.retryHeldLogin()
    }

    func logout() async {
        let userId = currentUserId
        await session?.logout()
        if !userId.isEmpty { UserDefaultsCallHistoryMarks.erase(userId: userId) }
        await recentSearches.clear()
        await profileCache.removeAll()
        await presence.removeAll()
        await presenceService?.reset()
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
        storiesModel?.stop()
        storiesModel = nil
        let contacts = coreContacts
        let calls = coreCalls
        let actions = profileActions as? CoreProfileActions
        Task {
            await contacts?.reset()
            await calls?.reset()
            await actions?.reset()
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
        ghostScreenModel?.deactivate()
        ghostScreenModel = nil
        privacyScreenModel?.deactivate()
        privacyScreenModel = nil
        devicesScreenModel = nil
        foldersScreenModel?.deactivate()
        foldersScreenModel = nil
    }
}
