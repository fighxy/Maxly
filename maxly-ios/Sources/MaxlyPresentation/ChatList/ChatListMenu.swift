import Foundation
import MaxlyDomain

/// Меню строки списка чатов — как в Max, один порядок на всех платформах: «Добавить в папку ›»,
/// «Закрепить», «Отметить непрочитанным», «Отключить уведомления ›» (на час, 4 часа, день,
/// навсегда), «Стереть переписку», «Скрыть истории автора», «Заблокировать», «Удалить чат».
/// Экран рисует `entries` по порядку, красным — `isDanger`.
public enum ChatListMenu {
    /// На сколько выключить уведомления.
    public enum MuteFor: CaseIterable, Hashable, Sendable {
        case hour, fourHours, day, forever

        public var title: String {
            switch self {
            case .hour: "На 1 час"
            case .fourHours: "На 4 часа"
            case .day: "На 1 день"
            case .forever: "Навсегда"
            }
        }

        /// `dontDisturbUntil`: конец в мс от `now` или `-1` насовсем.
        public func until(now: Date) -> Int64 {
            let ms = Int64((now.timeIntervalSince1970 * 1000).rounded())
            switch self {
            case .hour: return ms + 3_600_000
            case .fourHours: return ms + 4 * 3_600_000
            case .day: return ms + 86_400_000
            case .forever: return -1
            }
        }

        public var isDanger: Bool { self == .forever }
    }

    /// Папка в подменю «Добавить в папку»: `contains` — чат в ней уже есть (галочка, повтор — убрать).
    public struct FolderChoice: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let contains: Bool

        public init(id: String, title: String, contains: Bool) {
            self.id = id
            self.title = title
            self.contains = contains
        }
    }

    public enum Entry: Hashable, Sendable {
        case folders([FolderChoice])
        case pin(pinned: Bool)
        case read(unread: Bool)
        /// Выключенные уведомления — один пункт «Включить», иначе подменю сроков.
        case mute(muted: Bool)
        case erase
        case hideStories
        case block
        /// Что именно удаляется (у себя, у всех), спрашивает окно подтверждения.
        case delete

        public var title: String {
            switch self {
            case .folders: "Добавить в папку"
            case .pin(let pinned): pinned ? "Открепить" : "Закрепить"
            case .read(let unread): unread ? "Отметить прочитанным" : "Отметить непрочитанным"
            case .mute(let muted): muted ? "Включить уведомления" : "Отключить уведомления"
            case .erase: "Стереть переписку"
            case .hideStories: "Скрыть истории автора"
            case .block: "Заблокировать"
            case .delete: "Удалить чат"
            }
        }

        public var isDanger: Bool { self == .block || self == .delete }
    }

    /// Пункты меню строки `item`. `folders` — папки пользователя (пусто — пункта нет),
    /// `hasStories` — у автора чата есть истории в ленте, `canBlock` — есть чем заблокировать.
    /// «Избранное» не блокируют и не скрывают.
    public static func entries(
        item: ChatListItem,
        folders: [FolderChoice],
        capabilities: ChatListCapabilities,
        hasStories: Bool = false,
        canBlock: Bool = false
    ) -> [Entry] {
        let saved = item.id == Chat.savedMessagesId
        let unread = item.unreadCount > 0 || item.badge == .dot
        var result: [Entry] = []
        if !folders.isEmpty { result.append(.folders(folders)) }
        if capabilities.contains(.pin) { result.append(.pin(pinned: item.isPinned)) }
        if unread || capabilities.contains(.markUnread) { result.append(.read(unread: unread)) }
        if capabilities.contains(.mute) { result.append(.mute(muted: item.isMuted)) }
        if capabilities.contains(.delete) { result.append(.erase) }
        if hasStories && !saved { result.append(.hideStories) }
        if canBlock && item.type == .private && !saved { result.append(.block) }
        if capabilities.contains(.delete) { result.append(.delete) }
        return result
    }

    /// Папки для подменю: чат в папке, если он добавлен в неё явно.
    public static func folderChoices(chatId: String, folders: [ServerFolder]) -> [FolderChoice] {
        folders.filter { !$0.isAllChats }.map { FolderChoice(id: $0.id, title: $0.title, contains: $0.chatIds.contains(chatId)) }
    }

    /// Состав папки после выбора `chatId` в подменю: был — убирается, не было — добавляется.
    public static func toggled(_ folder: ServerFolder, chatId: String) -> [String] {
        folder.chatIds.contains(chatId) ? folder.chatIds.filter { $0 != chatId } : folder.chatIds + [chatId]
    }

    /// Собеседник личного чата: id диалога — `мой id ^ id собеседника`.
    public static func peer(chatId: String, myId: String) -> String? {
        guard chatId != Chat.savedMessagesId, let chat = Int64(chatId), let me = Int64(myId), me != 0 else { return nil }
        let peer = chat ^ me
        return peer > 0 && peer != me ? String(peer) : nil
    }
}
