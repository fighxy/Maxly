import Foundation
import OrbitleDomain

/// Куда сохранить вложение с телефона: в медиатеку («Фото») или в «Файлы».
public enum SaveTarget: String, Hashable, Sendable {
    case photos
    case files
}

/// Вложение, готовое к сохранению: файл на устройстве с понятным именем.
public struct SavedFile: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case image
        case video
        /// Голосовые и документы: только в «Файлы».
        case other
    }

    public var url: URL
    public var name: String
    public var kind: Kind

    public init(url: URL, name: String, kind: Kind) {
        self.url = url
        self.name = name
        self.kind = kind
    }
}

/// Медиатека iPhone. Приложение сохраняет через PhotoKit с доступом «только добавление».
public protocol GallerySaving: Sendable {
    func save(_ files: [SavedFile]) async throws(OrbitleError)
}

/// Файлы для системного окна «Сохранить в Файлы». `fromViewer` — окно открывает просмотр
/// фото поверх чата: экран чата под ним показать окно не может.
public struct FileExport: Identifiable, Hashable, Sendable {
    public var id: String
    public var files: [SavedFile]
    public var fromViewer: Bool

    public init(id: String = UUID().uuidString, files: [SavedFile], fromViewer: Bool = false) {
        self.id = id
        self.files = files
        self.fromViewer = fromViewer
    }
}

/// Имена сохраняемых файлов и их тип по первым байтам.
public enum SaveNaming {
    /// «Orbitle 2026-10-01 14.05.33.jpg»: по времени
    /// сообщения, номер для второго и следующих вложений одного сообщения.
    public static func name(for date: Date, index: Int, ext: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "Orbitle \(formatter.string(from: date))" + (index > 0 ? " \(index + 1)" : "")
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// Расширение картинки по сигнатуре: у адресов CDN Max его нет.
    public static func imageExtension(of data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<(offset + prefix.count)]) == prefix
        }
        if starts([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if starts(Array("GIF8".utf8)) { return "gif" }
        if starts(Array("RIFF".utf8)), starts(Array("WEBP".utf8), at: 8) { return "webp" }
        if starts(Array("ftyp".utf8), at: 4) {
            let brand = bytes.count >= 12 ? String(decoding: bytes[8..<12], as: UTF8.self) : ""
            return brand.hasPrefix("avi") ? "avif" : "heic"
        }
        return "jpg"
    }

    /// Расширение файла на диске по сигнатуре; не читается — `fallback`.
    static func imageExtension(of url: URL, fallback: String = "jpg") -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return fallback }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 12), !head.isEmpty else { return fallback }
        return imageExtension(of: head)
    }
}
