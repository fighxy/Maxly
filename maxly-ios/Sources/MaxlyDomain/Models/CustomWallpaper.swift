import Foundation

/// Своё фото на обоях: общее для всех чатов («Оформление» → «Обои чата») и своё у чата («Ещё» →
/// «Обои» в профиле). Хранится только на устройстве, на сервер ничего не уходит.
///
/// Затемнение и размытие общие для всех фото. Порядок для чата: своё фото чата, затем
/// «Без обоев» чата, затем общее фото, иначе встроенные обои из «Оформления».
public enum CustomWallpaperStyle {
    public static let minDim = 0
    public static let maxDim = 60
    /// Длинная сторона копии фото в пикселях: маленькие фото не растягиваются.
    public static let maxSide = 2560
    /// Радиус размытия в пунктах экрана, когда «Размытие» включено.
    public static let blurRadius = 18.0

    public static func clampDim(_ percent: Int) -> Int { min(max(percent, minDim), maxDim) }

    /// Непрозрачность чёрного слоя поверх фото.
    public static func dimOpacity(_ percent: Int) -> Double { Double(clampDim(percent)) / 100 }

    /// «Затемнение — 20 %».
    public static func dimCaption(_ percent: Int) -> String {
        "Затемнение — \(clampDim(percent))\u{00A0}%"
    }

    /// Размытая копия фото: строится один раз, когда размытие включено, и лежит рядом.
    public static func blurredName(_ file: String) -> String { "blur-" + file }

    /// Размер копии для фото `width`×`height`: длинная сторона не больше `maxSide`, пропорции
    /// сохраняются, маленькие фото не растягиваются, стороны не меньше 1.
    public static func target(width: Int, height: Int, maxSide: Int = maxSide) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (1, 1) }
        let longest = max(width, height)
        guard longest > maxSide else { return (width, height) }
        let scale = Double(maxSide) / Double(longest)
        let w = min(max(Int((Double(width) * scale).rounded()), 1), maxSide)
        let h = min(max(Int((Double(height) * scale).rounded()), 1), maxSide)
        return (w, h)
    }
}

/// Для чего меняется фото: общее или для одного чата (ключ `CustomWallpaperIndex.chatKey`).
public enum WallpaperScope: Hashable, Sendable {
    case global
    case chat(String)
}

/// Что выбрано в «Обоях» чата.
public enum ChatWallpaperChoice: Equatable, Sendable {
    /// «Как в общих»: обои из «Оформления».
    case global
    /// «Без обоев»: в этом чате ровный фон, даже если в «Оформлении» есть обои или фото.
    case plain
    /// «Своё фото…» только для этого чата: имя файла в папке обоев.
    case photo(String)
}

/// Итог для чата: своё фото (имя файла), ровный фон или встроенные обои из «Оформления».
public enum ResolvedChatWallpaper: Equatable, Sendable {
    case photo(String)
    case plain
    case preset
}

/// Все свои обои устройства: `wallpapers.json` в папке обоев.
public struct CustomWallpaperIndex: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// Значение чата «Без обоев».
    public static let plainValue = "plain"

    public var version: Int
    /// Файл общего фото; `nil` — общего фото нет.
    public var global: String?
    /// Затемнение всех фото, `CustomWallpaperStyle.minDim…maxDim` процентов.
    public var dimPercent: Int
    /// Размыть все фото.
    public var blur: Bool
    /// По ключу `chatKey(account:chatId:)`: имя файла своего фото или `plain`. Нет ключа — «Как в общих».
    public var chats: [String: String]

    public init(global: String? = nil, dimPercent: Int = 0, blur: Bool = false, chats: [String: String] = [:]) {
        version = Self.currentVersion
        self.global = global
        self.dimPercent = CustomWallpaperStyle.clampDim(dimPercent)
        self.blur = blur
        self.chats = chats
    }

    public static let empty = CustomWallpaperIndex()

    /// Ключ чата: аккаунт и чат, у разных аккаунтов обои свои.
    public static func chatKey(account: String, chatId: String) -> String { "\(account).\(chatId)" }

    public func choice(chatKey: String) -> ChatWallpaperChoice {
        switch chats[chatKey] {
        case nil, "": .global
        case Self.plainValue: .plain
        case let file?: .photo(file)
        }
    }

    /// Фото чата, затем «Без обоев» чата, затем общее фото, иначе встроенные обои.
    public func resolve(chatKey: String?) -> ResolvedChatWallpaper {
        switch chatKey.map(choice(chatKey:)) ?? .global {
        case .photo(let file): .photo(file)
        case .plain: .plain
        case .global: global.map(ResolvedChatWallpaper.photo) ?? .preset
        }
    }

    /// Файлы фото, на которые есть ссылки (без размытых копий).
    public var photoFiles: Set<String> {
        var names = Set(chats.values.filter { !$0.isEmpty && $0 != Self.plainValue })
        if let global { names.insert(global) }
        return names
    }

    private enum CodingKeys: String, CodingKey { case version, global, dimPercent, blur, chats }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        global = try container.decodeIfPresent(String.self, forKey: .global).flatMap { $0.isEmpty ? nil : $0 }
        dimPercent = CustomWallpaperStyle.clampDim(try container.decodeIfPresent(Int.self, forKey: .dimPercent) ?? 0)
        blur = try container.decodeIfPresent(Bool.self, forKey: .blur) ?? false
        chats = try container.decodeIfPresent([String: String].self, forKey: .chats) ?? [:]
    }
}

