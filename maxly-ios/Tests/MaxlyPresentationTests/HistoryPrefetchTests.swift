import Testing
@testable import MaxlyPresentation

@Suite("Prefetch истории до края ленты")
struct HistoryPrefetchTests {
    @Test("Шапка у верха — грузим")
    func headerVisible() {
        #expect(HistoryPrefetch.shouldLoadOlder(
            canLoadOlder: true, isLoadingOlder: false, isRestoringHistory: false, isOpening: false,
            headerVisible: true, visiblePrefix: nil
        ))
    }

    @Test("Первые 20 строк — грузим")
    func nearTopRows() {
        #expect(HistoryPrefetch.shouldLoadOlder(
            canLoadOlder: true, isLoadingOlder: false, isRestoringHistory: false, isOpening: false,
            headerVisible: false, visiblePrefix: 19
        ))
        #expect(!HistoryPrefetch.shouldLoadOlder(
            canLoadOlder: true, isLoadingOlder: false, isRestoringHistory: false, isOpening: false,
            headerVisible: false, visiblePrefix: 20
        ))
    }

    @Test("Открытие и загрузка — не грузим")
    func guards() {
        #expect(!HistoryPrefetch.shouldLoadOlder(
            canLoadOlder: true, isLoadingOlder: false, isRestoringHistory: false, isOpening: true,
            headerVisible: true, visiblePrefix: 0
        ))
        #expect(!HistoryPrefetch.shouldLoadOlder(
            canLoadOlder: true, isLoadingOlder: true, isRestoringHistory: false, isOpening: false,
            headerVisible: true, visiblePrefix: 0
        ))
        #expect(!HistoryPrefetch.shouldLoadOlder(
            canLoadOlder: false, isLoadingOlder: false, isRestoringHistory: false, isOpening: false,
            headerVisible: true, visiblePrefix: 0
        ))
    }
}
