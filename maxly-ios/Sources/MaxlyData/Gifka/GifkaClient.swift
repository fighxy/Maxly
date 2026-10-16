import Foundation

/// Гифка или стикер каталога gifka.me (`GET /v1/search`, `GET /v1/media/trending`).
public struct GifkaMedia: Decodable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case gif
        case sticker
        case other
    }

    public struct Rendition: Decodable, Hashable, Sendable {
        /// `mp4`, `webp`, `webm_alpha`, `poster`, `poster_jpeg`.
        public let kind: String
        public let url: URL
        public let width: Int?
        public let height: Int?
        public let mime: String?
        public let bytes: Int?
    }

    public struct Download: Decodable, Hashable, Sendable {
        /// Ссылка API на файл GIF: отдаёт его только с ключом (`X-Api-Key`).
        public let gif: URL?
        /// GIF уже собран; иначе первый запрос соберёт его (до полуминуты).
        public let gifReady: Bool?
    }

    public let id: String
    public let rawType: String
    public let title: String
    public let width: Int?
    public let height: Int?
    public let renditions: [Rendition]
    public let download: Download?
    /// Автор разрешил скачивание (политика бренда может его запретить).
    public let downloadAllowed: Bool

    public var kind: Kind { Kind(rawValue: rawType) ?? .other }

    enum CodingKeys: String, CodingKey {
        case id, type, title, width, height, renditions, download, downloadAllowed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        rawType = (try? c.decode(String.self, forKey: .type)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        width = try? c.decode(Int.self, forKey: .width)
        height = try? c.decode(Int.self, forKey: .height)
        // Битая рендиция (нет адреса) не роняет весь ответ.
        let list = (try? c.decode([Lenient<Rendition>].self, forKey: .renditions)) ?? []
        renditions = list.compactMap(\.value)
        download = try? c.decode(Download.self, forKey: .download)
        downloadAllowed = (try? c.decode(Bool.self, forKey: .downloadAllowed)) ?? true
    }

    /// Ролик для превью: самый маленький MP4 не уже `minWidth` (или самый большой из узких).
    public func previewMP4(minWidth: Int = 200) -> Rendition? {
        pick("mp4", minWidth: minWidth)
    }

    /// Анимированный WebP для превью (у стикеров нет MP4).
    public func previewWebP(minWidth: Int = 200) -> Rendition? {
        pick("webp", minWidth: minWidth)
    }

    /// Статичный кадр: постер JPEG или WebP.
    public var poster: Rendition? {
        renditions.first { $0.kind == "poster_jpeg" } ?? renditions.first { $0.kind == "poster" }
    }

    /// Отношение сторон для сетки.
    public var aspect: Double {
        let w = width ?? previewMP4()?.width ?? poster?.width
        let h = height ?? previewMP4()?.height ?? poster?.height
        guard let w, let h, w > 0, h > 0 else { return 1 }
        return Double(w) / Double(h)
    }

    /// Можно ли получить файл GIF для отправки.
    public func canSendGIF(hasKey: Bool) -> Bool {
        hasKey && downloadAllowed && download?.gif != nil
    }

    private func pick(_ kind: String, minWidth: Int) -> Rendition? {
        let all = renditions.filter { $0.kind == kind }.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        return all.first { ($0.width ?? 0) >= minWidth } ?? all.last
    }
}

/// Событие pingback: только id медиа и вид, без данных пользователя.
public struct GifkaEvent: Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// Показ в выдаче.
        case view
        /// Выбор (нажатие).
        case click
        /// Отправка в чат.
        case send
    }

    public let mediaId: String
    public let kind: Kind

    public init(mediaId: String, kind: Kind) {
        self.mediaId = mediaId
        self.kind = kind
    }
}

/// Причины жалобы, как их принимает `POST /v1/media/{id}/report`.
public enum GifkaReportReason: String, CaseIterable, Sendable, Identifiable {
    case copyright
    case nsfw
    case violence
    case hate
    case spam
    case wrongDescription = "wrong_description"
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .copyright: "Нарушение авторских прав"
        case .nsfw: "Откровенный контент"
        case .violence: "Насилие"
        case .hate: "Вражда и оскорбления"
        case .spam: "Спам"
        case .wrongDescription: "Неверное описание"
        case .other: "Другое"
        }
    }
}

/// Страница выдачи gifka.me.
public struct GifkaPage: Decodable, Sendable {
    public let items: [GifkaMedia]
    /// Всего найдено (у трендов нет).
    public let total: Int?

    enum CodingKeys: String, CodingKey { case items, total }

    public init(items: [GifkaMedia], total: Int?) {
        self.items = items
        self.total = total
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = (try? c.decode([Lenient<GifkaMedia>].self, forKey: .items)) ?? []
        items = list.compactMap(\.value)
        total = try? c.decode(Int.self, forKey: .total)
    }

    public static func parse(_ data: Data) throws -> GifkaPage {
        try JSONDecoder().decode(GifkaPage.self, from: data)
    }
}

/// Элемент массива, который при ошибке разбора становится `nil`.
struct Lenient<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

public enum GifkaError: LocalizedError, Equatable {
    case noKey
    case http(Int)
    case notGIF

