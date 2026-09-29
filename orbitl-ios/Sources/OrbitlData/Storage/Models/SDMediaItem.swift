import Foundation
import SwiftData

/// Тип вложения.
public enum MediaKind: String, Codable, Sendable {
    case photo
    case video
    case audio
    case file
    case sticker
}

/// Вложение в локальной базе. Сам файл лежит в дисковом кэше, здесь только метаданные.
@Model
final class SDMediaItem {
    @Attribute(.unique) var id: String
    var kindRaw: String
    /// Адрес на сервере.
    var url: String
    /// Размер в байтах.
    var size: Int64
    /// Путь к файлу в кэше, если он уже скачан (architecture.md, «Медиа»).
    var localPath: String?

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .file }
        set { kindRaw = newValue.rawValue }
    }

    init(id: String, kind: MediaKind, url: String, size: Int64, localPath: String? = nil) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.url = url
        self.size = size
        self.localPath = localPath
    }
}
