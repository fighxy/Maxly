import Foundation
import Observation
import MaxlyDomain

/// Категория обычных эмодзи Unicode («Смайлы и люди», «Животные и природа», …).
public struct EmojiCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let emoji: [String]

    public init(id: String, title: String, systemImage: String, emoji: [String]) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.emoji = emoji
    }
}

/// Ячейка панели эмодзи: обычный эмодзи или анимодзи сервера.
public struct EmojiItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let emoji: String
    /// Анимодзи: в ячейке играет его Lottie, в сообщение он уходит отметкой `ANIMOJI`.
    public let animated: AnimatedEmoji?

    public init(section: String, emoji: String, animated: AnimatedEmoji? = nil) {
        id = section + ":" + (animated.map { "a" + $0.id } ?? emoji)
        self.emoji = emoji
        self.animated = animated
    }
}

/// Раздел панели эмодзи с заголовком и значком на полосе вкладок.
public struct EmojiSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let items: [EmojiItem]
}

/// Раздел панели стикеров: недавние или набор.
public struct StickerSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// Обложка набора на полосе вкладок; у недавних — значок часов.
    public let iconURL: URL?
    public let systemImage: String?
    public let stickerIds: [String]
}

/// Панель эмодзи и стикеров под полем ввода: вместо клавиатуры, две вкладки.
///
/// Эмодзи: «Недавние» (если ими пользовались), «Анимированные» (анимодзи сервера, Lottie из
/// KometTeam/Komet `EmojiPanel`), затем обычные категории Unicode. Стикеры: недавние, затем
/// наборы (свои первыми). Каталоги берутся из кэша сразу и обновляются с сервера.
@MainActor
@Observable
public final class StickerPanelModel {
    public enum Mode: String, Sendable { case emoji, stickers }

    public var mode: Mode = .emoji
    public private(set) var emojiSections: [EmojiSection] = []
    public private(set) var stickerSections: [StickerSection] = []
    /// Загруженные стикеры по id.
    public private(set) var stickers: [String: Sticker] = [:]
    public private(set) var isLoading = false
    public private(set) var failure: String?

    @ObservationIgnored private let repository: (any StickerRepository)?
    @ObservationIgnored private let recents: any RecentStickerStore
    @ObservationIgnored private var animated: [AnimatedEmoji] = []
    @ObservationIgnored private var animatedById: [String: AnimatedEmoji] = [:]
    @ObservationIgnored private var catalog = StickerCatalog()
    @ObservationIgnored private var recentEmoji: [String] = []
    @ObservationIgnored private var recentStickers: [Sticker] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private var refreshed = false

    public static let recentTitle = "Недавние"
    public static let animatedTitle = "Анимированные"
    /// Сколько недавних эмодзи видно в первом разделе (две-три строки).
    public static let recentEmojiShown = 24

    public init(repository: (any StickerRepository)?, recents: any RecentStickerStore) {
        self.repository = repository
        self.recents = recents
        rebuildEmoji()
    }

