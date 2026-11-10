import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Prefetch картинок по окну скролла")
struct TranscriptImagePrefetchTests {
    @Test("К новым берёт хвост видимого окна, к истории — голову")
    func directionShiftsWindow() {
        let messages = (0..<30).map { message(id: "m\($0)") }
        let towardNew = TranscriptImagePrefetch.plan(
            messages: messages, visibleRange: 10..<15, scrollingTowardOlder: false, window: 5
        )
        let towardOld = TranscriptImagePrefetch.plan(
            messages: messages, visibleRange: 10..<15, scrollingTowardOlder: true, window: 5
        )
        let newSet = Set(towardNew.urls)
        let oldSet = Set(towardOld.urls)
        let expectedNew = Set(TranscriptImagePrefetch.urls(in: messages[10..<20]))
        let expectedOld = Set(TranscriptImagePrefetch.urls(in: messages[5..<15]))
        #expect(newSet == expectedNew)
        #expect(oldSet == expectedOld)
    }

    @Test("Без видимого диапазона — последние window сообщений")
    func defaultTail() {
        let messages = (0..<40).map { message(id: "m\($0)") }
        let plan = TranscriptImagePrefetch.plan(
            messages: messages, visibleRange: nil, scrollingTowardOlder: false, window: 10
        )
        #expect(Set(plan.urls) == Set(TranscriptImagePrefetch.urls(in: messages[30..<40])))
    }

    /// Размер сервера виден в адресе: `fn=w_<пиксели>` или `fn=sqr_<пиксели>`.
    private struct MarkedSizing: ImageURLSizing {
        func sizedURL(_ url: String, shape: ImageURLShape, neededPixels: Int) -> String {
            "\(url)&fn=\(shape == .square ? "sqr" : "w")_\(neededPixels)"
        }
        func isExpired(_ url: String, nowMillis: Int64) -> Bool { false }
    }

    private func frame() -> TranscriptImagePrefetch.Frame {
        TranscriptImagePrefetch.Frame(bubbleMaxWidth: 300, showsAuthors: true, allowsComments: false, scale: 3, sizing: MarkedSizing())
    }

    private func photoMessage(_ photo: PhotoContent) -> Message {
        Message(
            id: "m1", chatId: "c", authorId: "u", text: "",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000), status: .sent,
            content: MessageContent(attachments: [.photo(photo)]),
            authorAvatarURL: URL(string: "https://cdn.example/a?sig=2")
        )
    }

    @Test("Предзагрузка берёт адрес с размером сервера и размер декодирования пузыря, а не оригинал")
    func requestsMatchBubble() throws {
        let photo = PhotoContent(id: "p", url: URL(string: "https://cdn.example/p?sig=1"), width: 1000, height: 1000)
        let rows = TranscriptLayout.rows([photoMessage(photo)], currentUserId: "me")
        let requests = TranscriptImagePrefetch.requests(rows: rows, visibleRange: nil, scrollingTowardOlder: false, frame: frame())
        #expect(requests.count == 2)

        let tile = try #require(requests.first { $0.url.absoluteString.hasPrefix("https://cdn.example/p?sig=1&fn=w_") })
        let pixels = try #require(Int(tile.url.absoluteString.components(separatedBy: "fn=w_").last ?? ""))
        // Плитка не шире пузыря (300 точек, масштаб 3) и декодируется ступенью по 256.
        #expect(pixels > 0 && pixels <= 900)
        #expect(tile.maxPixel == max(256, (pixels + 255) / 256 * 256))

        // Аватар автора в группе: 34 точки, квадрат сервера.
        let avatar = try #require(requests.first { $0.url.absoluteString.contains("/a?") })
        #expect(avatar.url.absoluteString == "https://cdn.example/a?sig=2&fn=sqr_102")
        #expect(avatar.maxPixel == 102)
    }

    @Test("Своя копия фото на диске не качается; пропавшая копия — уменьшенный адрес, а не оригинал")
    func localCopy() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("maxly-prefetch-\(UUID().uuidString).jpg")
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let remote = URL(string: "https://cdn.example/p?sig=1")
        let kept = PhotoContent(id: "p", url: remote, width: 10, height: 10, localPath: file.path)
        let gone = PhotoContent(id: "p", url: remote, width: 10, height: 10, localPath: file.path + ".missing")
        let sizing = MarkedSizing()

        #expect(TranscriptImagePrefetch.tileURL(.photo(kept), pointSize: 100, scale: 3, sizing: sizing)?.isFileURL == true)
        #expect(TranscriptImagePrefetch.tileURL(.photo(gone), pointSize: 100, scale: 3, sizing: sizing)?.absoluteString
            == "https://cdn.example/p?sig=1&fn=w_300")

        var plain = frame()
        plain.showsAuthors = false
        let keptRows = TranscriptLayout.rows([photoMessage(kept)], currentUserId: "me")
        #expect(TranscriptImagePrefetch.requests(in: keptRows[...], frame: plain).isEmpty)
        let goneRows = TranscriptLayout.rows([photoMessage(gone)], currentUserId: "me")
        let requests = TranscriptImagePrefetch.requests(in: goneRows[...], frame: plain)
        #expect(requests.count == 1)
        #expect(requests.first?.url.absoluteString.contains("&fn=w_") == true)
    }

    @Test("Видимый диапазон за концом ленты не выходит за её границы")
    func staleRangeIsClamped() {
        let messages = (0..<5).map { message(id: "m\($0)") }
        let plan = TranscriptImagePrefetch.plan(messages: messages, visibleRange: 8..<12, scrollingTowardOlder: false, window: 3)
        #expect(Set(plan.urls) == Set(TranscriptImagePrefetch.urls(in: messages[4..<5])))
    }

    private func message(id: String) -> Message {
        Message(
            id: id,
            chatId: "c",
            authorId: "u",
            text: id,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            status: .sent,
            authorAvatarURL: URL(string: "https://example.invalid/\(id).png")
        )
    }
}
