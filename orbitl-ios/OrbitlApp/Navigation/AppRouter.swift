import Foundation
import Observation
import OrbitlDomain

@MainActor
@Observable
final class AppRouter {
    var chatId: String?
    var tab: AppTab = .chats

    /// Переход в чат с других вкладок (контакт, звонок).
    func openChat(_ id: String) {
        tab = .chats
        chatId = id
    }

    func open(_ link: DeepLink?) {
        switch link {
        case .chat(let id), .message(let id, _):
            tab = .chats
            chatId = id
        case .user, .none:
            break
        }
    }
}
