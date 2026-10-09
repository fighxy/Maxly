import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Стикеры и анимодзи в данных")
struct StickerDataTests {
    @Test("Стикер из attaches сервера: id, картинка, Lottie, размер")
    func serverSticker() throws {
        let json = """
        {"attaches":[{"_type":"STICKER","stickerId":901,"url":"https://st/901.webp","lottieUrl":"https://st/901.json","width":512,"height":512}]}
        """
        let content = MessageContentCodec.decode(json)
        let sticker = try #require(content.sticker)
        #expect(sticker.stickerId == "901")
        #expect(sticker.url == URL(string: "https://st/901.webp"))
        #expect(sticker.isAnimated)
        #expect(sticker.width == 512)
        #expect(content.previewMedia == .sticker)
        // Каноническая запись базы читается обратно тем же стикером.
        #expect(MessageContentCodec.decode(MessageContentCodec.encode(content)).sticker == sticker)
    }

    @Test("ANIMOJI из elements: id и Lottie; отметки для отправки — из разметки")
    func animojiSpans() throws {
        let json = """
        {"elements":[{"type":"ANIMOJI","from":0,"length":2,"entityId":77,"attributes":{"animojiLottieUrl":"https://a/77.json"}}],"attaches":[]}
        """
        let span = try #require(MessageContentCodec.decode(json).formatting?.first)
        #expect(span.kind == .animoji)
        #expect(span.entityId == "77")
        #expect(span.url == "https://a/77.json")
        let marks = CoreAnimojiMark.marks([span, TextSpan(kind: .strong, from: 0, length: 2)])
        #expect(marks == [CoreAnimojiMark(from: 0, length: 2, animojiId: "77", lottieURL: "https://a/77.json")])
    }

    @Test("Черновик стикера: пузырь до ответа сервера и отдельное сообщение без подписи")
    func stickerDraft() {
        let sticker = Sticker(id: "5", url: URL(string: "https://st/5.webp"), lottieURL: URL(string: "https://st/5.json"), width: 512, height: 512)
        let draft = AttachmentDraft.sticker(sticker)
        #expect(draft.preview(index: 0) == .sticker(sticker.content))
        // Codable черновика (он лежит в базе до ответа сервера) не теряет стикер.
        let data = try? JSONEncoder().encode(draft)
        #expect(data.flatMap { try? JSONDecoder().decode(AttachmentDraft.self, from: $0) } == draft)
    }

    @Test("Стикер уходит в ядро своим вызовом, с цитатой")
    func sendsSticker() async throws {
        let core = FakeMaxCore()
        let api = MaxAPIClient(core: core)
        let draft = AttachmentDraft.sticker(Sticker(id: "42", url: URL(string: "https://st/42.webp")))
        let result = await api.sendAttachments(chatId: "c1", drafts: [draft], caption: "", replyTo: "100") { _ in }
        _ = try result.get()
        let calls = await core.stickerCalls
        #expect(calls.count == 1)
        #expect(calls.first?.stickerId == "42")
        #expect(calls.first?.replyTo == "100")
    }

    @Test("Недавние стикеры и эмодзи: новые первыми, без повторов")
    func recents() async {
        let store = UserDefaultsRecentStickers(suiteName: "orbitle.tests.recents.\(UUID().uuidString)")
        await store.noteEmoji("😀")
        await store.noteEmoji("🔥")
        await store.noteEmoji("😀")
        #expect(await store.recentEmoji() == ["😀", "🔥"])
        await store.noteSticker(Sticker(id: "1", url: nil))
        await store.noteSticker(Sticker(id: "2", url: nil))
        await store.noteSticker(Sticker(id: "1", url: nil))
        #expect(await store.recentStickers().map(\.id) == ["1", "2"])
    }

    @Test("Каталог стикеров переживает перезапуск в кэше и отдаётся без сети")
    func catalogCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = StickerCatalog(sets: [StickerSet(id: "s", name: "Кот", stickerIds: ["1", "2"])], recentStickerIds: ["2"])
        let core = FakeMaxCore()
        await core.setStickerCatalog(catalog)
        let online = CoreStickerRepository(core: core, directory: directory)
        #expect(try await online.catalog() == catalog)
        #expect(try await online.stickers(ids: ["2", "1"]).map(\.id) == ["2", "1"])
        let offline = CoreStickerRepository(core: FakeMaxCore(), directory: directory)
        #expect(await offline.cachedCatalog() == catalog)
        #expect(try await offline.catalog() == catalog)
        #expect(try await offline.stickers(ids: ["1"]).map(\.id) == ["1"])
    }
}

