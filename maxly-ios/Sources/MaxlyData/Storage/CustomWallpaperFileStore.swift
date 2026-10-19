import Foundation
import MaxlyDomain

/// Свои обои в `Application Support/Wallpapers`: копии фото (JPEG) и `wallpapers.json`. Только
/// на устройстве, на сервер не уходят, выход из аккаунта их не трогает.
///
/// Копия получает новое имя при каждой записи (`global-<8 hex>.jpg`, `chat-<8 hex>.jpg`): экран,
/// державший прежнюю картинку в памяти, видит новое имя и перечитывает её. Прежняя копия и её
/// размытый вариант (`blur-<имя>`) удаляются сразу, а при открытии стираются и файлы, на
/// которые список не ссылается.
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

    public func url(forFile file: String) -> URL {
        directory.appendingPathComponent(file)
    }

    @discardableResult
    public func savePhoto(_ image: Data, for scope: WallpaperScope) throws -> String {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = Self.fileName(for: scope)
        let target = url(forFile: file)
        try image.write(to: target, options: .atomic)
        var next = index
        let previous: String?
        switch scope {
        case .global:
            previous = next.global
            next.global = file
        case .chat(let key):
            previous = next.chats[key]
            next.chats[key] = file
        }
        do {
            try write(next)
        } catch {
            try? fileManager.removeItem(at: target)
            throw error
        }
        index = next
        deletePhoto(previous)
        return file
    }

    public func setChat(_ chatKey: String, plain: Bool) {
        let previous = index.chats[chatKey]
        var next = index
        next.chats[chatKey] = plain ? CustomWallpaperIndex.plainValue : nil
        guard next != index else { return }
        commit(next)
        deletePhoto(previous)
    }

    public func resetGlobal() {
        guard let previous = index.global else { return }
        var next = index
        next.global = nil
        commit(next)
        deletePhoto(previous)
    }

    public func setDim(_ percent: Int) {
        var next = index
        next.dimPercent = CustomWallpaperStyle.clampDim(percent)
        guard next != index else { return }
        commit(next)
    }

    public func setBlur(_ blur: Bool) {
        var next = index
        next.blur = blur
        guard next != index else { return }
        commit(next)
    }

    /// Имя новой копии: чья она и случайный хвост.
    nonisolated static func fileName(for scope: WallpaperScope, token: String = randomToken()) -> String {
        switch scope {
        case .global: "global-\(token).jpg"
        case .chat: "chat-\(token).jpg"
        }
    }

    nonisolated static func randomToken() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    private func commit(_ next: CustomWallpaperIndex) {
        do {
            try write(next)
        } catch {
            Log.error(.settings, "Обои: список не записан, \(error.localizedDescription)")
        }
        index = next
    }

    /// Копия фото и её размытый вариант. «plain» и чужие пути (с `/`) не трогаются.
    private func deletePhoto(_ file: String?) {
        guard let file, !file.isEmpty, file != CustomWallpaperIndex.plainValue, !file.contains("/") else { return }
        guard !index.photoFiles.contains(file) else { return }
        try? fileManager.removeItem(at: url(forFile: file))
        try? fileManager.removeItem(at: url(forFile: CustomWallpaperStyle.blurredName(file)))
    }

    private func write(_ next: CustomWallpaperIndex) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(next).write(to: directory.appendingPathComponent(Self.indexFile), options: .atomic)
    }

    /// Список с диска. Нет файла или он испорчен — своих обоев нет; фото без файла выпадает
    /// (у чата это «Как в общих»).
    private static func read(_ url: URL) -> CustomWallpaperIndex {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        guard var index = try? JSONDecoder().decode(CustomWallpaperIndex.self, from: data) else {
            Log.error(.settings, "Обои: список не читается, свои обои сброшены")
            return .empty
        }
        let folder = url.deletingLastPathComponent()
        let exists = { (file: String) in
            !file.contains("/") && FileManager.default.fileExists(atPath: folder.appendingPathComponent(file).path)
        }
        if let global = index.global, !exists(global) { index.global = nil }
        index.chats = index.chats.filter { $0.value == CustomWallpaperIndex.plainValue || exists($0.value) }
        return index
    }

    /// Файлы, на которые список не ссылается (запись прервалась): удаляются.
    private func pruneOrphans() {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        let photos = index.photoFiles
        let keep = photos.union(photos.map(CustomWallpaperStyle.blurredName)).union([Self.indexFile])
        for name in names where !keep.contains(name) && !name.hasPrefix(".") {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
