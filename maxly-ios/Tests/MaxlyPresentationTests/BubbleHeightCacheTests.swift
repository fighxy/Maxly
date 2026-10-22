import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Кэш высоты пузырей")
struct BubbleHeightCacheTests {
    @Test("Текст выше пустого, день добавляет высоту")
    func estimatesGrowWithContent() {
        let narrow = 280.0
        let empty = row(text: "", day: nil)
        let text = row(text: String(repeating: "слово ", count: 40), day: nil)
        let withDay = row(text: "hi", day: "Сегодня")
        let emptyH = BubbleHeightCache.estimate(row: empty, maxWidth: narrow)
        let textH = BubbleHeightCache.estimate(row: text, maxWidth: narrow)
        let dayH = BubbleHeightCache.estimate(row: withDay, maxWidth: narrow)
        #expect(textH > emptyH)
        #expect(dayH >= BubbleHeightCache.daySeparator)
        #expect(dayH > BubbleHeightCache.estimate(row: row(text: "hi", day: nil), maxWidth: narrow))
    }

    @Test("Измеренная высота перекрывает эвристику")
    func measuredOverrides() {
        let cache = BubbleHeightCache()
        let item = row(text: "x", day: nil)
        cache.store(id: item.id, height: 120)
        #expect(cache.estimated(for: item, maxWidth: 300) == 120)
    }

    @Test("textHeightProvider заменяет эвристику символов")
    func textProvider() {
        let previous = BubbleHeightCache.textHeightProvider
        defer { BubbleHeightCache.textHeightProvider = previous }
        BubbleHeightCache.textHeightProvider = { _, _ in 99 }
        let short = BubbleHeightCache.estimate(row: row(text: "hi", day: nil), maxWidth: 280)
        let empty = BubbleHeightCache.estimate(row: row(text: "", day: nil), maxWidth: 280)
        #expect(short >= empty + 99)
    }

    private func row(text: String, day: String?) -> TranscriptRow {
        TranscriptRow(
            message: Message(
                id: "m-\(text.count)-\(day ?? "nil")",
                chatId: "c1",
                authorId: "u1",
                text: text,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                status: .sent,
                authorName: "A"
            ),
            dayTitle: day,
            group: .single,
            showsAuthorName: false,
            showsAuthorAvatar: false,
            isOutgoing: true
        )
    }
}
