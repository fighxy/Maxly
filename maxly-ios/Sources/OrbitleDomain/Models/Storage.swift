import Foundation

/// Что лежит в кэше устройства. Порядок — как в списке «Данные и память».
public enum StorageCategory: String, CaseIterable, Codable, Hashable, Sendable {
    /// Фото из сообщений и аватары.
    case photos
    case videos
    case videoNotes
    case voice
    case files
    /// Записи и вложения, подготовленные к отправке, временные файлы, системный кэш сети.
    case other

    /// Папка категории внутри `StorageLayout.root`.
    public var folder: String { rawValue }
}

/// Сколько хранить медиа, к которым не обращались (настройка «Хранить медиа»).
public enum KeepMediaPeriod: String, CaseIterable, Codable, Hashable, Sendable {
    case threeDays
    case week
    case month
    case forever

    /// Срок в секундах; `nil` — всегда.
    public var interval: TimeInterval? {
        switch self {
        case .threeDays: TimeInterval(3 * 86_400)
        case .week: TimeInterval(7 * 86_400)
        case .month: TimeInterval(30 * 86_400)
        case .forever: nil
        }
    }
}

/// Предел размера кэша (настройка «Максимальный размер кэша»).
public enum CacheSizeLimit: String, CaseIterable, Codable, Hashable, Sendable {
    case gb1
    case gb5
    case gb20
    case unlimited

    /// Предел в байтах; `nil` — без ограничений.
    public var bytes: Int64? {
        switch self {
        case .gb1: Int64(1) << 30
        case .gb5: Int64(5) << 30
        case .gb20: Int64(20) << 30
        case .unlimited: nil
        }
    }
}

/// Правила кэша: срок хранения и предел размера. Живут на устройстве.
public struct StoragePolicy: Hashable, Codable, Sendable {
    public var keepMedia: KeepMediaPeriod
    public var sizeLimit: CacheSizeLimit

    public init(keepMedia: KeepMediaPeriod = .month, sizeLimit: CacheSizeLimit = .gb5) {
        self.keepMedia = keepMedia
        self.sizeLimit = sizeLimit
    }

    public static let standard = StoragePolicy()
}

/// Сколько места занимает приложение.
public struct StorageUsage: Hashable, Sendable {
    /// Кэш по категориям, байты.
    public var categories: [StorageCategory: Int64]
    /// Локальная база чатов и сообщений. Кэшем не считается и отдельно не чистится.
    public var database: Int64
    /// Свободно на устройстве, если система ответила.
    public var deviceFree: Int64?
    /// Объём устройства, если система ответила.
    public var deviceTotal: Int64?

    public init(categories: [StorageCategory: Int64] = [:], database: Int64 = 0, deviceFree: Int64? = nil, deviceTotal: Int64? = nil) {
        self.categories = categories
        self.database = database
        self.deviceFree = deviceFree
        self.deviceTotal = deviceTotal
    }

    public func bytes(_ category: StorageCategory) -> Int64 { categories[category] ?? 0 }

    /// Весь кэш, без базы.
    public var cache: Int64 { categories.values.reduce(0, +) }

    /// Всё приложение: кэш и база.
    public var total: Int64 { cache + database }
}

/// Папки дискового кэша медиа. Одна раскладка на всё приложение: картинки пишет
/// `ImagePipeline`, остальное — репозиторий медиа, считает и чистит `StorageRepository`.
public struct StorageLayout: Hashable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `Application Support/OrbitleMedia`: система не стирает его сама, как `Caches`, и он
    /// не попадает в резервную копию iCloud.
    public static func standard() throws -> StorageLayout {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var root = support.appending(path: "MaxlyMedia", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        return StorageLayout(root: root)
    }

    public func directory(_ category: StorageCategory) -> URL {
        root.appending(path: category.folder, directoryHint: .isDirectory)
    }

    /// Папка категории, созданная при необходимости.
    public func prepared(_ category: StorageCategory) throws -> URL {
        let url = directory(category)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension MediaType {
    /// Категория кэша для скачанного файла этого типа.
    public var storageCategory: StorageCategory {
        switch self {
        case .image: .photos
        case .video: .videos
        case .videoNote: .videoNotes
        case .audio: .voice
        case .file: .files
        }
    }
}
