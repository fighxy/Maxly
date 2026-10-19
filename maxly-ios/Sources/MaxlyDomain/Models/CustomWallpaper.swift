import Foundation

/// Для чего задано своё фото обоев: для всех чатов или для одного чата или канала.
public enum WallpaperScope: Hashable, Sendable {
    case global
    case chat(String)
}

/// Своё фото за лентой чата. Хранится только на устройстве: картинка уже уменьшена до размера
/// экрана и размыта при сохранении, поэтому экран чата рисует её как есть, одним слоем.
public struct CustomWallpaper: Codable, Equatable, Sendable {
    /// Имя файла в папке обоев (`global-1a2b3c4d.jpg`, `chat-123-1a2b3c4d.jpg`).
    public var file: String
    /// Затемнение в светлой теме, `dimRange`. В тёмной теме фото затемняется сильнее.
    public var dim: Double
    /// Размытие, `0…1`: уже запечено в картинку, хранится для подписи и повторной настройки.
    public var blur: Double
    public var updatedAt: Date

    public static let dimRange: ClosedRange<Double> = 0...0.7
    public static let blurRange: ClosedRange<Double> = 0...1
    public static let defaultDim = 0.1
    public static let defaultBlur = 0.0
    /// Доля оставшейся яркости, которую тёмная тема добавляет к затемнению.
    public static let darkExtra = 0.3
    /// Наибольший радиус размытия в пунктах экрана: `blur == 1`.
    public static let maxBlurRadius = 24.0

    public init(file: String, dim: Double = Self.defaultDim, blur: Double = Self.defaultBlur, updatedAt: Date = Date()) {
        self.file = file
        self.dim = Self.clampDim(dim)
        self.blur = Self.clampBlur(blur)
        // Целые секунды: так же время читается из `wallpapers.json`.
        self.updatedAt = Date(timeIntervalSince1970: updatedAt.timeIntervalSince1970.rounded())
    }

    public static func clampDim(_ value: Double) -> Double {
        guard value.isFinite else { return defaultDim }
        return min(max(value, dimRange.lowerBound), dimRange.upperBound)
    }

    public static func clampBlur(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBlur }
        return min(max(value, blurRange.lowerBound), blurRange.upperBound)
    }

    /// Непрозрачность чёрного слоя поверх фото. В тёмной теме выше: светлое фото не слепит.
    public static func dimOpacity(_ dim: Double, dark: Bool) -> Double {
        let base = clampDim(dim)
        return dark ? base + (1 - base) * darkExtra : base
    }

    public func dimOpacity(dark: Bool) -> Double { Self.dimOpacity(dim, dark: dark) }

    /// Радиус размытия в пунктах экрана.
    public static func blurRadius(_ blur: Double) -> Double { clampBlur(blur) * maxBlurRadius }

    /// «Затемнение 10 %», «Размытие 40 %»: подписи ползунков.
    public static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))\u{00A0}%"
    }

    private enum CodingKeys: String, CodingKey { case file, dim, blur, updatedAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let file = try container.decode(String.self, forKey: .file)
        let dim = try container.decodeIfPresent(Double.self, forKey: .dim) ?? Self.defaultDim
        let blur = try container.decodeIfPresent(Double.self, forKey: .blur) ?? Self.defaultBlur
        let seconds = try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        self.init(file: file, dim: dim, blur: blur, updatedAt: Date(timeIntervalSince1970: seconds))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(file, forKey: .file)
        try container.encode(dim, forKey: .dim)
        try container.encode(blur, forKey: .blur)
        // Секунды Unix: одинаково читаются на всех платформах.
        try container.encode(updatedAt.timeIntervalSince1970.rounded(), forKey: .updatedAt)
    }
}

