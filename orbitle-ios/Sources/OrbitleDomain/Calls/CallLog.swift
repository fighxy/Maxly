import Foundation

/// Запись журнала звонков в том виде, в каком её отдаёт сервер (`CALL_HISTORY` 163,
/// пуш `NOTIF_CALL_HISTORY` 165).
public struct CallLogItem: Hashable, Sendable {
    public var historyId: String
    public var callId: String
    /// Название группового звонка; пусто у звонка один на один.
    public var callName: String
    /// Кто звонил; пусто, если сервер не прислал.
    public var callerId: String
    public var messageId: String
    /// Пусто, если сервер не прислал чат.
    public var chatId: String
    public var isVideo: Bool
    /// `HUNGUP`, `CANCELED`, `REJECTED`, `MISSED` или пусто.
    public var hangupType: String
    public var joinLink: String
    public var timeMs: Int64
    /// Длительность в мс; `-1` — сервер её не прислал (`0` — настоящий ноль).
    public var durationMs: Int64
    /// `LINK` (звонок по ссылке), `CHAT` (звонок группы) или пусто (один на один).
    public var groupCallType: String

    public init(
        historyId: String,
        callId: String = "",
        callName: String = "",
        callerId: String = "",
        messageId: String = "",
        chatId: String = "",
        isVideo: Bool = false,
        hangupType: String = "",
        joinLink: String = "",
        timeMs: Int64 = 0,
        durationMs: Int64 = -1,
        groupCallType: String = ""
    ) {
        self.historyId = historyId
        self.callId = callId
        self.callName = callName
        self.callerId = callerId
        self.messageId = messageId
        self.chatId = chatId
        self.isVideo = isVideo
        self.hangupType = hangupType
        self.joinLink = joinLink
        self.timeMs = timeMs
        self.durationMs = durationMs
        self.groupCallType = groupCallType
    }

    /// Групповой звонок: по ссылке или в чате.
    public var isGroup: Bool { !groupCallType.isEmpty }
}

/// Ответ `CALL_HISTORY` 163: записи, курсор следующего запроса и `reset`.
public struct CallLogPage: Hashable, Sendable {
    /// Курсор `callHistorySync` для следующего запроса.
    public var sync: String
    /// Журнал на устройстве надо заменить этими записями.
    public var reset: Bool
    public var items: [CallLogItem]

    public init(sync: String, reset: Bool = false, items: [CallLogItem]) {
        self.sync = sync
        self.reset = reset
        self.items = items
    }
}

/// Имя и аватар собеседника или чата звонка.
public struct CallLogPeer: Hashable, Sendable {
    public var name: String
    public var avatarURL: URL?

    public init(name: String, avatarURL: URL? = nil) {
        self.name = name
        self.avatarURL = avatarURL
    }
}

/// Журнал звонков по курсору сервера.
///
/// Первый запрос идёт с пустым курсором, каждый следующий — с `sync` прошлого ответа: так
/// приходят следующие страницы и новые звонки. Ответ с `reset` заменяет журнал целиком.
/// Пуш 165 добавляет и удаляет записи по `historyId`.
public struct CallLog: Hashable, Sendable {
    public private(set) var items: [String: CallLogItem] = [:]
    /// Курсор для следующего запроса; пусто — первая страница.
    public private(set) var sync: String = ""
    /// Последний ответ принёс записи и новый курсор: за ним может быть ещё страница.
    public private(set) var hasMore = true
    /// Хотя бы один ответ уже пришёл.
    public private(set) var isLoaded = false

    public init() {}

    /// Ответ на запрос с текущим курсором. `true` — журнал изменился.
    @discardableResult
    public mutating func apply(_ page: CallLogPage) -> Bool {
        let before = items
        if page.reset { items = [:] }
        for item in page.items where !item.historyId.isEmpty {
            items[item.historyId] = item
        }
        let next = Self.cursor(page.sync)
        hasMore = !page.items.isEmpty && !next.isEmpty && next != sync
        if !next.isEmpty { sync = next }
        let changed = !isLoaded || items != before
        isLoaded = true
        return changed
    }

