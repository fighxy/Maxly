import Foundation

/// Ссылка, которую роутер открывает тем же путём, что и обычную навигацию.
public enum DeepLink: Sendable, Equatable {
    case chat(id: String)
    case message(chatId: String, messageId: String)
    case user(id: String)

    /// `orbitl://chat/<id>`, `orbitl://chat/<id>/message/<messageId>`, `orbitl://user/<id>`.
    public static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == "orbitl" else { return nil }
        let host = url.host?.lowercased()
        let parts = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        switch host {
        case "chat":
            guard let id = parts.first else { return nil }
            if parts.count >= 3, parts[1] == "message" {
                return .message(chatId: id, messageId: parts[2])
            }
            return .chat(id: id)
        case "user":
            guard let id = parts.first else { return nil }
            return .user(id: id)
        default:
            return nil
        }
    }
}
