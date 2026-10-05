import Foundation
import OrbitleDomain

extension SharedMediaTab {
    /// Что спрашивать у сервера для вкладки. Ссылки — вложения-превью (`SHARE`); ссылки из
    /// простого текста приходят только с историей.
    public var attachTypes: [SharedAttachType] {
        switch self {
        case .media: [.photo, .video]
        case .files: [.file]
        case .links: [.share]
        case .voice: [.audio]
        }
    }
}

/// Страница общих медиа с сервера: вкладка и сообщение-якорь (серверный id),
/// до `forward` сообщений новее и до `backward` старше.
public struct SharedMediaRequest: Hashable, Sendable {
    public let tab: SharedMediaTab
    public let anchorId: String
    public let forward: Int
    public let backward: Int

    public var types: [SharedAttachType] { tab.attachTypes }
}

/// Обход общих медиа на сервере, независимо от того, сколько истории загружено в чате.
///
/// Каждая вкладка идёт от последнего сообщения чата к старым: первая страница — вокруг него,
/// следующие — от самого старого полученного сообщения. Вкладки спрашиваются по кругу, чтобы
/// первые страницы всех вкладок пришли сразу. Вкладка заканчивается, когда страница не
/// принесла ничего нового или набрано `maxPages` страниц. Ошибка останавливает вкладку до
/// следующего открытия профиля (``retryFailed()``).
///
/// `maxPages` по умолчанию небольшой: обход идёт сам, без прокрутки, и каждая страница —
/// отдельный `CHAT_MEDIA`. Сорок страниц на четыре вкладки давали до 160 запросов за одно
/// открытие профиля и съедали лимит сервера (`too.many.requests`) у истории и комментариев.
public struct SharedMediaPager: Sendable {
    struct Cursor: Sendable {
        var anchor: String?
        /// Серверные id, уже пришедшие этой вкладке: сообщение с фото и файлом приходит обеим
        /// вкладкам, и чужое не должно считаться концом.
        var seen: Set<String> = []
        var pages = 0
        var done = false
        var failed = false
    }

    public let pageSize: Int
    public let maxPages: Int
    /// Полученные с сервера сообщения по серверному id.
    public private(set) var messages: [String: Message] = [:]
    private var cursors: [SharedMediaTab: Cursor] = [:]

    public init(pageSize: Int = 50, maxPages: Int = 5) {
        self.pageSize = pageSize
        self.maxPages = maxPages
    }

    /// Серверный id сообщения: у своих отправленных — `serverId`, у остальных — `id`.
    public static func key(_ message: Message) -> String { message.serverId ?? message.id }

    /// Якорь первой страницы: самое новое сообщение окна, уже известное серверу.
    public static func anchor(in window: [Message]) -> String? {
        for message in window.reversed() {
            let id = key(message)
            if Int64(id) != nil { return id }
        }
        return nil
    }

    public var isFinished: Bool {
        SharedMediaTab.allCases.allSatisfy { cursors[$0]?.done == true || cursors[$0]?.failed == true }
    }

    /// Очередной круг запросов: по одному на каждую незаконченную вкладку.
    public func round(latest: String) -> [SharedMediaRequest] {
        SharedMediaTab.allCases.compactMap { tab in
            let cursor = cursors[tab] ?? Cursor()
            guard !cursor.done, !cursor.failed else { return nil }
            if let anchor = cursor.anchor {
                return SharedMediaRequest(tab: tab, anchorId: anchor, forward: 0, backward: pageSize)
            }
            return SharedMediaRequest(tab: tab, anchorId: latest, forward: pageSize, backward: pageSize)
        }
    }

    /// Ответ на `request`; `nil` — сервер не ответил. Возвращает, пришло ли что-то новое.
    @discardableResult
    public mutating func receive(_ page: [Message]?, for request: SharedMediaRequest) -> Bool {
        var cursor = cursors[request.tab] ?? Cursor()
        defer { cursors[request.tab] = cursor }
        guard let page else {
            cursor.failed = true
            return false
        }
        cursor.pages += 1
        let fresh = page.filter { !cursor.seen.contains(Self.key($0)) }
        for message in fresh {
            let key = Self.key(message)
            cursor.seen.insert(key)
            messages[key] = message
        }
        // Следующая страница — от самого старого сообщения этой страницы.
        if let oldest = page.min(by: { $0.timestamp < $1.timestamp }) {
            cursor.anchor = Self.key(oldest)
        }
        if fresh.isEmpty || cursor.pages >= maxPages { cursor.done = true }
        return !fresh.isEmpty
    }

    /// Вкладки, остановленные ошибкой, продолжаются с того же места.
    public mutating func retryFailed() {
        for tab in SharedMediaTab.allCases where cursors[tab]?.failed == true {
            cursors[tab]?.failed = false
        }
    }
}
