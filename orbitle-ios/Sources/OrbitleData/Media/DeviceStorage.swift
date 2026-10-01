import Foundation
import OrbitleDomain

/// Кэш медиа на устройстве, как «Использование памяти» в Telegram.
///
/// Файлы лежат по папкам категорий (`StorageLayout`). Дата изменения файла — время последнего
/// обращения: её обновляют при чтении из кэша, по ней работают и срок хранения, и вытеснение
/// старого сверх предела. Правила (`StoragePolicy`) хранятся в `UserDefaults`.
public actor DeviceStorage: StorageRepository {
    /// Чужая папка, которую тоже считает «Прочее». Файлы моложе `minimumAge` ещё нужны
    /// (запись идёт, вложение отправляется) и не удаляются.
    public struct Extra: Sendable {
        public let url: URL
        public let minimumAge: TimeInterval

        public init(url: URL, minimumAge: TimeInterval) {
            self.url = url
            self.minimumAge = minimumAge
        }
    }

    struct Entry: Equatable {
        let url: URL
        let size: Int64
        let date: Date
    }

    private let layout: StorageLayout
    private let database: URL?
    private let extras: [Extra]
    private let defaults: UserDefaults
    private let includesSystemCache: Bool
    private let now: @Sendable () -> Date
    private var lastTrim: Date?

    static let keepKey = "storage.keepMedia"
    static let limitKey = "storage.sizeLimit"
    /// Чаще, чем раз в столько секунд, правила после загрузок не применяются.
    static let trimInterval: TimeInterval = 60

    /// - Parameters:
    ///   - database: папка локальной базы; её размер показывается отдельно и не чистится.
    ///   - extras: папки «Прочего» вне `layout` (подготовленные к отправке файлы, `tmp`).
    ///   - defaultsSuite: набор `UserDefaults` для правил; `nil` — стандартный.
    ///   - includesSystemCache: считать и чистить общий `URLCache` (ответы сети).
    public init(
        layout: StorageLayout,
        database: URL? = nil,
        extras: [Extra] = [],
        defaultsSuite: String? = nil,
        includesSystemCache: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.layout = layout
        self.database = database
        self.extras = extras
        self.defaults = defaultsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.includesSystemCache = includesSystemCache
        self.now = now
    }

    // MARK: StorageRepository

    public func usage() async -> StorageUsage {
        var categories: [StorageCategory: Int64] = [:]
        for category in StorageCategory.allCases where category != .other {
            categories[category] = Self.total(Self.files(in: layout.directory(category)))
        }
        var other = Self.total(otherFiles(respectingAge: false))
        if includesSystemCache { other += Int64(URLCache.shared.currentDiskUsage) }
        categories[.other] = other
        let databaseBytes = database.map { Self.total(Self.files(in: $0)) } ?? 0
        let volume = try? layout.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return StorageUsage(
            categories: categories,
            database: databaseBytes,
            deviceFree: volume?.volumeAvailableCapacityForImportantUsage,
            deviceTotal: volume?.volumeTotalCapacity.map(Int64.init)
        )
    }

    public func clear(_ categories: Set<StorageCategory>) async {
        var removed: [Entry] = []
        for category in categories {
            if category == .other {
                removed += otherFiles(respectingAge: true)
            } else {
                removed += Self.files(in: layout.directory(category))
            }
        }
        delete(removed)
        if categories.contains(.other), includesSystemCache {
            URLCache.shared.removeAllCachedResponses()
        }
        Log.info(.media, "Кэш очищен: \(categories.map(\.rawValue).sorted().joined(separator: ", ")), \(removed.count) файлов, \(Self.total(removed)) Б")
    }

    public func policy() async -> StoragePolicy {
        StoragePolicy(
            keepMedia: defaults.string(forKey: Self.keepKey).flatMap(KeepMediaPeriod.init(rawValue:)) ?? StoragePolicy.standard.keepMedia,
            sizeLimit: defaults.string(forKey: Self.limitKey).flatMap(CacheSizeLimit.init(rawValue:)) ?? StoragePolicy.standard.sizeLimit
        )
    }

    public func setPolicy(_ policy: StoragePolicy) async {
        defaults.set(policy.keepMedia.rawValue, forKey: Self.keepKey)
        defaults.set(policy.sizeLimit.rawValue, forKey: Self.limitKey)
        Log.info(.media, "Правила кэша: хранить \(policy.keepMedia.rawValue), предел \(policy.sizeLimit.rawValue)")
        await trim()
    }

    public func trim() async {
        let rules = await policy()
        let moment = now()
        lastTrim = moment
        let removed = Self.expired(cacheFiles(), policy: rules, now: moment)
        guard !removed.isEmpty else { return }
        delete(removed)
        Log.info(.media, "Правила кэша применены: удалено \(removed.count) файлов, \(Self.total(removed)) Б")
    }

    /// Что удалить по правилам: всё старше срока, затем самое давно использованное, пока
    /// остальное не влезет в предел.
    static func expired(_ entries: [Entry], policy: StoragePolicy, now: Date, limit: Int64? = nil) -> [Entry] {
        var kept = entries
        var removed: [Entry] = []
        if let keep = policy.keepMedia.interval {
            let cutoff = now.addingTimeInterval(-keep)
            removed += kept.filter { $0.date < cutoff }
            kept.removeAll { $0.date < cutoff }
        }
        if let limit = limit ?? policy.sizeLimit.bytes {
            kept.sort { $0.date < $1.date }
            var used = Self.total(kept)
            var index = 0
            while used > limit, index < kept.count {
                removed.append(kept[index])
                used -= kept[index].size
                index += 1
            }
        }
        return removed
    }

    /// После загрузки: правила, но не чаще раза в минуту.
    public func trimIfNeeded() async {
        if let lastTrim, now().timeIntervalSince(lastTrim) < Self.trimInterval { return }
        await trim()
    }

    // MARK: Файлы

    /// Всё, что можно удалить по правилам: категории и «Прочее» без свежих файлов.
    private func cacheFiles() -> [Entry] {
        var entries: [Entry] = []
        for category in StorageCategory.allCases where category != .other {
            entries += Self.files(in: layout.directory(category))
        }
        return entries + otherFiles(respectingAge: true)
    }

    /// «Прочее»: своя папка, файлы прежней раскладки прямо в корне и чужие папки.
    private func otherFiles(respectingAge: Bool) -> [Entry] {
        var entries = Self.files(in: layout.directory(.other))
        entries += Self.files(in: layout.root, recursive: false)
        let moment = now()
        for extra in extras {
            let files = Self.files(in: extra.url)
            entries += respectingAge ? files.filter { moment.timeIntervalSince($0.date) >= extra.minimumAge } : files
        }
        return entries
    }

    private func delete(_ entries: [Entry]) {
        for entry in entries {
            try? FileManager.default.removeItem(at: entry.url)
        }
        // В подготовленных к отправке файлах у каждого вложения своя папка: пустые убрать.
        for extra in extras {
            Self.removeEmptyFolders(in: extra.url)
        }
    }

    private static let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]

    private static func files(in directory: URL, recursive: Bool = true) -> [Entry] {
        let manager = FileManager.default
        let urls: [URL]
        if recursive {
            guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) else { return [] }
            urls = enumerator.compactMap { $0 as? URL }
        } else {
            urls = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            return Entry(url: url, size: size, date: values.contentModificationDate ?? .distantPast)
        }
    }

    private static func total(_ entries: [Entry]) -> Int64 {
        entries.reduce(0) { $0 + $1.size }
    }

    private static func removeEmptyFolders(in directory: URL) {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            removeEmptyFolders(in: child)
            if (try? manager.contentsOfDirectory(atPath: child.path).isEmpty) == true {
                try? manager.removeItem(at: child)
            }
        }
    }
}