    /// Записи пуша `add`. `true` — журнал изменился.
    @discardableResult
    public mutating func add(_ added: [CallLogItem]) -> Bool {
        let before = items
        for item in added where !item.historyId.isEmpty { items[item.historyId] = item }
        return items != before
    }

    /// Записи удалили (пуш `remove` или удаление с этого устройства). `true` — что-то ушло.
    @discardableResult
    public mutating func remove(_ ids: [String]) -> Bool {
        var changed = false
        for id in ids where items.removeValue(forKey: id) != nil { changed = true }
        return changed
    }

    /// Новые звонки сверху; при равном времени — больший `historyId`.
    public var ordered: [CallLogItem] {
        items.values.sorted { a, b in
            if a.timeMs != b.timeMs { return a.timeMs > b.timeMs }
            let left = Int64(a.historyId) ?? 0
            let right = Int64(b.historyId) ?? 0
            return left != right ? left > right : a.historyId > b.historyId
        }
    }

    /// `""` и `"0"` — курсора нет.
    static func cursor(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed == "0" ? "" : trimmed
    }

    // MARK: Запись для экрана

    /// Собеседник звонка один на один: позвонивший, а у своего звонка — второй участник
    /// диалога (id диалога — XOR двух id). У группового — его чат, у звонка по ссылке пусто.
    public static func peerId(of item: CallLogItem, me: String) -> String {
        if item.isGroup { return item.chatId }
        if !item.callerId.isEmpty, item.callerId != me { return item.callerId }
        guard let chat = Int64(item.chatId), let mine = Int64(me), chat != 0, mine != 0 else { return "" }
        let peer = chat ^ mine
        return peer > 0 ? String(peer) : ""
    }

    /// Чат диалога с человеком `peerId`: XOR двух id. Пусто, если id не числа.
    public static func dialogChatId(me: String, peerId: String) -> String {
        guard let mine = Int64(me), let peer = Int64(peerId), mine != 0, peer != 0 else { return "" }
        return String(mine ^ peer)
    }

    public static func isOutgoing(_ item: CallLogItem, me: String) -> Bool {
        !me.isEmpty && item.callerId == me
    }

    /// Чем закончился звонок для этого аккаунта.
    public static func outcome(of item: CallLogItem, outgoing: Bool) -> CallRecord.Outcome {
        let talked = item.durationMs > 0
        if outgoing {
            switch item.hangupType {
            case "REJECTED": return .declined
            case "CANCELED", "MISSED": return .cancelled
            case "HUNGUP": return item.durationMs == 0 ? .cancelled : .answered
            default: return talked ? .answered : .cancelled
            }
        }
        switch item.hangupType {
        case "MISSED", "CANCELED": return .missed
        case "REJECTED": return .declined
        case "HUNGUP": return item.durationMs == 0 ? .missed : .answered
        default: return talked ? .answered : .missed
        }
    }

    /// Строка журнала для экрана. `peer` — имя и аватар собеседника или чата, если известны.
    public static func record(_ item: CallLogItem, me: String, peer: CallLogPeer?) -> CallRecord {
        let outgoing = isOutgoing(item, me: me)
        let peerId = peerId(of: item, me: me)
        var chatId = item.chatId
        if chatId.isEmpty, !item.isGroup, !peerId.isEmpty { chatId = dialogChatId(me: me, peerId: peerId) }
        let name = item.callName.isEmpty ? (peer?.name ?? "") : item.callName
        return CallRecord(
            id: item.historyId,
            peerId: peerId,
            title: name.isEmpty ? (item.isGroup ? "Групповой звонок" : "Звонок") : name,
            avatarURL: peer?.avatarURL,
            isGroup: item.isGroup,
            chatId: chatId.isEmpty ? nil : chatId,
            direction: outgoing ? .outgoing : .incoming,
            outcome: outcome(of: item, outgoing: outgoing),
            isVideo: item.isVideo,
            date: Date(timeIntervalSince1970: TimeInterval(item.timeMs) / 1000),
            duration: item.durationMs >= 0 ? TimeInterval(item.durationMs) / 1000 : nil
        )
    }
}
