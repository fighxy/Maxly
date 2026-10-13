import Foundation
import MaxlyDomain

/// Плитки под шапкой профиля и меню «Ещё» — как в Max, тот же порядок, что на Android и ПК.
///
/// - Человек: «Чат», «Звонок», «Видео», «Звук», «Ещё» → «Поделиться контактом», «Добавить в
///   папку ›», «Найти», «Стереть переписку», «Скрыть истории автора», «Заблокировать», «Удалить чат».
/// - Группа: «Звонок», «Видео» (если в группе можно звонить), «Звук», «Найти», «Ещё» →
///   «Добавить в папку ›», «Стереть переписку», «Пожаловаться», «Покинуть группу», «Удалить
///   группу» (владельцу) или «Удалить чат».
/// - Канал: «Звук», «Ещё» → «Добавить в папку ›», «Найти», «Стереть переписку», «Пожаловаться»,
///   «Отписаться от канала», «Удалить канал» (владельцу).
/// - Группа или канал не из списка: «Вступить» / «Подписаться» и «Ещё».
public enum ProfileMenu {
    public enum Tile: Hashable, Sendable {
        case chat, call, video, sound, search, join, subscribe, more

        public var title: String {
            switch self {
            case .chat: "Чат"
            case .call: "Звонок"
            case .video: "Видео"
            case .sound: "Звук"
            case .search: "Найти"
            case .join: "Вступить"
            case .subscribe: "Подписаться"
            case .more: "Ещё"
            }
        }
    }

    public enum Entry: Hashable, Sendable {
        case shareContact
        case shareLink
        /// Подменю папок; в конце — «Создать папку».
        case folders([ChatListMenu.FolderChoice])
        case search
        case erase
        case hideStories
        case report
        case block(blocked: Bool)
        case leave(channel: Bool)
        case delete(title: String)

        public var title: String {
            switch self {
            case .shareContact: "Поделиться контактом"
            case .shareLink: "Поделиться ссылкой"
            case .folders: "Добавить в папку"
            case .search: "Найти"
            case .erase: "Стереть переписку"
            case .hideStories: "Скрыть истории автора"
            case .report: "Пожаловаться"
            case .block(let blocked): blocked ? "Разблокировать" : "Заблокировать"
            case .leave(let channel): channel ? "Отписаться от канала" : "Покинуть группу"
            case .delete(let title): title
            }
        }

        public var isDanger: Bool {
            switch self {
            case .block(let blocked): !blocked
            case .leave, .delete: true
            default: false
            }
        }
    }

    public static let createFolder = "Создать папку"

    /// Плитки профиля. `listed` — чат в списке (иначе открыт из поиска), `calls` — звонки
    /// собеседнику, `groupCalls` — звонки в группе, `sound` — звук можно переключить.
    public static func tiles(
        kind: ChatProfile.Kind,
        listed: Bool = true,
        calls: Bool = true,
        groupCalls: Bool = false,
        sound: Bool = true
    ) -> [Tile] {
        var result: [Tile] = []
        switch kind {
        case .user:
            result.append(.chat)
            if calls { result += [.call, .video] }
            if sound { result.append(.sound) }
        case .bot:
            result.append(.chat)
            if sound { result.append(.sound) }
        case .saved:
            result += [.chat, .search]
        case .group:
            if !listed {
                result.append(.join)
            } else {
                if groupCalls { result += [.call, .video] }
                if sound { result.append(.sound) }
                result.append(.search)
            }
        case .channel:
            if !listed {
                result.append(.subscribe)
            } else if sound {
                result.append(.sound)
            }
        }
        result.append(.more)
        return result
    }

    /// Пункты «Ещё». `folders` — папки для подменю (`nil` — менять их нечем), `blocked` — собеседник
    /// в чёрном списке (`nil` — неизвестно или блокировать нельзя), `canReport` — есть жалоба,
    /// `canErase` — переписку можно стереть и чат удалить. «Найти» уходит в меню, если его нет
    /// среди `tiles`.
    public static func entries(
        kind: ChatProfile.Kind,
        tiles: [Tile],
        listed: Bool = true,
        hasLink: Bool = false,
        folders: [ChatListMenu.FolderChoice]? = nil,
        hasStories: Bool = false,
        canReport: Bool = false,
        isAdmin: Bool = false,
        isOwner: Bool = false,
        blocked: Bool? = nil,
        canErase: Bool = true
    ) -> [Entry] {
        let channel = kind == .channel
        if !listed {
            var result: [Entry] = []
            if hasLink { result.append(.shareLink) }
            if canReport { result.append(.report) }
            return result
        }
        var result: [Entry] = []
        switch kind {
        case .user: result.append(.shareContact)
        case .group, .channel: if hasLink { result.append(.shareLink) }
        case .bot, .saved: break
        }
        if let folders { result.append(.folders(folders)) }
        if !tiles.contains(.search) { result.append(.search) }
        if canErase { result.append(.erase) }
        if hasStories, kind != .saved { result.append(.hideStories) }
        if canReport, kind == .group || (channel && !isAdmin) { result.append(.report) }
        if let blocked, kind == .user || kind == .bot { result.append(.block(blocked: blocked)) }
        if kind == .group || channel { result.append(.leave(channel: channel)) }
        if canErase {
            if channel {
                if isOwner { result.append(.delete(title: "Удалить канал")) }
            } else {
                result.append(.delete(title: kind == .group && isOwner ? "Удалить группу" : "Удалить чат"))
            }
        }
        return result
    }
}
