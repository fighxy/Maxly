import Foundation
import MaxlyDomain

/// Уведомление о новом сообщении, пока приложение в фоне: показывать ли его и что в нём.
///
/// Не показываем, когда приложение на экране (сообщение и так видно), когда фоновая работа
/// выключена в настройках и в чатах «без звука». Заголовок — чат, в группе подзаголовок —
/// автор, текст — сообщение или подпись вложения, как в списке чатов.
public enum MessageNotificationRules {
    public struct Content: Equatable, Sendable {
        public let title: String
        public let subtitle: String?
        public let body: String

        public init(title: String, subtitle: String?, body: String) {
            self.title = title
            self.subtitle = subtitle
            self.body = body
        }
    }

    /// Самое длинное тело уведомления: дальше iOS всё равно обрезает.
    public static let bodyLimit = 300
    /// Заголовок группы или канала без названия.
    public static let untitledChat = "Чат"

    public static func content(for notice: IncomingMessageNotice, appActive: Bool, enabled: Bool) -> Content? {
        guard enabled, !appActive, !notice.isMuted else { return nil }
        let author = notice.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let chat = notice.chatTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = notice.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.isEmpty ? MessageSelectionRules.placeholder(for: notice.media) : String(text.prefix(bodyLimit))
        switch notice.chatType {
        case .private:
            return Content(title: chat.isEmpty ? (author.isEmpty ? DisplayName.fallback : author) : chat, subtitle: nil, body: body)
        case .group:
            let title = chat.isEmpty ? Self.untitledChat : chat
            return Content(title: title, subtitle: author.isEmpty || author == title ? nil : author, body: body)
        case .channel:
            return Content(title: chat.isEmpty ? Self.untitledChat : chat, subtitle: nil, body: body)
        }
    }
}
