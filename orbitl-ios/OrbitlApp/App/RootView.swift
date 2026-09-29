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
            NavigationSplitView {
                ChatListView(viewModel: list, selection: $router.chatId) {
                    Task { await container.logout() }
                }
            } detail: {
                if let id = router.chatId, let model = container.chatViewModel(id: id) {
                    ChatView(viewModel: model, title: container.chatTitle(id: id))
                } else {
                    ContentUnavailableView("Выберите чат", systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
    }
}
