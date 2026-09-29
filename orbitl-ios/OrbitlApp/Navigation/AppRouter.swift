import Foundation
import Observation
import OrbitlDomain

@MainActor
@Observable
final class AppRouter {
    var chatId: String?
    var tab: AppTab = .chats

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
