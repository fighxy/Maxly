import Foundation

/// Свой профиль для шапки настроек и редактирования.
public struct MyProfile: Sendable, Hashable {
    public var id: String
    public var firstName: String
    public var lastName: String
    /// «О себе». Пусто, если не задано.
    public var about: String
    /// Цифры без `+`. Пусто, если номер неизвестен.
    public var phone: String
    public var avatarURL: URL?
    /// Есть ли фото на сервере: только его можно удалить.
    public var hasPhoto: Bool
    /// Ссылка на профиль для QR и «Поделиться». `nil`, если сервер её не дал.
    public var link: URL?

    public init(
        id: String, firstName: String, lastName: String = "", about: String = "", phone: String = "",
        avatarURL: URL? = nil, hasPhoto: Bool = false, link: URL? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.about = about
        self.phone = phone
        self.avatarURL = avatarURL
        self.hasPhoto = hasPhoto
        self.link = link
    }

    /// Имя и фамилия через пробел; «Без имени», если обоих нет.
    public var displayName: String {
        let name = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "Без имени" : name
    }

    /// `+7 999 000-11-22` для российских номеров, иначе `+<цифры>`. Пусто без номера.
    public var formattedPhone: String {
        PhoneFormatting.format(phone)
    }

    /// Номер со скрытыми цифрами той же длины и формы: `+7 ••• •••-••-••`.
    public var maskedPhone: String {
        PhoneFormatting.mask(formattedPhone)
    }
}

/// Форматирование номера для шапки настроек.
public enum PhoneFormatting {
    public static func format(_ digits: String) -> String {
        let d = digits.filter(\.isNumber)
        guard !d.isEmpty else { return "" }
        if d.count == 11, d.first == "7" || d.first == "8" {
            let a = Array(d)
            return "+7 \(String(a[1...3])) \(String(a[4...6]))-\(String(a[7...8]))-\(String(a[9...10]))"
        }
        return "+\(d)"
    }

    /// Цифры после кода страны заменяются точками, разделители остаются: `+7 ••• •••-••-••`.
    public static func mask(_ formatted: String) -> String {
        guard !formatted.isEmpty else { return "" }
        let prefixEnd = formatted.firstIndex(of: " ")
            ?? formatted.index(formatted.startIndex, offsetBy: min(2, formatted.count))
        let tail = formatted[prefixEnd...].map { $0.isNumber ? "•" : $0 }
        return String(formatted[..<prefixEnd]) + String(tail)
    }
}

/// Кто видит что-либо: номер, звонки, приглашения.
public enum PrivacyAccess: String, Sendable, Hashable, CaseIterable {
    case everybody = "ALL"
    case contacts = "CONTACTS"
    case nobody = "NOBODY"

    public var title: String {
        switch self {
        case .everybody: "Все"
        case .contacts: "Мои контакты"
        case .nobody: "Никто"
        }
    }
}

/// Через сколько месяцев без входа сервер удалит профиль.
public enum InactiveTTL: String, Sendable, Hashable, CaseIterable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"

    public var title: String {
        switch self {
        case .oneMonth: "1 месяц"
        case .threeMonths: "3 месяца"
        case .sixMonths: "6 месяцев"
        }
    }
}

/// Настройки аккаунта из конфига сервера.
public struct AccountSettings: Sendable, Hashable {
    /// Конфиг уже пришёл с сервера. До этого значения по умолчанию, экран показывает загрузку.
    public var isKnown: Bool
    public var phonePrivacy: PrivacyAccess
    /// Статус «в сети» не видит никто. Иначе его видят контакты.
    public var onlineHidden: Bool
    public var safeMode: Bool
    public var familyProtection: Bool
    public var inactiveTTL: InactiveTTL
    /// Ссылка-приглашение сервера. `nil`, если её нет.
    public var inviteLink: URL?
    public var sferumBotId: Int64
    public var digitalIdBotId: Int64
    /// Эмодзи двойного нажатия в чате.
    public var quickReaction: String
    /// Сервер не выключил быструю реакцию (`DOUBLE_TAP_REACTION_DISABLED` не `true`).
    public var quickReactionEnabled: Bool

    public static let defaultQuickReaction = "👍"

