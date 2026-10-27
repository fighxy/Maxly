import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

struct RootView: View {
    @Bindable var container: AppContainer
    @Bindable var router: AppRouter
    @AppStorage(GifAutoplayMode.storageKey) private var gifAutoplayMode = GifAutoplayMode.defaultMode.rawValue
    private let network = NetworkKindMonitor.shared

    /// Шрифт, толщина и размер текста одной строкой: меняется — экраны получают новый шрифт.
    private var typographyKey: String {
        let appearance = container.appearance
        return "\(appearance.font.rawValue)-\(appearance.fontWeight)-\(appearance.textSize.rawValue)"
    }

    var body: some View {
        Group {
            if let report = container.crashReport {
                CrashReportView(container: container, report: report)
            } else {
                content
            }
        }
        // Размер текста, шрифт, тема и обои чата из «Оформления» — на всё приложение, включая экран сбоя.
        .font(.app(.body))
        .dynamicTypeSize(container.appearance.textSize.dynamicTypeSize)
        .onChange(of: typographyKey) {
            let appearance = container.appearance
            Typography.shared.apply(font: appearance.font, weight: appearance.fontWeight, textSize: appearance.textSize)
            NavigationBarFonts.apply()
        }
        .background(InterfaceStyleOverride(theme: container.appearance.theme))
        .environment(\.chatWallpaper, container.appearance.wallpaper)
        // Свои фото обоев: экран чата берёт обои чата или общие, профиль чата их меняет.
        .environment(container.wallpapers)
        .environment(\.imageURLSizing, CoreImageURLSizing())
        .environment(\.gifAutoplay, GifAutoplayPolicy.allows(
            GifAutoplayMode(stored: gifAutoplayMode), network: network.kind, constrained: network.constrained
        ))
        .task { await container.bootstrap() }
        // Нажатие на уведомление о сообщении (приложение было свёрнуто) открывает чат.
        .task {
            let router = self.router
            container.messageNotifier.onOpenChat = { router.openChat($0) }
        }
        .task(id: router.chatId) { await container.focus(chatId: router.chatId) }
        .onChange(of: container.phase) { old, phase in
            // Сессия истекла или вошёл другой аккаунт: открытый чат прежнего аккаунта
            // не должен открыться. Выход из настроек сбрасывает его сам.
            if phase == .expired { router.chatId = nil }
            if case .signedIn(let was) = old, case .signedIn(let now) = phase, was != now {
                router.chatId = nil
            }
        }
        .onOpenURL { url in router.open(DeepLink.parse(url)) }
    }

    @ViewBuilder
    private var content: some View {
        switch container.boot {
        case .loading:
            MaxlySplash()
        case .failed(let message):
            ContentUnavailableView {
                Label {
                    Text("Maxly не запустился")
                } icon: {
                    MaxlyMark(size: 72)
                }
            } description: {
                Text(message)
            }
        case .ready:
            switch container.phase {
            case .signedIn:
                main
            case .restoring:
                MaxlySplash(caption: "Подключение…")
            default:
                auth
            }
        }
    }

    @ViewBuilder
    private var auth: some View {
        if let model = container.authViewModel() {
            AuthView(viewModel: model)
        }
    }

    @ViewBuilder
    private var main: some View {
        if let list = container.chatListViewModel() {
            MainTabView(container: container, router: router, list: list)
                // Другой аккаунт — новые модели экранов, и их `.task` должны запуститься заново.
                .id(container.currentUserId)
                // Ограничения после входа: один раз, и после перезапуска тоже, если панель не успели увидеть.
                .sheet(isPresented: Binding(
                    get: { container.accountLimits.pendingNotice(now: Date()) != nil },
                    set: { if !$0 { container.accountLimits.markShown() } }
                )) {
                    if let limits = container.accountLimits.limits {
                        AccountLimitsSheet(content: AccountLimitsText().content(limits, now: Date()))
                    }
                }
        }
    }
}

/// Сжатие нижней панели при прокрутке вниз (iOS 26, `tabBarMinimizeBehavior`). Сжатая панель
/// показывает кнопку текущей вкладки; раскрывают её прокрутка вверх или нажатие. Раньше iOS 26
/// панель не сжимается.
private struct TabBarMinimize: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(enabled ? .onScrollDown : .never)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Нижняя панель вкладок. На iOS 26 система рисует её плавающей стеклянной капсулой.
struct MainTabView: View {
    @Bindable var container: AppContainer
    @Bindable var router: AppRouter
    @Bindable var list: ChatListViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Новая история: системный выбор фото или видео (`StoriesHost`).
    @State private var pickingStory = false

