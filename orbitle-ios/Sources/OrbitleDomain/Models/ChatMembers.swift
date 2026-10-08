import Foundation

/// Роль участника группы или канала. Ядро выводит её из карточки чата (`owner`,
/// `adminParticipants`); `arrange` делает то же по карточке, если роли не пришли.
public enum ChatMemberRole: String, Hashable, Sendable {
    case owner
    case admin
    case member
}

/// Участник в списке «Участники».
public struct ChatMemberEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var avatarURL: URL?
    public var role: ChatMemberRole
    /// Подпись админа (`alias`), если её задали.
    public var alias: String?
    /// Имя для упоминаний (ник без «@»), если известно.
    public var mentionName: String?

    public init(id: String, name: String, avatarURL: URL? = nil, role: ChatMemberRole = .member, alias: String? = nil, mentionName: String? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.role = role
        self.alias = alias
        self.mentionName = mentionName
    }

    /// Значок у имени: «владелец», подпись админа или «админ»; у остальных нет.
    public var badge: String? {
        switch role {
        case .owner: "владелец"
        case .admin:
            if let alias = alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty { alias } else { "админ" }
        case .member: nil
        }
    }
}

/// Страница `CHAT_MEMBERS` 59: участники и маркер следующей страницы. `nil` — дальше нет.
public struct ChatMembersPage: Hashable, Sendable {
    public var members: [ChatMemberEntry]
    public var marker: Int64?

    public init(members: [ChatMemberEntry], marker: Int64?) {
        self.members = members
        self.marker = marker
    }
}

/// Правила списка участников. Общие с Kotlin сценарии — `test-fixtures/members`.
public enum ChatMembersRules {
    /// Маркер первой страницы.
    public static let firstMarker: Int64 = 0
    /// Размер страницы, как у веб-клиента.
    public static let pageSize = 50

    /// Маркер для следующего запроса после ответа с [received] на запрос с [requested]:
    /// нет маркера — конец; `0` — тоже конец (это маркер первой страницы); тот же маркер, что
    /// спрашивали, или страница без новых участников — конец (защита от повтора).
    public static func nextMarker(requested: Int64, received: Int64?, newMembers: Int) -> Int64? {
        guard let received, received != 0, received != requested, newMembers > 0 else { return nil }
        return received
    }

    /// Дописать страницу к списку: повторы по id выбрасываются (остаётся первый).
    public static func append(_ page: [ChatMemberEntry], to list: [ChatMemberEntry]) -> (list: [ChatMemberEntry], added: Int) {
        var seen = Set(list.map(\.id))
        var result = list
        var added = 0
        for member in page where seen.insert(member.id).inserted {
            result.append(member)
            added += 1
        }
        return (result, added)
    }

    /// Роли из карточки чата и порядок: владелец, админы, остальные — каждый в порядке сервера.
    public static func arrange(_ list: [ChatMemberEntry], owner: String?, admins: [String: String?]) -> [ChatMemberEntry] {
        let ranked = list.map { member -> ChatMemberEntry in
            var copy = member
            if let owner, member.id == owner {
                copy.role = .owner
                copy.alias = nil
            } else if let alias = admins[member.id] {
                copy.role = .admin
                copy.alias = alias
            } else {
                copy.role = .member
                copy.alias = nil
            }
            return copy
        }
        return ranked.filter { $0.role == .owner } + ranked.filter { $0.role == .admin } + ranked.filter { $0.role == .member }
    }

    /// Порядок экрана: владелец, админы, остальные — каждый в порядке сервера.
    public static func ranked(_ list: [ChatMemberEntry]) -> [ChatMemberEntry] {
        list.filter { $0.role == .owner } + list.filter { $0.role == .admin } + list.filter { $0.role == .member }
    }

    /// Поиск по уже загруженным: без учёта регистра, «ё» = «е», пробелы по краям не важны;
    /// пустой запрос — все. Порядок сохраняется.
    public static func filter(_ list: [ChatMemberEntry], query: String) -> [ChatMemberEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = fold(trimmed)
        guard !needle.isEmpty else { return list }
        // «@ник» ищется только по имени для упоминаний.
        let mention = needle.hasPrefix("@") ? String(needle.dropFirst()) : needle
        return list.filter { member in
            if !needle.hasPrefix("@"), fold(member.name).contains(needle) { return true }
            guard !mention.isEmpty, let nick = member.mentionName else { return needle == "@" }
            return fold(nick).contains(mention)
        }
    }

    static func fold(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
    }
}