    public init(
        isKnown: Bool = false, phonePrivacy: PrivacyAccess = .everybody, onlineHidden: Bool = false,
        safeMode: Bool = false, familyProtection: Bool = false, inactiveTTL: InactiveTTL = .sixMonths,
        inviteLink: URL? = nil, sferumBotId: Int64 = 2_340_831, digitalIdBotId: Int64 = 8_250_447,
        quickReaction: String = AccountSettings.defaultQuickReaction, quickReactionEnabled: Bool = true
    ) {
        self.isKnown = isKnown
        self.phonePrivacy = phonePrivacy
        self.onlineHidden = onlineHidden
        self.safeMode = safeMode
        self.familyProtection = familyProtection
        self.inactiveTTL = inactiveTTL
        self.inviteLink = inviteLink
        self.sferumBotId = sferumBotId
        self.digitalIdBotId = digitalIdBotId
        self.quickReaction = quickReaction
        self.quickReactionEnabled = quickReactionEnabled
    }

    public static let unknown = AccountSettings()
}

/// Сеанс аккаунта на каком-либо устройстве.
public struct DeviceSession: Sendable, Hashable, Identifiable {
    public var id: String
    /// Приложение и платформа, например «MAX Web».
    public var client: String
    /// Устройство или браузер.
    public var info: String
    public var location: String
    public var isCurrent: Bool
    public var lastSeen: Date?

    public init(id: String, client: String, info: String = "", location: String = "", isCurrent: Bool = false, lastSeen: Date? = nil) {
        self.id = id
        self.client = client
        self.info = info
        self.location = location
        self.isCurrent = isCurrent
        self.lastSeen = lastSeen
    }

    /// Заголовок строки: приложение, иначе устройство, иначе «Неизвестное устройство».
    public var title: String {
        if !client.isEmpty { return client }
        if !info.isEmpty { return info }
        return "Неизвестное устройство"
    }
}

/// Заблокированный пользователь.
public struct BlockedUser: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var phone: String
    public var avatarURL: URL?

    public init(id: String, name: String, phone: String = "", avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.avatarURL = avatarURL
    }

    public var title: String { name.isEmpty ? "Пользователь MAX" : name }
}

/// Пароль для входа (двухэтапная проверка).
public struct TwoFactorStatus: Sendable, Hashable {
    public var isEnabled: Bool
    /// Почта для восстановления. `nil`, если не указана.
    public var email: String?
    public var hint: String?

    public init(isEnabled: Bool, email: String? = nil, hint: String? = nil) {
        self.isEnabled = isEnabled
        self.email = email.flatMap { $0.isEmpty ? nil : $0 }
        self.hint = hint.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `i•••n@ya.ru`: первая и последняя буква имени, домен целиком. Короткое имя — одна буква и точки.
    public static func mask(email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let first = parts[0].first else { return email }
        let name = parts[0]
        let masked = name.count <= 2 ? "\(first)•••" : "\(first)•••\(name.last!)"
        return "\(masked)@\(parts[1])"
    }
}

/// Мини-приложение MAX для листа с веб-страницей.
public struct MiniApp: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case sferum
        case digitalId

        public var title: String {
            switch self {
            case .sferum: "Сферум"
            case .digitalId: "Цифровой ID"
            }
        }
    }

    public var botId: Int64
    public var url: URL
    public var queryId: String?

    public init(botId: Int64, url: URL, queryId: String? = nil) {
        self.botId = botId
        self.url = url
        self.queryId = queryId
    }

    public var id: String { "\(botId):\(url.absoluteString)" }

    /// Адрес возврата внешнего шага (Госуслуги в Цифровом ID): в запросе `externalCallback=1`.
    public static func isExternalCallback(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains { $0.name == "externalCallback" && $0.value == "1" } ?? false
    }
}

/// Серверная папка чатов.
public struct ServerFolder: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// Чаты, добавленные в папку явно.
    public var chatIds: [String]
    /// Фильтры сервера текстом: коды (`"4"`) или имена (`"DIALOG"`).
    public var filters: [String]
    /// Системная папка «Все»: не редактируется и стоит первой.
    public var isAllChats: Bool

    public init(id: String, title: String, chatIds: [String] = [], filters: [String] = [], isAllChats: Bool = false) {
        self.id = id
        self.title = title
        self.chatIds = chatIds
        self.filters = filters
        self.isAllChats = isAllChats
    }

    /// Папка для полосы над списком чатов.
    public var chatFolder: ChatFolder {
        ChatFolder(id: id, title: title, filter: .rules(ChatFolderRules(chatIds: Set(chatIds), filters: filters)))
    }
}
