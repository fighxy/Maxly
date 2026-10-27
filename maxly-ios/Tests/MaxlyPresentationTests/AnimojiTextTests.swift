import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Анимодзи в тексте")
struct AnimojiTextTests {
    private let heart = URL(string: "https://lottie/heart.json")!
    private let fire = URL(string: "https://lottie/fire.json")!
    private var catalog: [String: URL] { ["❤️": heart, "🔥": fire] }

    @Test("В тексте: ссылка отметки, иначе каталог; без отметки — буква")
    func inline() {
        let own = URL(string: "https://lottie/own-fire.json")!
        let text = "Привет 🔥 и ❤ и 😀"
        let spans = [
            TextSpan(kind: .animoji, from: 7, length: 2, url: own.absoluteString, entityId: "1"),
            TextSpan(kind: .animoji, from: 12, length: 1, entityId: "2"),
            TextSpan(kind: .strong, from: 0, length: 6),
        ]
        #expect(AnimojiText.inline(text: text, spans: spans, catalog: catalog) == [
            .init(from: 7, length: 2, emoji: "🔥", lottieURL: own),
            .init(from: 12, length: 1, emoji: "❤", lottieURL: heart),
        ])
        #expect(AnimojiText.inline(text: "🔥 огонь", spans: [], catalog: catalog).isEmpty)
        let broken = [TextSpan(kind: .animoji, from: 40, length: 2, entityId: "1")]
        #expect(AnimojiText.inline(text: "🔥", spans: broken, catalog: catalog).isEmpty)
    }

    @Test("Крупные эмодзи: каждое по отметке или каталогу")
    func bigEmoji() {
        let own = URL(string: "https://lottie/own-fire.json")!
        let spans = [TextSpan(kind: .animoji, from: 0, length: 2, url: own.absoluteString, entityId: "1")]
        #expect(AnimojiText.bigEmoji(text: "🔥 ❤️ 😀", emoji: ["🔥", "❤️", "😀"], spans: spans, catalog: catalog) == [own, heart, nil])
    }

    @Test("Каталог не различает селектор FE0F")
    func lookup() {
        #expect(AnimojiText.lookup(catalog: catalog, emoji: "❤") == heart)
        #expect(AnimojiText.lookup(catalog: ["❤": heart], emoji: "❤️") == heart)
        #expect(AnimojiText.lookup(catalog: [:], emoji: "❤️") == nil)
    }
}

@Suite("Анимация реакции")
@MainActor
struct ReactionBurstTests {
    @Test("Поставленная реакция играет один раз, отметка «доиграла» её снимает")
    func burst() async {
        let fire = URL(string: "https://lottie/fire.json")!
        let firePlay = URL(string: "https://lottie/fire-play.json")!
        let laughPlay = URL(string: "https://lottie/laugh-play.json")!
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository())
        model.reactions.loadAnimoji = { AnimojiAssets(animoji: ["🔥": fire], effects: ["🔥": firePlay, "😂": laughPlay]) }
        #expect(await eventually { !model.reactions.animoji.isEmpty })
        await model.reactions.toggle(messageId: "m1", emoji: "🔥")
        let burst = model.reactions.burst
        #expect(burst?.messageId == "m1")
        #expect(burst?.lottieURL == fire)
        #expect(burst?.effectURL == firePlay)
        #expect(burst?.matches(messageId: "m1", emoji: "🔥") == true)
        #expect(burst?.matches(messageId: "m2", emoji: "🔥") == false)
        model.reactions.burstShown((burst?.id ?? 0) + 1)
        #expect(model.reactions.burst == burst)
        model.reactions.burstShown(burst?.id ?? 0)
        #expect(model.reactions.burst == nil)
        await model.reactions.toggle(messageId: "m1", emoji: "😀")
        #expect(model.reactions.burst == nil)
        // Только эффект, без анимации самого значка, — тоже играет.
        await model.reactions.toggle(messageId: "m1", emoji: "😂")
        #expect(model.reactions.burst?.lottieURL == nil)
        #expect(model.reactions.burst?.effectURL == laughPlay)
    }

    @Test("Каталог: эмодзи и эффекты по своим адресам, без пустых")
    func assets() {
        let list = [
            AnimatedEmoji(id: "1", emoji: "❤️", lottieURL: URL(string: "https://l/1"), effectURL: URL(string: "https://p/1")),
            AnimatedEmoji(id: "2", emoji: "👍", lottieURL: URL(string: "https://l/2")),
            AnimatedEmoji(id: "3", emoji: "❤️", lottieURL: URL(string: "https://l/3")),
        ]
        let assets = AnimojiAssets(list)
        #expect(assets.animoji == ["❤️": URL(string: "https://l/1")!, "👍": URL(string: "https://l/2")!])
        #expect(assets.effects == ["❤️": URL(string: "https://p/1")!])
    }
}
