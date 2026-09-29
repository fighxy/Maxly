import Foundation
import Observation
import OrbitlDomain

@MainActor
@Observable
final class AppRouter {
    var chatId: String?

    func open(_ link: DeepLink?) {
        switch link {
        case .chat(let id), .message(let id, _):
            chatId = id
        case .user, .none:
            break
        }
    }
}