/// Своё фото, готовое к показу.
public struct CustomWallpaperBackdrop: Equatable, Sendable {
    /// Копия фото (длинная сторона до 2560 пикселей).
    public let url: URL
    /// Размытая копия рядом; строится один раз при первом показе с размытием.
    public let blurredURL: URL
    public let dimPercent: Int
    public let blur: Bool

    public init(url: URL, blurredURL: URL, dimPercent: Int, blur: Bool) {
        self.url = url
        self.blurredURL = blurredURL
        self.dimPercent = dimPercent
        self.blur = blur
    }

    public var dimOpacity: Double { CustomWallpaperStyle.dimOpacity(dimPercent) }
}

/// Фон ленты чата с учётом своих обоев.
public enum ChatBackground: Equatable, Sendable {
    case photo(CustomWallpaperBackdrop)
    /// «Без обоев» у чата: ровный фон.
    case plain
    /// Встроенные обои из «Оформления».
    case preset

    public var photo: CustomWallpaperBackdrop? {
        if case .photo(let backdrop) = self { backdrop } else { nil }
    }
}

/// Где лежат свои обои. Картинка приходит уже уменьшенной.
@MainActor
public protocol CustomWallpaperStore: AnyObject {
    func load() -> CustomWallpaperIndex
    func url(forFile file: String) -> URL
    /// Записать фото для `scope`; прежнее фото этого `scope` удаляется. Возвращает имя файла.
    @discardableResult
    func savePhoto(_ image: Data, for scope: WallpaperScope) throws -> String
    /// «Как в общих» или «Без обоев» у чата; прежнее фото чата удаляется.
    func setChat(_ chatKey: String, plain: Bool)
    /// «Сбросить» общее фото.
    func resetGlobal()
    func setDim(_ percent: Int)
    func setBlur(_ blur: Bool)
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

    public func url(forFile file: String) -> URL {
        URL(fileURLWithPath: "/memory/wallpapers", isDirectory: true).appendingPathComponent(file)
    }

    public func savePhoto(_ image: Data, for scope: WallpaperScope) throws -> String {
        counter += 1
        let file = "wallpaper-\(counter).jpg"
        images[file] = image
        switch scope {
        case .global:
            drop(index.global)
            index.global = file
        case .chat(let key):
            drop(index.chats[key])
            index.chats[key] = file
        }
        return file
    }

    public func setChat(_ chatKey: String, plain: Bool) {
        drop(index.chats[chatKey])
        index.chats[chatKey] = plain ? CustomWallpaperIndex.plainValue : nil
    }

    public func resetGlobal() {
        drop(index.global)
        index.global = nil
    }

    public func setDim(_ percent: Int) { index.dimPercent = CustomWallpaperStyle.clampDim(percent) }

    public func setBlur(_ blur: Bool) { index.blur = blur }

    private func drop(_ file: String?) {
        guard let file, file != CustomWallpaperIndex.plainValue else { return }
        images[file] = nil
    }
}
