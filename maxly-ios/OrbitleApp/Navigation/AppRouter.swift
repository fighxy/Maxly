import Foundation
import Observation
import SwiftUI
import OrbitleDomain

@MainActor
@Observable
final class AppRouter {
    var chatId: String?
    var tab: AppTab = .chats

    /// Переход в чат с других вкладок (контакт, звонок).
    func openChat(_ id: String) {
        show(chatId: id)
    }

    func open(_ link: DeepLink?) {
        switch link {
        case .chat(let id), .message(let id, _):
            show(chatId: id)
        case .user, .none:
            break
        }
    }

    /// Уже на вкладке «Чаты» — обычный переход с анимацией. С другой вкладки чат
    /// открывается сразу: иначе на миг мелькает список, панель вкладок выезжает и тут же
    /// прячется, а экран чата въезжает поверх.
    private func show(chatId id: String) {
        guard tab != .chats else {
            chatId = id
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tab = .chats
            chatId = id
        }
    }
}
