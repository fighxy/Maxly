import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

struct RootView: View {
    @Bindable var container: AppContainer
    @Bindable var router: AppRouter

    var body: some View {
        Group {
            if let report = container.crashReport {
                CrashReportView(container: container, report: report)
            } else {
                content
            }
        }
        // Размер текста, тема и обои чата из «Оформления» — на всё приложение, включая экран сбоя.
        .dynamicTypeSize(container.appearance.textSize.dynamicTypeSize)
        .background(InterfaceStyleOverride(theme: container.appearance.theme))
        .environment(\.chatWallpaper, container.appearance.wallpaper)
        .task { await container.bootstrap() }
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
            OrbitleSplash()
        case .failed(let message):
            ContentUnavailableView {
                Label {
                    Text("Orbitle не запустился")
                } icon: {
                    OrbitleMark(size: 72)
                }
            } description: {
                Text(message)
            }
        case .ready:
            switch container.phase {
            case .signedIn:
                main
            case .restoring:
                OrbitleSplash(caption: "Подключение…")
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
                .sheet(isPresented: $container.showsNewSessionNotice) {
                    NewSessionNoticeSheet()
                }
        }
    }
}

/// Нижняя панель вкладок. На iOS 26 система рисует её плавающей стеклянной капсулой.
struct MainTabView: View {
    @Bindable var container: AppContainer
    @Bindable var router: AppRouter
    @Bindable var list: ChatListViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

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
        // Приватный режим: вид для строк и пузырей, а сама настройка — для кнопок-переключателей.
        .environment(\.privateMode, container.privateMode.display)
        .environment(container.privateMode)
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
            switch phase {
            case .active:
                // Звонки могли пропустить или удалить на другом устройстве, пока приложение спало.
                let visible = router.tab == .calls
                Task {
                    if visible { await calls.appeared() } else { await calls.refresh() }
                }
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
                CallsView(viewModel: container.callsViewModel()) { chatId in
                    router.openChat(chatId)
                }
            }
        case .settings:
            NavigationStack {
                SettingsView(
                    container: container,
                    account: container.accountSettingsModel(),
                    list: list,
                    onOpenChat: { id in router.openChat(id) },
                    // Выделение в панели вкладок переезжает плавно, как при нажатии.
                    onOpenContacts: { withAnimation(OrbitleMotion.quick(reduceMotion: OrbitleMotion.systemReducesMotion)) { router.tab = .contacts } },
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

    /// Группа и канал уже в списке. Личный диалог ещё запоминается, чтобы шапка знала имя.
    private func openCreated(_ opened: NewChatOpened) {
        if let draft = opened.draft { container.openDialog(draft) }
        router.chatId = opened.id
    }

    @ViewBuilder
    private var chats: some View {
        if sizeClass == .compact {
            // iPhone: обычный стек. Чат прячет панель вкладок сам, и система анимирует её
            // вместе с переходом, в том числе при свайпе назад.
            NavigationStack(path: chatPath) {
                ChatListView(viewModel: list, selection: $router.chatId, newChat: container.newChatModel(), onOpened: openCreated)
                    .navigationDestination(for: String.self) { id in
                        chatScreen(id)
                    }
            }
        } else {
            NavigationSplitView {
                ChatListView(viewModel: list, selection: $router.chatId, newChat: container.newChatModel(), onOpened: openCreated)
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
                            OrbitleMark(size: 72)
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

    @ViewBuilder
    private func chatScreen(_ id: String) -> some View {
        if let model = container.chatViewModel(id: id) {
            // Свой экран на каждый чат: иначе при смене выбора SwiftUI переиспользует
            // прежний ChatView, его `.task` не перезапускается, и модель нового чата
            // так и не подписывается на сообщения.
            let settings = container.accountSettingsModel().settings
            ChatView(
                viewModel: model,
                title: container.chatTitle(id: id),
                commentsEnabled: container.commentsEnabled(id: id),
                chatType: container.chatType(id: id),
                forwardTargets: { container.forwardTargets(excluding: id) },
                canWrite: container.canWrite(id: id),
                isMuted: container.isMuted(id: id),
                onToggleMute: { Task { await container.toggleMute(id: id) } },
                contactList: { container.attachmentContacts() },
                stickerPanel: container.stickerPanelModel(),
                live: { container.headerLive(id: id) },
                makeProfile: { container.profileViewModel(chatId: id) },
                onEraseChat: { clear, everyone in
                    Task {
                        let gone = await container.eraseChat(id: id, clearHistory: clear, forEveryone: everyone)
                        if gone { router.chatId = nil }
                    }
                },
                quickReaction: settings.quickReactionEnabled ? settings.quickReaction : nil
            )
            .id(id)
        }
    }
}