    var body: some View {
        TabView(selection: $router.tab) {
            ForEach(AppTab.order, id: \.self) { tab in
                content(for: tab)
                    .toolbar(tabBarVisibility(for: tab), for: .tabBar)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
                    .badge(badge(for: tab))
            }
        }
        // iOS 26: прокрутка списка чатов вниз сжимает панель до кнопки вкладки, прокрутка вверх
        // или нажатие раскрывают её. Только во «Чатах» и только на iPhone.
        .modifier(TabBarMinimize(enabled: router.tab == .chats && sizeClass != .regular))
        // Приватный режим: вид для строк и пузырей, а сама настройка — для кнопок-переключателей.
        .environment(\.privateMode, container.privateMode.display)
        .environment(container.privateMode)
        .environment(container.addressBook)
        // Истории: кольца в списке, шапке чата и профиле, просмотр и публикация.
        .modifier(StoriesHost(stories: container.storiesViewModel(), picking: $pickingStory, afterStart: {
            let account = container.accountSettingsModel()
            if account.profile == nil { await account.reloadProfile() }
        }, onProfile: { chatId in router.openProfile(chatId: chatId) }))
        // Звонок поверх всего: полный экран или плашка свёрнутого (docs/calls.md).
        .modifier(CallHost(center: container.callCenter, onAnswer: { container.answerCall(video: $0) }))
        // Бейдж «Звонков» нужен и до первого открытия вкладки.
        .task {
            let calls = container.callsViewModel()
            calls.activate()
            container.accountSettingsModel().watchSettings()
            if router.tab == .calls { await calls.appeared() }
        }
        .onChange(of: router.tab) { _, tab in
            let calls = container.callsViewModel()
            if tab == .calls {
                Task { await calls.appeared() }
            } else {
                calls.disappeared()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            let calls = container.callsViewModel()
            // «В сети» решает сервер по флагу из `PING`: на экране — да, в фоне — нет.
            if phase == .active { container.setAppActive(true) }
            if phase == .background { container.setAppActive(false) }
            switch phase {
            case .active:
                // Звонки могли пропустить или удалить на другом устройстве, пока приложение спало.
                let visible = router.tab == .calls
                Task {
                    if visible { await calls.appeared() } else { await calls.refresh() }
                }
                // Пуши, пока приложение спало, могли потеряться: одна сверка вместо опроса по таймеру.
                Task { await container.appBecameActive() }
            case .background:
                calls.disappeared()
                container.trimStorage()
            default:
                break
            }
        }
    }

    /// Один владелец preference на стабильных корнях вкладок, без конкурирующих
    /// требований от списка и destination во время интерактивного push/pop.
    private func tabBarVisibility(for tab: AppTab) -> Visibility {
        guard sizeClass != .regular, tab == .chats else { return .visible }
        return router.chatId != nil || list.isEditing || list.isSearchActive ? .hidden : .visible
    }

    private func badge(for tab: AppTab) -> Int {
        switch tab {
        case .chats: list.tabBadge
        case .calls: container.callsViewModel().unseenMissedCount
        case .contacts, .settings: 0
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .chats:
            chats
        case .contacts:
            NavigationStack {
                ContactsView(
                    viewModel: container.contactsViewModel(),
                    makeProfile: { container.profileViewModel(dialog: $0) }
                ) { dialog in
                    container.openDialog(dialog)
                    router.openChat(dialog.chatId)
                }
            }
        case .calls:
            NavigationStack {
                CallsView(
                    viewModel: container.callsViewModel(),
                    onOpenChat: { chatId in router.openChat(chatId) },
                    onJoin: { link in container.joinCall(link: link) },
                    onCall: { row, video in
                        container.startCall(CallCenter.Peer(id: row.peerId, name: row.name, avatarURL: row.avatarURL), video: video)
                    }
                )
            }
        case .settings:
            NavigationStack {
                SettingsView(
                    container: container,
                    account: container.accountSettingsModel(),
                    list: list,
                    onOpenChat: { id in router.openChat(id) },
                    // Выделение в панели вкладок переезжает плавно, как при нажатии.
                    onOpenContacts: { withAnimation(MaxlyMotion.quick(reduceMotion: MaxlyMotion.systemReducesMotion)) { router.tab = .contacts } },
                    onLogout: {
                        // Открытый чат прежнего аккаунта не должен открыться после следующего входа.
                        router.chatId = nil
                        router.tab = .chats
                        Task { await container.logout() }
                    }
                )
            }
            // В настройках ничего не прячется: там включают и выключают сам режим.
            .environment(\.privateMode, .visible)
        }
    }

    /// Свой аватар для плитки «Ваша история».
    private var selfAvatar: ChatAvatar {
        let profile = container.accountSettingsModel().profile
        let name = [profile?.firstName ?? "", profile?.lastName ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return StoryText.avatar(id: profile?.id ?? container.currentUserId, name: name, url: profile?.avatarURL)
    }

    /// Группа и канал уже в списке. Личный диалог ещё запоминается, чтобы шапка знала имя.
    private func openCreated(_ opened: NewChatOpened) {
        if let draft = opened.draft { container.openDialog(draft) }
        router.chatId = opened.id
    }

    /// Сообщение из общего поиска: модель чата запоминает его, чат откроется на нём.
    private func openFound(_ message: ChatSearchMessage) {
        container.chatViewModel(id: message.chatId)?.openAt(messageId: message.messageId, at: message.date)
    }

    /// Плеер в списке чатов. Открытый чат показывает свой — в списке его тогда нет.
    private var listNowPlaying: VoiceNowPlaying? {
        router.chatId == nil ? container.nowPlaying : nil
    }

    /// Полоса «играет голосовое»: чат открывается на этом сообщении.
    private func openVoice(_ track: VoiceNowPlaying.Track) {
        container.chatViewModel(id: track.chatId)?.openAt(messageId: track.messageId, at: track.date)
        router.chatId = track.chatId
    }

    @ViewBuilder
    private var chats: some View {
        if sizeClass == .compact {
            // iPhone: обычный стек. Чат прячет панель вкладок сам, и система анимирует её
            // вместе с переходом, в том числе при свайпе назад.
            NavigationStack(path: chatPath) {
                ChatListView(
                    viewModel: list, selection: $router.chatId, newChat: container.newChatModel(), onOpened: openCreated,
                    onOpenMessage: openFound,
                    selfAvatar: selfAvatar, onAddStory: { pickingStory = true },
                    makeBotApp: { container.botAppModel($0) },
                    nowPlaying: listNowPlaying, onOpenVoice: { openVoice($0) },
                    makeFoldersModel: { container.foldersModel() }
                )
                .safeAreaInset(edge: .top, spacing: 0) { loginHoldBanner }
                    .navigationDestination(for: String.self) { id in
                        chatScreen(id)
                    }
            }
        } else {
            NavigationSplitView {
                ChatListView(
                    viewModel: list, selection: $router.chatId, newChat: container.newChatModel(), onOpened: openCreated,
                    onOpenMessage: openFound,
                    selfAvatar: selfAvatar, onAddStory: { pickingStory = true },
                    makeBotApp: { container.botAppModel($0) },
                    nowPlaying: listNowPlaying, onOpenVoice: { openVoice($0) },
                    makeFoldersModel: { container.foldersModel() }
                )
                .safeAreaInset(edge: .top, spacing: 0) { loginHoldBanner }
            } detail: {
                if let id = router.chatId {
                    // Свой стек у колонки: из чата открывается профиль.
                    NavigationStack { chatScreen(id) }
                        .id(id)
                } else {
                    ContentUnavailableView {
                        Label {
                            Text("Выберите чат")
                        } icon: {
                            MaxlyMark(size: 72)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    /// Путь стека на iPhone: открытый чат — единственный экран поверх списка.
    private var chatPath: Binding<[String]> {
        Binding(
            get: { router.chatId.map { [$0] } ?? [] },
            set: { router.chatId = $0.last }
        )
    }

    /// Входы экрана чата: данные из списка, службы и действия.
    private var chatFactory: ChatScreenFactory {
        ChatScreenFactory(container: container, router: router, openVoice: { openVoice($0) })
    }

    @ViewBuilder
    private func chatScreen(_ id: String) -> some View {
        if let model = container.chatViewModel(id: id) {
            // Свой экран на каждый чат: иначе при смене выбора SwiftUI переиспользует
            // прежний ChatView, его `.task` не перезапускается, и модель нового чата
            // так и не подписывается на сообщения.
            ChatView(viewModel: model, context: chatFactory.context(chatId: id))
                .id(id)
        }
    }

    @ViewBuilder
    private var loginHoldBanner: some View {
        if let notice = container.loginNotice, notice.place == .chatList {
            VStack(alignment: .leading, spacing: 8) {
                Text(notice.title)
                    .font(.app(.headline))
                if let message = notice.message, !message.isEmpty {
                    Text(message)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button("Повторить") {
                        Task { await container.retryHeldLogin() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Выйти из аккаунта", role: .destructive) {
                        router.chatId = nil
                        router.tab = .chats
                        Task { await container.logout() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .accessibilityElement(children: .contain)
        }
    }
}
