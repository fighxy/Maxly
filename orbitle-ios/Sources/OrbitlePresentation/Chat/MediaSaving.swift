import AVFoundation
import Foundation
import ImageIO
import OrbitleDomain
import UniformTypeIdentifiers

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
    /// «Orbitle 2026-10-01 14.05.33.jpg»: имя с префиксом приложения и по времени
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

/// Форматы сохраняемых файлов: фото — только JPG или PNG, видео — только MP4.
enum SaveFormat {
    /// Папка копий для сохранения: своя на вложение, во временной папке.
    static func folder(for id: String) -> URL {
        let name = id.filter { $0.isLetter || $0.isNumber }
        return FileManager.default.temporaryDirectory
            .appending(path: "OrbitleFiles", directoryHint: .isDirectory)
            .appending(path: name.isEmpty ? "file" : name, directoryHint: .isDirectory)
    }

    /// Картинка в `folder/baseName.jpg|png`. JPEG и PNG копируются как есть, остальное
    /// (WebP, HEIC, GIF, AVIF) перекодируется: с прозрачностью — в PNG, иначе в JPEG 95 %.
    /// Поворот из метаданных сохраняется.
    static func image(at source: URL, in folder: URL, baseName: String) async throws(OrbitleError) -> URL {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let identifier = CGImageSourceGetType(image),
              let type = UTType(identifier as String) else {
            throw .rejected("Не удалось прочитать фото")
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw .storageError
        }
        if type.conforms(to: .jpeg) || type.conforms(to: .png) {
            let target = folder.appending(path: "\(baseName).\(type.conforms(to: .png) ? "png" : "jpg")")
            try copy(source, to: target)
            return target
        }
        guard let frame = CGImageSourceCreateImageAtIndex(image, 0, nil) else {
            throw .rejected("Не удалось прочитать фото")
        }
        let output: UTType = hasAlpha(frame) ? .png : .jpeg
        let target = folder.appending(path: "\(baseName).\(output == .png ? "png" : "jpg")")
        try? FileManager.default.removeItem(at: target)
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, output.identifier as CFString, 1, nil) else {
            throw .storageError
        }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
        if let source = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
           let orientation = source[kCGImagePropertyOrientation] {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, frame, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .storageError }
        return target
    }

    /// Видео в MP4. Уже MP4 (`ftyp` не QuickTime) — копия; QuickTime и неизвестное —
    /// перекладка в MP4 без перекодирования (`AVAssetExportPresetPassthrough`).
    static func video(at source: URL, to target: URL) async throws(OrbitleError) {
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .storageError
        }
        if isMP4(source) {
            try copy(source, to: target)
            return
        }
        try? FileManager.default.removeItem(at: target)
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough) else {
            throw .rejected("Не удалось подготовить видео")
        }
        if #available(iOS 18.0, macOS 15.0, *) {
            do {
                try await session.export(to: target, as: .mp4)
            } catch {
                throw .rejected("Не удалось подготовить видео")
            }
        } else {
            session.outputURL = target
            session.outputFileType = .mp4
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else { throw .rejected("Не удалось подготовить видео") }
        }
    }

    /// MP4 по сигнатуре: `ftyp` и бренд не `qt  ` (тот — QuickTime .mov).
    static func isMP4(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 12), head.count == 12 else { return false }
        let bytes = [UInt8](head)
        guard Array(bytes[4..<8]) == Array("ftyp".utf8) else { return false }
        return String(decoding: bytes[8..<12], as: UTF8.self) != "qt  "
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    private static func copy(_ source: URL, to target: URL) throws(OrbitleError) {
        guard source.standardizedFileURL != target.standardizedFileURL else { return }
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            throw .storageError
        }
    }
}
