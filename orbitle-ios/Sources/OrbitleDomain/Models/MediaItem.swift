import Foundation

/// Тип вложения.
public enum MediaType: String, Codable, Hashable, Sendable {
    case image
    case video
    /// Кружок: круглое видеосообщение.
    case videoNote
    case audio
    case file
}

/// Вложение. Сам файл лежит в дисковом кэше, здесь только метаданные.
public struct MediaItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var type: MediaType
    /// Адрес на сервере.
    public var url: URL
    /// Размер в байтах.
    public var size: Int64
    /// Путь к файлу в кэше, если он уже скачан.
    public var localPath: String?

    public init(id: String, type: MediaType, url: URL, size: Int64, localPath: String? = nil) {
        self.id = id
        self.type = type
        self.url = url
        self.size = size
        self.localPath = localPath
    }
}
