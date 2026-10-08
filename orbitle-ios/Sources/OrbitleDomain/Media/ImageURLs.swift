import Foundation

/// Форма `fn` у адреса картинки. Лестницу размеров знает только ядро.
public enum ImageURLShape: String, Sendable {
    /// Аватар: `sqr_N`.
    case square
    /// Фото: `w_N`.
    case width
}

/// Выбор размера и проверка `expires`. Реализация в приложении зовёт ядро.
public protocol ImageURLSizing: Sendable {
    func sizedURL(_ url: String, shape: ImageURLShape, neededPixels: Int) -> String
    func isExpired(_ url: String, nowMillis: Int64) -> Bool
}

/// Без ядра адрес не меняется и не считается просроченным.
public struct PassthroughImageURLSizing: ImageURLSizing {
    public init() {}
    public func sizedURL(_ url: String, shape: ImageURLShape, neededPixels: Int) -> String { url }
    public func isExpired(_ url: String, nowMillis: Int64) -> Bool { false }
}

public enum ImageURLRequests {
    /// Полноэкранный просмотр оставляет адрес без `fn`. Иначе ядро дописывает размер.
    /// `neededPixels` — сторона в точках, умноженная на масштаб экрана.
    public static func url(
        _ url: URL?,
        shape: ImageURLShape,
        pointSize: CGFloat,
        scale: CGFloat,
        fullScreen: Bool,
        sizing: any ImageURLSizing
    ) -> URL? {
        guard let url, !url.isFileURL else { return url }
        if fullScreen { return url }
        let pixels = Int((pointSize * max(scale, 1)).rounded(.up))
        let sized = sizing.sizedURL(url.absoluteString, shape: shape, neededPixels: max(pixels, 0))
        return URL(string: sized) ?? url
    }
}

/// Одно фото, чей адрес пора обновить (код 203).
public struct PhotoRefreshKey: Hashable, Sendable {
    public var chatId: String
    public var messageId: String
    public var photoId: String

    public init(chatId: String, messageId: String, photoId: String) {
        self.chatId = chatId
        self.messageId = messageId
        self.photoId = photoId
    }
}

/// Очередь обновления адресов: без повторов и не чаще, чем позволяет пауза.
public struct PhotoRefreshQueue: Sendable {
    public var maxPerRequest: Int
    public var minIntervalMs: Int64
    private var waiting: [PhotoRefreshKey] = []
    private var seen: Set<PhotoRefreshKey> = []
    private var lastSentMs: Int64?

    public init(maxPerRequest: Int = 100, minIntervalMs: Int64 = 1_000) {
        self.maxPerRequest = max(1, maxPerRequest)
        self.minIntervalMs = max(0, minIntervalMs)
    }

    public var pendingCount: Int { waiting.count }

    public mutating func enqueue(_ keys: [PhotoRefreshKey]) {
        for key in keys where !key.photoId.isEmpty && key.photoId != "0" && seen.insert(key).inserted {
            waiting.append(key)
        }
    }

    /// Следующая пачка. `nil`, если очередь пуста или пауза ещё не прошла.
    public mutating func take(nowMs: Int64) -> [PhotoRefreshKey]? {
        guard !waiting.isEmpty else { return nil }
        if let lastSentMs, nowMs - lastSentMs < minIntervalMs { return nil }
        let count = min(maxPerRequest, waiting.count)
        let batch = Array(waiting.prefix(count))
        waiting.removeFirst(count)
        lastSentMs = nowMs
        return batch
    }

    /// Неудачная пачка возвращается в очередь и может уйти после паузы.
    public mutating func requeue(_ keys: [PhotoRefreshKey]) {
        for key in keys { seen.remove(key) }
        enqueue(keys)
    }
}

/// Новый адрес фото из ответа 203.
public struct RefreshedPhotoURL: Sendable, Equatable {
    public var photoId: String
    public var url: String
    public var width: Int
    public var height: Int

    public init(photoId: String, url: String, width: Int = 0, height: Int = 0) {
        self.photoId = photoId
        self.url = url
        self.width = width
        self.height = height
    }
}

extension MessageContent {
    /// Подменяет адреса фото по id. Пустой адрес и неизвестный id не трогает.
    public func replacingPhotoURLs(_ fresh: [RefreshedPhotoURL]) -> MessageContent {
        let byId = Dictionary(uniqueKeysWithValues: fresh.compactMap { item -> (String, RefreshedPhotoURL)? in
            guard !item.url.isEmpty, let url = URL(string: item.url) else { return nil }
            return (item.photoId, RefreshedPhotoURL(photoId: item.photoId, url: url.absoluteString, width: item.width, height: item.height))
        })
        guard !byId.isEmpty else { return self }
        var copy = self
        copy.attachments = attachments.map { attachment in
            guard case .photo(var photo) = attachment, let next = byId[photo.id], let url = URL(string: next.url) else {
                return attachment
            }
            photo.url = url
            if next.width > 0 { photo.width = next.width }
            if next.height > 0 { photo.height = next.height }
            return .photo(photo)
        }
        return copy
    }
}
