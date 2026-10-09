import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private actor MemoryRecents: RecentStickerStore {
    var emoji: [String]
    var stickers: [Sticker] = []
    init(emoji: [String] = []) { self.emoji = emoji }
    func recentEmoji() async -> [String] { emoji }
    func noteEmoji(_ value: String) async { emoji.removeAll { $0 == value }; emoji.insert(value, at: 0) }
    func recentStickers() async -> [Sticker] { stickers }
    func noteSticker(_ sticker: Sticker) async { stickers.insert(sticker, at: 0) }
}

private struct FakeStickers: StickerRepository {
    var animated: [AnimatedEmoji] = []
    var catalog = StickerCatalog()
    func cachedCatalog() async -> StickerCatalog? { nil }
    func catalog() async throws(MaxlyError) -> StickerCatalog { catalog }
    func stickers(ids: [String]) async throws(MaxlyError) -> [Sticker] { ids.map { Sticker(id: $0, url: nil) } }
    func cachedAnimatedEmoji() async -> [AnimatedEmoji] { [] }
    func animatedEmoji() async throws(MaxlyError) -> [AnimatedEmoji] { animated }
}

@Suite("Панель эмодзи и стикеров")
@MainActor
struct StickerPanelTests {
    private func waitLoaded(_ model: StickerPanelModel) async {
        model.prepare()
        for _ in 0..<50 where model.emojiSections.first?.id != "recent" || model.stickerSections.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Без недавних: сначала анимированные, потом обычные категории")
    func orderWithoutRecents() async {
        let repo = FakeStickers(animated: [AnimatedEmoji(id: "1", emoji: "👍", lottieURL: URL(string: "https://x/1.json"))])
        let model = StickerPanelModel(repository: repo, recents: MemoryRecents())
        model.prepare()
        for _ in 0..<50 where !model.emojiSections.contains(where: { $0.id == "animated" }) {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.emojiSections.map(\.id).prefix(3) == ["animated", "people", "nature"])
        #expect(model.emojiSections.last?.id == "flags")
    }

    @Test("Недавние первыми; использованное анимодзи остаётся анимированным")
    func recentsFirst() async {
        let animated = AnimatedEmoji(id: "7", emoji: "🔥", lottieURL: URL(string: "https://x/7.json"))
        let model = StickerPanelModel(
            repository: FakeStickers(animated: [animated], catalog: StickerCatalog(sets: [StickerSet(id: "s", name: "Кот", stickerIds: ["1"])])),
            recents: MemoryRecents(emoji: ["😀", "animoji:7"])
        )
        await waitLoaded(model)
        let recent = model.emojiSections.first
        #expect(recent?.id == "recent")
        #expect(recent?.items.map(\.emoji) == ["😀", "🔥"])
        #expect(recent?.items.last?.animated?.id == "7")
        #expect(model.emojiSections.dropFirst().first?.id == "animated")
        #expect(model.stickerSections.map(\.id) == ["s"])
    }

    @Test("В разделах обычных эмодзи нет пустых и повторов внутри категории")
    func builtInCategories() {
        for category in EmojiCategory.builtIn {
            #expect(!category.emoji.isEmpty)
            #expect(Set(category.emoji).count == category.emoji.count, "повтор в \(category.id)")
        }
        #expect(EmojiCategory.builtIn.map(\.id) == ["people", "nature", "food", "activity", "travel", "objects", "symbols", "flags"])
    }

    @Test("Вставленные анимодзи становятся отметками со смещениями UTF-16")
    func animojiSpans() {
        var draft = AnimojiDraft()
        draft.insert(AnimatedEmoji(id: "5", emoji: "🔥", lottieURL: URL(string: "https://x/5.json")))
        let spans = draft.spans(in: "ok 🔥 и 🔥")
        #expect(spans.count == 2)
        #expect(spans[0].from == 3)
        #expect(spans[0].length == 2)
        #expect(spans[0].entityId == "5")
        #expect(spans[0].url == "https://x/5.json")
        #expect(spans[1].from == 8)
    }

    @Test("Крупные эмодзи: от одного до трёх, без текста")
    func bigEmoji() {
        #expect(ChatContentFormat.bigEmoji("🔥") == ["🔥"])
        #expect(ChatContentFormat.bigEmoji(" 👍🏽 ❤️ ") == ["👍🏽", "❤️"])
        #expect(ChatContentFormat.bigEmoji("🇷🇺") == ["🇷🇺"])
        #expect(ChatContentFormat.bigEmoji("🔥🔥🔥🔥") == nil)
        #expect(ChatContentFormat.bigEmoji("ok 🔥") == nil)
        #expect(ChatContentFormat.bigEmoji("1") == nil)
        #expect(ChatContentFormat.bigEmoji("") == nil)
    }
}
