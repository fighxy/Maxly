import Foundation
import Testing
@testable import MaxlyData

/// Разбор ответов gifka.me: образцы сняты с `GET /v1/search` и `GET /v1/media/trending`.
@Suite("gifka.me: разбор ответа")
struct GifkaParsingTests {
    static let search = #"""
{
 "query": "cat",
 "total": 236,
 "items": [
  {
   "id": "oa9phkxg03cc",
   "type": "gif",
   "status": "ready",
   "title": "Месси празднует гол на фоне Газпрома",
   "width": 510,
   "height": 512,
   "renditions": [
    {
     "kind": "mp4",
     "width": 480,
     "height": 482,
     "bytes": 394421,
     "mime": "video/mp4",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/480.mp4",
     "fps": 30,
     "durationMs": 2920,
     "hasAlpha": false
    },
    {
     "kind": "mp4",
     "width": 510,
     "height": 512,
     "bytes": 411678,
     "mime": "video/mp4",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/510.mp4",
     "fps": 30,
     "durationMs": 2920,
     "hasAlpha": false
    },
    {
     "kind": "webp",
     "width": 200,
     "height": 200,
     "bytes": 237994,
     "mime": "image/webp",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/200.webp",
     "fps": 30,
     "durationMs": 2920,
     "hasAlpha": false
    },
    {
     "kind": "webp",
     "width": 480,
     "height": 482,
     "bytes": 1410234,
     "mime": "image/webp",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/480.webp",
     "fps": 30,
     "durationMs": 2920,
     "hasAlpha": false
    },
    {
     "kind": "poster",
     "width": 480,
     "height": 482,
     "bytes": 10082,
     "mime": "image/webp",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/poster.webp",
     "fps": null,
     "durationMs": null,
     "hasAlpha": false
    },
    {
     "kind": "poster_jpeg",
     "width": 320,
     "height": 321,
     "bytes": 10770,
     "mime": "image/jpeg",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/poster.jpg",
     "fps": null,
     "durationMs": null,
     "hasAlpha": false
    }
   ],
   "download": {
    "gif": "https://api.gifka.me/v1/media/oa9phkxg03cc/download/gif",
    "gifReady": true
   },
   "downloadAllowed": true
  },
  {
   "id": "14iw14ab52nz",
   "type": "sticker",
   "status": "ready",
   "title": "Чёрный кот играет палочкой",
   "width": 512,
   "height": 512,
   "renditions": [
    {
     "kind": "webp",
     "width": 200,
     "height": 200,
     "bytes": 228402,
     "mime": "image/webp",
     "url": "https://media.gifka.me/r/14iw14ab52nz/v1/200.webp",
     "fps": 30,
     "durationMs": 2100,
     "hasAlpha": true
    },
    {
     "kind": "webp",
     "width": 512,
     "height": 512,
     "bytes": 1246674,
     "mime": "image/webp",
     "url": "https://media.gifka.me/r/14iw14ab52nz/v1/512.webp",
     "fps": 30,
     "durationMs": 2100,
     "hasAlpha": true
    },
    {
     "kind": "webm_alpha",
     "width": 512,
     "height": 512,
     "bytes": 124077,
     "mime": "video/webm",
     "url": "https://media.gifka.me/r/14iw14ab52nz/v1/512.webm",
     "fps": 30,
     "durationMs": 2100,
     "hasAlpha": true
    },
    {
     "kind": "poster",
     "width": 480,
     "height": 480,
     "bytes": 29824,
     "mime": "image/webp",
     "url": "https://media.gifka.me/r/14iw14ab52nz/v1/poster.webp",
     "fps": null,
     "durationMs": null,
     "hasAlpha": true
    },
    {
     "kind": "poster_jpeg",
     "width": 320,
     "height": 320,
     "bytes": 17368,
     "mime": "image/jpeg",
     "url": "https://media.gifka.me/r/14iw14ab52nz/v1/poster.jpg",
     "fps": null,
     "durationMs": null,
     "hasAlpha": false
    }
   ],
   "download": {
    "gif": "https://api.gifka.me/v1/media/14iw14ab52nz/download/gif",
    "gifReady": false
   },
   "downloadAllowed": true
  },
  {
   "title": "нет id"
  }
 ]
}
"""#

    static let trending = #"""
{
 "items": [
  {
   "id": "oa9phkxg03cc",
   "type": "gif",
   "status": "ready",
   "title": "Месси празднует гол на фоне Газпрома",
   "width": 510,
   "height": 512,
   "renditions": [
    {
     "kind": "mp4",
     "width": 480,
     "height": 482,
     "bytes": 394421,
     "mime": "video/mp4",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/480.mp4",
     "fps": 30,
     "durationMs": 2920,
     "hasAlpha": false
    },
    {
     "kind": "mp4",
     "width": 510,
     "height": 512,
     "bytes": 411678,
     "mime": "video/mp4",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/510.mp4",
     "fps": 30,
     "durationMs": 2920,
     "hasAlpha": false
    },
    {
     "kind": "webp",
     "width": 200,
     "height": 200,
     "bytes": 237994,
     "mime": "image/webp",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/200.webp",
     "fps": 30,
     "durationMs": 2920,
     "hasAlpha": false
    },
    {
     "kind": "webp",
     "width": 480,
     "height": 482,
     "bytes": 1410234,
     "mime": "image/webp",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/480.webp",
     "fps": 30,
     "durationMs": 2920,
     "hasAlpha": false
    },
    {
     "kind": "poster",
     "width": 480,
     "height": 482,
     "bytes": 10082,
     "mime": "image/webp",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/poster.webp",
     "fps": null,
     "durationMs": null,
     "hasAlpha": false
    },
    {
     "kind": "poster_jpeg",
     "width": 320,
     "height": 321,
     "bytes": 10770,
     "mime": "image/jpeg",
     "url": "https://media.gifka.me/r/oa9phkxg03cc/v1/poster.jpg",
     "fps": null,
     "durationMs": null,
     "hasAlpha": false
    }
   ],
   "download": {
    "gif": "https://api.gifka.me/v1/media/oa9phkxg03cc/download/gif",
    "gifReady": true
   },
   "downloadAllowed": true
  }
 ]
}
"""#

    @Test("Поиск: гифка и стикер, элемент без id пропущен")
    func searchPage() throws {
        let page = try GifkaPage.parse(Data(Self.search.utf8))
        #expect(page.total == 236)
        #expect(page.items.map(\.id) == ["oa9phkxg03cc", "14iw14ab52nz"])
        let gif = page.items[0]
        #expect(gif.kind == .gif)
        #expect(gif.downloadAllowed)
        #expect(gif.download?.gif?.absoluteString == "https://api.gifka.me/v1/media/oa9phkxg03cc/download/gif")
        #expect(gif.download?.gifReady == true)
        #expect(gif.previewMP4()?.url.absoluteString == "https://media.gifka.me/r/oa9phkxg03cc/v1/480.mp4")
        #expect(gif.previewWebP()?.width == 200)
        #expect(gif.poster?.kind == "poster_jpeg")
        #expect(abs(gif.aspect - 510.0 / 512.0) < 0.001)
    }

    @Test("Стикер: превью WebP, MP4 нет, GIF ещё не собран")
    func sticker() throws {
        let sticker = try GifkaPage.parse(Data(Self.search.utf8)).items[1]
        #expect(sticker.kind == .sticker)
        #expect(sticker.previewMP4() == nil)
        #expect(sticker.previewWebP()?.url.pathExtension == "webp")
        #expect(sticker.download?.gifReady == false)
        #expect(sticker.download?.gif != nil)
    }

    @Test("Тренды без total")
    func trendingPage() throws {
        let page = try GifkaPage.parse(Data(Self.trending.utf8))
        #expect(page.total == nil)
        #expect(page.items.count == 1)
    }

    @Test("Отправка GIF только с ключом и разрешённым скачиванием")
    func sending() throws {
        let gif = try GifkaPage.parse(Data(Self.search.utf8)).items[0]
        #expect(gif.canSendGIF(hasKey: true))
        #expect(!gif.canSendGIF(hasKey: false))
        let denied = try GifkaPage.parse(Data(#"{"items":[{"id":"x","type":"gif","downloadAllowed":false,"download":{"gif":"https://api.gifka.me/v1/media/x/download/gif"}}]}"#.utf8)).items[0]
        #expect(!denied.canSendGIF(hasKey: true))
    }

    @Test("Пустой ответ и битые рендиции не роняют разбор")
    func lenient() throws {
        #expect(try GifkaPage.parse(Data("{}".utf8)).items.isEmpty)
        let page = try GifkaPage.parse(Data(#"{"items":[{"id":"a","renditions":[{"kind":"mp4"},{"kind":"mp4","url":"https://media.gifka.me/a.mp4","width":100}]}]}"#.utf8))
        #expect(page.items[0].renditions.count == 1)
        #expect(page.items[0].kind == .other)
        #expect(page.items[0].previewMP4(minWidth: 200)?.width == 100)
    }

    @Test("Ключ: пустой и незаполненная переменная сборки — нет ключа, заголовок только с ключом")
    func key() {
        #expect(!GifkaClient(apiKey: nil).hasKey)
        #expect(!GifkaClient(apiKey: "  ").hasKey)
        #expect(!GifkaClient(apiKey: "$(GIFKA_API_KEY)").hasKey)
        let url = GifkaClient.searchURL(query: "кот", type: .gif, limit: 10, offset: 0)
        #expect(GifkaClient(apiKey: nil).request(url).value(forHTTPHeaderField: "X-Api-Key") == nil)
        #expect(GifkaClient(apiKey: "k").request(url).value(forHTTPHeaderField: "X-Api-Key") == "k")
        #expect(!url.absoluteString.contains("api_key"))
    }

    @Test("Адреса поиска и трендов")
    func urls() {
        let search = GifkaClient.searchURL(query: "кот", type: .sticker, limit: 10, offset: 20)
        let items = URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(search.path == "/v1/search")
        #expect(items.first { $0.name == "q" }?.value == "кот")
        #expect(items.first { $0.name == "type" }?.value == "sticker")
        #expect(items.first { $0.name == "offset" }?.value == "20")
        #expect(items.first { $0.name == "rating" }?.value == "pg")
        #expect(GifkaClient.trendingURL(type: .gif, limit: 5, offset: 0).path == "/v1/media/trending")
    }
}
