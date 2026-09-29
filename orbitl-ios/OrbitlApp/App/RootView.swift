import SwiftUI
import OrbitlDomain
import OrbitlPresentation

struct RootView: View {
    @Bindable var container: AppContainer
    @Bindable var router: AppRouter

    var body: some View {
        Group {
            switch container.boot {
            case .loading:
                ProgressView("Orbitl")
            case .failed(let message):
                ContentUnavailableView("Orbitl", systemImage: "externaldrive.badge.exclamationmark", description: Text(message))
            case .ready:
                switch container.phase {
                case .signedIn:
                    main
                case .restoring:
                    ProgressView("Подключение")
                default:
                    auth
                }
            }
        }
        .task { await container.bootstrap() }
        .task(id: router.chatId) { await container.focus(chatId: router.chatId) }
        .onOpenURL { url in router.open(DeepLink.parse(url)) }
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
        }
    }
}

/// Нижняя панель вкладок. На iOS 26 система рисует её плавающей стеклянной капсулой.
struct MainTabView: View {
    @Bindable var container: AppContainer
    @Bindable var router: AppRouter
    @Bindable var list: ChatListViewModel

    var body: some View {
        TabView(selection: $router.tab) {
            ForEach(AppTab.order, id: \.self) { tab in
                content(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
                    .badge(badge(for: tab))
            }
        }
    }

    private func badge(for tab: AppTab) -> Int {
        tab == .chats ? list.tabBadge : 0
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .chats:
            chats
        case .contacts:
            NavigationStack {
                ContentUnavailableView("Контакты", systemImage: "person.crop.circle", description: Text("Список контактов пока недоступен"))
                    .navigationTitle("Контакты")
            }
        case .calls:
            NavigationStack {
                ContentUnavailableView("Звонки", systemImage: "phone", description: Text("История звонков пока недоступна"))
                    .navigationTitle("Звонки")
            }
        case .settings:
            NavigationStack {
                SettingsView(container: container, list: list) {
                    // Открытый чат прежнего аккаунта не должен открыться после следующего входа.
                    router.chatId = nil
                    router.tab = .chats
                    Task { await container.logout() }
                }
            }
        }
    }

    private var chats: some View {
        NavigationSplitView {
            ChatListView(viewModel: list, selection: $router.chatId)
        } detail: {
            if let id = router.chatId, let model = container.chatViewModel(id: id) {
                // Свой экран на каждый чат: иначе при смене выбора SwiftUI переиспользует
                // прежний ChatView, его `.task` не перезапускается, и модель нового чата
                // так и не подписывается на сообщения.
                ChatView(viewModel: model, title: list.title(chatId: id))
                    .id(id)
                    .toolbar(.hidden, for: .tabBar)
            } else {
                ContentUnavailableView("Выберите чат", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }
}
