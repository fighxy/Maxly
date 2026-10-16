import Foundation
import Testing
@testable import MaxlyData

/// Кэш ответов gifka.me и рейтинг выдачи.
@Suite("gifka.me: кэш и рейтинг")
struct GifkaCacheTests {
    /// Часы, которые двигает тест.
    final class Clock: @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1_000_000)
    }

    private let url = GifkaClient.trendingURL(type: .gif, limit: 30, offset: 0)

    @Test("Ответ живёт меньше 10 минут, потом пропадает")
    func expiry() {
        let clock = Clock()
        let cache = GifkaResponseCache(now: { clock.date })
        cache.store(GifkaPage(items: [], total: 7), for: url)
        clock.date += 9 * 60 + 59
        #expect(cache.page(for: url)?.total == 7)
        clock.date += 1
        #expect(cache.page(for: url) == nil)
    }

    @Test("Срок жизни не больше 10 минут даже при большем ttl")
    func ttlCapped() {
        let clock = Clock()
        let cache = GifkaResponseCache(ttl: 24 * 3600, now: { clock.date })
        cache.store(GifkaPage(items: [], total: 1), for: url)
        clock.date += 10 * 60
        #expect(cache.page(for: url) == nil)
    }

    @Test("Разные адреса кэшируются отдельно, лишние вытесняются")
    func capacity() {
        let clock = Clock()
        let cache = GifkaResponseCache(capacity: 2, now: { clock.date })
        let a = GifkaClient.searchURL(query: "a", type: .gif, limit: 30, offset: 0)
        let b = GifkaClient.searchURL(query: "b", type: .gif, limit: 30, offset: 0)
        cache.store(GifkaPage(items: [], total: 1), for: a)
        clock.date += 1
        cache.store(GifkaPage(items: [], total: 2), for: b)
        clock.date += 1
        cache.store(GifkaPage(items: [], total: 3), for: url)
        #expect(cache.page(for: a) == nil)
        #expect(cache.page(for: b)?.total == 2)
        #expect(cache.page(for: url)?.total == 3)
    }

    @Test("Поиск и тренды передают rating=pg13")
    func rating() {
        for url in [
            GifkaClient.searchURL(query: "кот", type: .gif, limit: 10, offset: 0),
            GifkaClient.trendingURL(type: .sticker, limit: 10, offset: 0),
        ] {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(items.filter { $0.name == "rating" }.map(\.value) == ["pg13"])
        }
    }
}
