import Foundation
import MaxlyDomain

/// Стикеры и анимодзи из ядра с кэшем на диске (`Caches/Stickers`): панель открывается сразу,
/// без сети, а каталог обновляется в фоне. Стикеры кэшируются по id и не спрашиваются снова.
public actor CoreStickerRepository: StickerRepository {
    private let core: any MaxCore
    private let directory: URL?
    private var catalogCache: StickerCatalog?
    private var stickerCache: [String: Sticker] = [:]
    private var animojiCache: [AnimatedEmoji]?
    private var loadedFromDisk = false

    public init(core: any MaxCore, directory: URL? = CoreStickerRepository.standardDirectory()) {
        self.core = core
        self.directory = directory
    }

    public static func standardDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Stickers", isDirectory: true)
    }

    public func cachedCatalog() async -> StickerCatalog? {
        restore()
        return catalogCache
    }

    public func catalog() async throws(MaxlyError) -> StickerCatalog {
        restore()
        do {
            let fresh = try await core.loadStickerCatalog()
            catalogCache = fresh
            write(fresh, "catalog.json")
            Log.info(.messages, "Стикеры: \(fresh.sets.count) наборов, \(fresh.recentStickerIds.count) недавних")
            return fresh
        } catch {
            if let catalogCache { return catalogCache }
            Log.warning(.messages, "Каталог стикеров не загрузился: \(error)")
            throw CoreMapping.apiError(error).maxlyError
        }
    }

    public func stickers(ids: [String]) async throws(MaxlyError) -> [Sticker] {
        restore()
        let missing = ids.filter { stickerCache[$0] == nil }
        if !missing.isEmpty {
            do {
                for sticker in try await core.loadStickers(ids: Array(Set(missing))) {
                    stickerCache[sticker.id] = sticker
                }
                write(Array(stickerCache.values), "stickers.json")
            } catch {
                Log.warning(.messages, "Стикеры не загрузились: \(error)")
                if ids.allSatisfy({ stickerCache[$0] == nil }) { throw CoreMapping.apiError(error).maxlyError }
            }
        }
        return ids.compactMap { stickerCache[$0] }
    }

    public func cachedAnimatedEmoji() async -> [AnimatedEmoji] {
        restore()
        return animojiCache ?? []
    }

    public func animatedEmoji() async throws(MaxlyError) -> [AnimatedEmoji] {
        restore()
        do {
            let fresh = try await core.loadAnimatedEmoji().filter { $0.lottieURL != nil || $0.iconURL != nil }
            guard !fresh.isEmpty else { return animojiCache ?? [] }
            animojiCache = fresh
            write(fresh, "animoji.json")
            return fresh
        } catch {
            if let animojiCache { return animojiCache }
            throw CoreMapping.apiError(error).maxlyError
        }
    }

    /// Выход из аккаунта: каталоги чужого аккаунта не нужны.
    public func removeAll() {
        catalogCache = nil
        stickerCache = [:]
        animojiCache = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func restore() {
        guard !loadedFromDisk else { return }
        loadedFromDisk = true
        catalogCache = read(StickerCatalog.self, "catalog.json")
        for sticker in read([Sticker].self, "stickers.json") ?? [] { stickerCache[sticker.id] = sticker }
        animojiCache = read([AnimatedEmoji].self, "animoji.json")
    }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            Log.warning(.messages, "Кэш стикеров не записался: \(error)")
        }
    }
}

/// Недавние эмодзи и стикеры в `UserDefaults` (раздел «Недавние»): последние сверху.
public final class UserDefaultsRecentStickers: RecentStickerStore, @unchecked Sendable {
    public static let emojiLimit = 32
    public static let stickerLimit = 20

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let emojiKey = "maxly.recent.emoji"
    private let stickerKey = "maxly.recent.stickers"

    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func recentEmoji() async -> [String] {
        lock.withLock { defaults.stringArray(forKey: emojiKey) ?? [] }
    }

    public func noteEmoji(_ emoji: String) async {
        lock.withLock {
            var list = defaults.stringArray(forKey: emojiKey) ?? []
            list.removeAll { $0 == emoji }
            list.insert(emoji, at: 0)
            defaults.set(Array(list.prefix(Self.emojiLimit)), forKey: emojiKey)
        }
    }

    public func recentStickers() async -> [Sticker] {
        lock.withLock {
            guard let data = defaults.data(forKey: stickerKey) else { return [] }
            return (try? JSONDecoder().decode([Sticker].self, from: data)) ?? []
        }
    }

    public func noteSticker(_ sticker: Sticker) async {
        lock.withLock {
            var list = (defaults.data(forKey: stickerKey)).flatMap { try? JSONDecoder().decode([Sticker].self, from: $0) } ?? []
            list.removeAll { $0.id == sticker.id }
            list.insert(sticker, at: 0)
            if let data = try? JSONEncoder().encode(Array(list.prefix(Self.stickerLimit))) {
                defaults.set(data, forKey: stickerKey)
            }
        }
    }

    public func clear() {
        lock.withLock {
            defaults.removeObject(forKey: emojiKey)
            defaults.removeObject(forKey: stickerKey)
        }
    }
}
