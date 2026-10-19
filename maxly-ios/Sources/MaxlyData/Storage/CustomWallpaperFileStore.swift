import Foundation
import MaxlyDomain

/// Свои обои в `Application Support/Wallpapers`: JPEG на каждый `scope` и `wallpapers.json`
/// со списком. Только на устройстве, на сервер не уходят, выход из аккаунта их не трогает.
///
/// Файл получает новое имя при каждой записи (`global-<8 hex>.jpg`, `chat-<id>-<8 hex>.jpg`):
/// экран, державший прежнюю картинку в памяти, видит новое имя и перечитывает её. Прежний
/// файл удаляется сразу, а при открытии стираются и файлы, на которые список не ссылается.
@MainActor
public final class FileCustomWallpaperStore: CustomWallpaperStore {
    public static let indexFile = "wallpapers.json"
    public static let folder = "Wallpapers"

    public let directory: URL
    private let fileManager: FileManager
    private var index: CustomWallpaperIndex

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        index = Self.read(directory.appendingPathComponent(Self.indexFile))
        pruneOrphans()
    }

    /// `Application Support/Wallpapers`.
    public static func standard() throws -> FileCustomWallpaperStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FileCustomWallpaperStore(directory: support.appendingPathComponent(folder, isDirectory: true))
    }

    public func load() -> CustomWallpaperIndex { index }

    public func url(for wallpaper: CustomWallpaper) -> URL {
        directory.appendingPathComponent(wallpaper.file)
    }

    @discardableResult
    public func save(image: Data, dim: Double, blur: Double, for scope: WallpaperScope) throws -> CustomWallpaper {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let wallpaper = CustomWallpaper(file: Self.fileName(for: scope), dim: dim, blur: blur)
        let target = url(for: wallpaper)
        try image.write(to: target, options: .atomic)
        var next = index
        let previous = next[scope]
        next[scope] = wallpaper
        do {
            try write(next)
        } catch {
            try? fileManager.removeItem(at: target)
            throw error
        }
        index = next
        if let previous, previous.file != wallpaper.file {
            try? fileManager.removeItem(at: url(for: previous))
        }
        return wallpaper
    }

    public func remove(_ scope: WallpaperScope) {
        guard let previous = index[scope] else { return }
        var next = index
        next[scope] = nil
        do {
            try write(next)
        } catch {
            Log.error(.settings, "Обои: список не записан, \(error.localizedDescription)")
        }
        index = next
        try? fileManager.removeItem(at: url(for: previous))
    }

    /// Имя нового файла: чей он и случайный хвост.
    nonisolated static func fileName(for scope: WallpaperScope, token: String = randomToken()) -> String {
        switch scope {
        case .global: "global-\(token).jpg"
        case .chat(let id): "chat-\(safe(id))-\(token).jpg"
        }
    }

    /// Id чата в имени файла: буквы, цифры, `-` и `_`, остальное — `_`, не длиннее 64.
    nonisolated static func safe(_ id: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let mapped = String(id.prefix(64).map { allowed.contains($0) ? $0 : "_" })
        return mapped.isEmpty ? "_" : mapped
    }

    nonisolated static func randomToken() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    private func write(_ next: CustomWallpaperIndex) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(next).write(to: directory.appendingPathComponent(Self.indexFile), options: .atomic)
    }

    /// Список с диска. Нет файла или он испорчен — своих обоев нет; запись без картинки выпадает.
    private static func read(_ url: URL) -> CustomWallpaperIndex {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        guard var index = try? JSONDecoder().decode(CustomWallpaperIndex.self, from: data) else {
            Log.error(.settings, "Обои: список не читается, свои обои сброшены")
            return .empty
        }
        let folder = url.deletingLastPathComponent()
        let exists = { (wallpaper: CustomWallpaper) in
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(wallpaper.file).path)
        }
        if let global = index.global, !exists(global) { index.global = nil }
        index.chats = index.chats.filter { exists($0.value) }
        return index
    }

    /// Файлы обоев, на которые список не ссылается (запись прервалась): удаляются.
    private func pruneOrphans() {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        let keep = index.files.union([Self.indexFile])
        for name in names where !keep.contains(name) && !name.hasPrefix(".") {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
