import Foundation
import Testing
import MaxlyDomain

private struct RecordingSizer: ImageURLSizing {
    func sizedURL(_ url: String, shape: ImageURLShape, neededPixels: Int) -> String {
        "\(url)&fn=\(shape.rawValue)-\(neededPixels)"
    }
    func isExpired(_ url: String, nowMillis: Int64) -> Bool { url.contains("expired") }
}

@Suite("Размер картинки")
struct ImageURLTests {
    @Test("Точки умножаются на масштаб экрана, полный экран остаётся без fn")
    func sizing() {
        let raw = URL(string: "https://cdn.example/p")!
        let thumb = ImageURLRequests.url(raw, shape: .square, pointSize: 40, scale: 3, fullScreen: false, sizing: RecordingSizer())
        #expect(thumb?.absoluteString == "https://cdn.example/p&fn=square-120")
        let wide = ImageURLRequests.url(raw, shape: .width, pointSize: 100.2, scale: 2, fullScreen: false, sizing: RecordingSizer())
        #expect(wide?.absoluteString == "https://cdn.example/p&fn=width-201")
        let full = ImageURLRequests.url(raw, shape: .width, pointSize: 400, scale: 3, fullScreen: true, sizing: RecordingSizer())
        #expect(full == raw)
        let file = URL(fileURLWithPath: "/tmp/a.jpg")
        #expect(ImageURLRequests.url(file, shape: .square, pointSize: 40, scale: 2, fullScreen: false, sizing: RecordingSizer()) == file)
    }
}

@Suite("Обновление адресов фото")
struct PhotoRefreshQueueTests {
    @Test("Повторы схлопываются, пачка режется, пауза держит следующую")
    func batching() {
        var queue = PhotoRefreshQueue(maxPerRequest: 2, minIntervalMs: 1_000)
        let first = PhotoRefreshKey(chatId: "c", messageId: "m", photoId: "1")
        let second = PhotoRefreshKey(chatId: "c", messageId: "m", photoId: "2")
        let third = PhotoRefreshKey(chatId: "c", messageId: "n", photoId: "3")
        queue.enqueue([first, first, second, PhotoRefreshKey(chatId: "c", messageId: "m", photoId: "0")])
        #expect(queue.pendingCount == 2)
        #expect(queue.take(nowMs: 5_000) == [first, second])
        queue.enqueue([third, first])
        #expect(queue.take(nowMs: 5_500) == nil)
        #expect(queue.take(nowMs: 6_000) == [third])
        #expect(queue.pendingCount == 0)
    }

    @Test("Неудачная пачка возвращается и уходит после паузы")
    func retry() {
        var queue = PhotoRefreshQueue(maxPerRequest: 100, minIntervalMs: 1_000)
        let key = PhotoRefreshKey(chatId: "c", messageId: "m", photoId: "9")
        queue.enqueue([key])
        let sent = queue.take(nowMs: 1_000)
        queue.requeue(sent ?? [])
        #expect(queue.take(nowMs: 1_500) == nil)
        #expect(queue.take(nowMs: 2_000) == [key])
    }

    @Test("Новый адрес фото заменяет только своё вложение")
    func rewrite() {
        let content = MessageContent(attachments: [
            .photo(PhotoContent(id: "1", url: URL(string: "https://cdn.example/old"))),
            .photo(PhotoContent(id: "2", url: URL(string: "https://cdn.example/keep"))),
        ])
        let next = content.replacingPhotoURLs([
            RefreshedPhotoURL(photoId: "1", url: "https://cdn.example/new", width: 10, height: 20),
            RefreshedPhotoURL(photoId: "9", url: "https://cdn.example/nope"),
            RefreshedPhotoURL(photoId: "2", url: ""),
        ])
        #expect(next.attachments[0].photo?.url?.absoluteString == "https://cdn.example/new")
        #expect(next.attachments[0].photo?.width == 10)
        #expect(next.attachments[1].photo?.url?.absoluteString == "https://cdn.example/keep")
    }
}