    /// Открытие панели: кэш сразу, сервер — один раз за запуск.
    public func prepare() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load()
        }
    }

    private func load() async {
        recentEmoji = await recents.recentEmoji()
        recentStickers = await recents.recentStickers()
        for sticker in recentStickers { stickers[sticker.id] = sticker }
        if let repository {
            animated = await repository.cachedAnimatedEmoji()
            if let cached = await repository.cachedCatalog() { catalog = cached }
        }
        indexAnimated()
        rebuildEmoji()
        rebuildStickers()
        guard let repository, !refreshed else { return }
        refreshed = true
        isLoading = stickerSections.isEmpty
        defer { isLoading = false }
        if let fresh = try? await repository.animatedEmoji(), fresh != animated {
            animated = fresh
            indexAnimated()
            rebuildEmoji()
        }
        do {
            catalog = try await repository.catalog()
            failure = nil
        } catch {
            if stickerSections.isEmpty { failure = error.userMessage ?? "Не удалось загрузить стикеры" }
        }
        rebuildStickers()
    }

    /// Повтор после ошибки загрузки стикеров.
    public func retry() {
        refreshed = false
        loadTask = Task { [weak self] in await self?.load() }
    }

    // MARK: Эмодзи

    /// Выбран эмодзи: он запоминается в недавних. Вставку в поле делает экран.
    public func noteEmoji(_ item: EmojiItem) {
        let key = item.animated.map { Self.animatedKey($0.id) } ?? item.emoji
        recentEmoji.removeAll { $0 == key }
        recentEmoji.insert(key, at: 0)
        let recents = recents
        Task { await recents.noteEmoji(key) }
        // Раздел «Недавние» перестраивается при следующем открытии: под пальцем ничего не прыгает.
    }

    /// Панель закрыли — недавние на месте к следующему открытию.
    public func refreshRecents() {
        rebuildEmoji()
        rebuildStickers()
    }

    public func animatedEmoji(id: String) -> AnimatedEmoji? { animatedById[id] }

    private static func animatedKey(_ id: String) -> String { "animoji:" + id }

    private func indexAnimated() {
        animatedById = Dictionary(animated.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func rebuildEmoji() {
        var sections: [EmojiSection] = []
        let recent = recentEmoji.prefix(Self.recentEmojiShown).compactMap { key -> EmojiItem? in
            if key.hasPrefix("animoji:") {
                guard let item = animatedById[String(key.dropFirst("animoji:".count))] else { return nil }
                return EmojiItem(section: "recent", emoji: item.emoji, animated: item)
            }
            return EmojiItem(section: "recent", emoji: key)
        }
        if !recent.isEmpty {
            sections.append(EmojiSection(id: "recent", title: Self.recentTitle, systemImage: "clock", items: recent))
        }
        if !animated.isEmpty {
            sections.append(EmojiSection(
                id: "animated", title: Self.animatedTitle, systemImage: "sparkles",
                items: animated.map { EmojiItem(section: "animated", emoji: $0.emoji, animated: $0) }
            ))
        }
        for category in EmojiCategory.builtIn {
            sections.append(EmojiSection(
                id: category.id, title: category.title, systemImage: category.systemImage,
                items: category.emoji.map { EmojiItem(section: category.id, emoji: $0) }
            ))
        }
        if sections != emojiSections { emojiSections = sections }
    }

    // MARK: Стикеры

    public func noteSticker(_ sticker: Sticker) {
        recentStickers.removeAll { $0.id == sticker.id }
        recentStickers.insert(sticker, at: 0)
        let recents = recents
        Task { await recents.noteSticker(sticker) }
    }

    /// Стикеры раздела, которые ещё не загружены, спрашиваются у сервера (раз на id).
    public func loadStickers(of section: StickerSection) {
        let missing = section.stickerIds.filter { stickers[$0] == nil && !requested.contains($0) }
        guard !missing.isEmpty, let repository else { return }
        requested.formUnion(missing)
        Task { [weak self] in
            guard let loaded = try? await repository.stickers(ids: missing) else {
                self?.requested.subtract(missing)
                return
            }
            guard let self else { return }
            for sticker in loaded { self.stickers[sticker.id] = sticker }
        }
    }

    private func rebuildStickers() {
        var sections: [StickerSection] = []
        var recentIds = recentStickers.map(\.id)
        for id in catalog.recentStickerIds where !recentIds.contains(id) { recentIds.append(id) }
        recentIds = Array(recentIds.prefix(UserDefaultsLimit.stickers))
        if !recentIds.isEmpty {
            sections.append(StickerSection(id: "recent", title: Self.recentTitle, iconURL: nil, systemImage: "clock", stickerIds: recentIds))
        }
        for set in catalog.sets where !set.stickerIds.isEmpty {
            sections.append(StickerSection(id: set.id, title: set.name, iconURL: set.iconURL, systemImage: nil, stickerIds: set.stickerIds))
        }
        if sections != stickerSections { stickerSections = sections }
    }

    private enum UserDefaultsLimit {
        static let stickers = 20
    }
}

/// Анимодзи, вставленные в поле ввода из панели: при отправке их эмодзи в тексте уходят
/// отметками `ANIMOJI` (KometTeam/Komet `RichMessageController.buildContent`).
public struct AnimojiDraft: Equatable, Sendable {
    public private(set) var byEmoji: [String: AnimatedEmoji] = [:]

    public init() {}

    public mutating func insert(_ emoji: AnimatedEmoji) {
        byEmoji[emoji.emoji] = emoji
    }

    public mutating func clear() {
        byEmoji = [:]
    }

    public var isEmpty: Bool { byEmoji.isEmpty }

    /// Отметки для текста: каждое вхождение вставленного анимодзи, смещения UTF-16.
    public func spans(in text: String) -> [TextSpan] {
        guard !byEmoji.isEmpty else { return [] }
        var spans: [TextSpan] = []
        var offset = 0
        for character in text {
            let length = String(character).utf16.count
            if let emoji = byEmoji[String(character)] {
                spans.append(TextSpan(
                    kind: .animoji, from: offset, length: length,
                    url: emoji.lottieURL?.absoluteString, entityId: emoji.id
                ))
            }
            offset += length
        }
        return spans
    }
}