/// Все свои обои устройства: общие и по чатам (ключ — id чата).
///
/// Порядок выбора для чата: обои этого чата, потом общие, потом встроенные из «Оформления».
public struct CustomWallpaperIndex: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var global: CustomWallpaper?
    public var chats: [String: CustomWallpaper]

    public init(global: CustomWallpaper? = nil, chats: [String: CustomWallpaper] = [:]) {
        version = Self.currentVersion
        self.global = global
        self.chats = chats
    }

    public static let empty = CustomWallpaperIndex()

    public var isEmpty: Bool { global == nil && chats.isEmpty }

    /// Своё фото, заданное именно для `scope` (общие для чата не подставляются).
    public subscript(scope: WallpaperScope) -> CustomWallpaper? {
        get {
            switch scope {
            case .global: global
            case .chat(let id): chats[id]
            }
        }
        set {
            switch scope {
            case .global: global = newValue
            case .chat(let id): chats[id] = newValue
            }
        }
    }

    /// Что показать в чате `chatId`: его обои, иначе общие. `nil` — встроенные из «Оформления».
    public func resolve(chatId: String?) -> CustomWallpaper? {
        if let chatId, let own = chats[chatId] { return own }
        return global
    }

    /// Все файлы, на которые есть ссылки: остальные в папке обоев лишние.
    public var files: Set<String> {
        var names = Set(chats.values.map(\.file))
        if let global { names.insert(global.file) }
        return names
    }

    private enum CodingKeys: String, CodingKey { case version, global, chats }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        global = try container.decodeIfPresent(CustomWallpaper.self, forKey: .global)
        chats = try container.decodeIfPresent([String: CustomWallpaper].self, forKey: .chats) ?? [:]
    }
}

/// Своё фото, готовое к показу: где лежит картинка и насколько её затемнить.
public struct CustomWallpaperBackdrop: Equatable, Sendable {
    public let url: URL
    public let dim: Double
    /// Чьи это обои: чата или общие.
    public let scope: WallpaperScope

    public init(url: URL, dim: Double, scope: WallpaperScope) {
        self.url = url
        self.dim = dim
        self.scope = scope
    }

    public func dimOpacity(dark: Bool) -> Double { CustomWallpaper.dimOpacity(dim, dark: dark) }
}

/// Где лежат свои обои. Картинка приходит уже готовой (уменьшенной и размытой).
@MainActor
public protocol CustomWallpaperStore: AnyObject {
    func load() -> CustomWallpaperIndex
    /// Где лежит файл обоев.
    func url(for wallpaper: CustomWallpaper) -> URL
    /// Записать фото для `scope`; прежний файл этого `scope` удаляется.
    @discardableResult
    func save(image: Data, dim: Double, blur: Double, for scope: WallpaperScope) throws -> CustomWallpaper
    /// Убрать свои обои `scope` вместе с файлом.
    func remove(_ scope: WallpaperScope)
}

/// Свои обои только в памяти: для тестов и превью.
@MainActor
public final class InMemoryCustomWallpaperStore: CustomWallpaperStore {
    public private(set) var index: CustomWallpaperIndex
    public private(set) var images: [String: Data] = [:]
    private var counter = 0

    public init(_ index: CustomWallpaperIndex = .empty) {
        self.index = index
    }

    public func load() -> CustomWallpaperIndex { index }

    public func url(for wallpaper: CustomWallpaper) -> URL {
        URL(fileURLWithPath: "/memory/wallpapers", isDirectory: true).appendingPathComponent(wallpaper.file)
    }

    public func save(image: Data, dim: Double, blur: Double, for scope: WallpaperScope) throws -> CustomWallpaper {
        counter += 1
        if let old = index[scope] { images[old.file] = nil }
        let wallpaper = CustomWallpaper(file: "wallpaper-\(counter).jpg", dim: dim, blur: blur)
        images[wallpaper.file] = image
        index[scope] = wallpaper
        return wallpaper
    }

    public func remove(_ scope: WallpaperScope) {
        if let old = index[scope] { images[old.file] = nil }
        index[scope] = nil
    }
}