    public var errorDescription: String? {
        switch self {
        case .noKey: "Для отправки гифок из gifka.me нужен ключ API в сборке"
        case .http(401): "gifka.me не отдал файл: нужен ключ API"
        case .http(let code): "gifka.me ответил ошибкой \(code)"
        case .notGIF: "gifka.me прислал не GIF"
        }
    }
}

/// REST API gifka.me (https://api.gifka.me/docs). Ключ необязателен: без него поиск и
/// тренды работают с лимитом по IP, а скачивание GIF недоступно.
public struct GifkaClient: Sendable {
    public enum MediaType: String, Sendable {
        case gif
        case sticker
    }

    public static let base = URL(string: "https://api.gifka.me")!
    /// Возрастной рейтинг выдачи (условия API требуют передавать его; по умолчанию до pg13).
    public static let rating = "pg13"

    public let apiKey: String?
    private let session: URLSession
    private let cache: GifkaResponseCache

    public init(apiKey: String?, session: URLSession = .shared, cache: GifkaResponseCache = .shared) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Незаполненная переменная сборки остаётся строкой `$(GIFKA_API_KEY)`.
        self.apiKey = trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        self.session = session
        self.cache = cache
    }

    public var hasKey: Bool { apiKey != nil }

    public static func searchURL(query: String, type: MediaType, limit: Int, offset: Int) -> URL {
        var components = URLComponents(url: base.appendingPathComponent("v1/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "rating", value: rating),
        ]
        return components.url!
    }

    public static func trendingURL(type: MediaType, limit: Int, offset: Int) -> URL {
        var components = URLComponents(url: base.appendingPathComponent("v1/media/trending"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "rating", value: rating),
        ]
        return components.url!
    }

    /// Запрос с ключом в заголовке, только если ключ есть. В адрес ключ не попадает.
    public func request(_ url: URL, timeout: TimeInterval = 15) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
        return request
    }

    public func search(_ query: String, type: MediaType, limit: Int = 30, offset: Int = 0) async throws -> GifkaPage {
        try await page(Self.searchURL(query: query, type: type, limit: limit, offset: offset))
    }

    public func trending(type: MediaType, limit: Int = 30, offset: Int = 0) async throws -> GifkaPage {
        try await page(Self.trendingURL(type: type, limit: limit, offset: offset))
    }

    /// Файл GIF медиа. Нужен ключ: без него сервер отвечает 401. Первый запрос собирает
    /// GIF на сервере, поэтому ждём дольше обычного.
    public func downloadGIF(_ media: GifkaMedia) async throws -> Data {
        guard hasKey else { throw GifkaError.noKey }
        guard let url = media.download?.gif else { throw GifkaError.http(404) }
        var request = request(url, timeout: 60)
        request.setValue("image/gif", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw GifkaError.http(code) }
        guard data.starts(with: Array("GIF8".utf8)) else { throw GifkaError.notGIF }
        return data
    }

    /// Тело `POST /v1/pingback`: только id медиа и вид события, без данных пользователя.
    public static func pingbackBody(_ events: [GifkaEvent]) -> Data? {
        let valid = events.filter { !$0.mediaId.isEmpty }
        guard !valid.isEmpty else { return nil }
        let list = valid.map { ["mediaId": $0.mediaId, "kind": $0.kind.rawValue] }
        return try? JSONSerialization.data(withJSONObject: ["events": list], options: [.sortedKeys])
    }

    /// Тело `POST /v1/media/{id}/report`.
    public static func reportBody(reason: GifkaReportReason, details: String? = nil) -> Data {
        var body: [String: String] = ["reason": reason.rawValue]
        if let text = details?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            body["details"] = String(text.prefix(500))
        }
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    /// Запрос pingback или `nil`, если отправлять нечего или нет ключа (без ключа API его не принимает).
    public func pingbackRequest(_ events: [GifkaEvent]) -> URLRequest? {
        guard hasKey, let body = Self.pingbackBody(events) else { return nil }
        return post(Self.base.appendingPathComponent("v1/pingback"), body: body)
    }

    /// События показа, выбора и отправки. Ошибки не бросает: pingback не влияет на работу панели.
    public func pingback(_ events: [GifkaEvent]) async {
        guard let request = pingbackRequest(events) else { return }
        _ = try? await session.data(for: request)
    }

    /// Жалоба на материал.
    public func report(_ mediaId: String, reason: GifkaReportReason, details: String? = nil) async throws {
        guard !mediaId.isEmpty, !mediaId.contains("/") else { throw GifkaError.http(400) }
        let url = Self.base.appendingPathComponent("v1/media").appendingPathComponent(mediaId).appendingPathComponent("report")
        let (_, response) = try await session.data(for: post(url, body: Self.reportBody(reason: reason, details: details)))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw GifkaError.http(code) }
    }

    private func post(_ url: URL, body: Data) -> URLRequest {
        var request = request(url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func page(_ url: URL) async throws -> GifkaPage {
        if let cached = cache.page(for: url) { return cached }
        let (data, response) = try await session.data(for: request(url))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw GifkaError.http(code) }
        let page = try GifkaPage.parse(data)
        cache.store(page, for: url)
        return page
    }
}
