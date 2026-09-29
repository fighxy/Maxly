import Foundation
import SwiftData
import OrbitlDomain

/// Вложение в локальной базе. Сам файл лежит в дисковом кэше, здесь только метаданные.
@Model
final class SDMediaItem {
    @Attribute(.unique) var id: String
    var typeRaw: String
    /// Адрес на сервере.
    var url: String
    /// Размер в байтах.
    var size: Int64
    /// Путь к файлу в кэше, если он уже скачан (architecture.md, «Медиа»).
    var localPath: String?

    var type: MediaType {
        get { MediaType(rawValue: typeRaw) ?? .file }
        set { typeRaw = newValue.rawValue }
    }

    init(id: String, type: MediaType, url: String, size: Int64, localPath: String? = nil) {
        self.id = id
        self.typeRaw = type.rawValue
        self.url = url
        self.size = size
        self.localPath = localPath
    }
}

extension SDMediaItem {
    /// Доменная модель. `nil`, если в базе лежит некорректный адрес.
    var domain: MediaItem? {
        guard let url = URL(string: url) else { return nil }
        return MediaItem(id: id, type: type, url: url, size: size, localPath: localPath)
    }
}
