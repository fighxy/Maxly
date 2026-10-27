import Foundation
import Testing
@testable import MaxlyPresentation

@Suite("Последние открытые модели")
struct RecentModelsTests {
    @Test("Сверх предела вытесняется самая давно открытая; открытая снова — недавняя")
    func evictsLeastRecent() {
        var cache = RecentModels<String, Int>(capacity: 2)
        #expect(cache.insert(1, for: "a").isEmpty)
        #expect(cache.insert(2, for: "b").isEmpty)
        // «a» открыли снова: давней стала «b».
        #expect(cache.value(for: "a") == 1)
        #expect(cache.insert(3, for: "c") == [2])
        #expect(cache.value(for: "b") == nil)
        #expect(cache.all == [1, 3])
        #expect(cache.count == 2)
    }

    @Test("Оставленные не вытесняются; новая модель не вытесняет саму себя")
    func keepsProtected() {
        var cache = RecentModels<String, Int>(capacity: 2)
        _ = cache.insert(1, for: "a")
        _ = cache.insert(2, for: "b")
        #expect(cache.insert(3, for: "c") { $0 == "a" } == [2])
        #expect(cache.all == [1, 3])
        // Оставить нужно всё: лишняя модель остаётся, новая — тоже.
        #expect(cache.insert(4, for: "d") { _ in true }.isEmpty)
        #expect(cache.count == 3)
        #expect(cache.value(for: "d") == 4)
    }

    @Test("Повторная вставка заменяет модель; очистка убирает всё")
    func replaceAndClear() {
        var cache = RecentModels<String, Int>(capacity: 3)
        _ = cache.insert(1, for: "a")
        _ = cache.insert(5, for: "a")
        #expect(cache.count == 1)
        #expect(cache.value(for: "a") == 5)
        cache.removeAll()
        #expect(cache.count == 0)
        #expect(cache.value(for: "a") == nil)
    }
}
