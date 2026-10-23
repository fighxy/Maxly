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

    @Test("Оценка не затирает уже измеренную высоту")
    func estimateDoesNotReplaceMeasurement() {
        let cache = BubbleHeightCache()
        let item = row(text: "x", day: nil)
        cache.storeIfAbsent(id: item.id, height: 80)
        cache.store(id: item.id, height: 140)
        cache.storeIfAbsent(id: item.id, height: 80)
        #expect(cache[item.id] == 140)
        cache.remove(id: item.id)
        cache.storeIfAbsent(id: item.id, height: 90)
        #expect(cache[item.id] == 90)
    }

    @Test("Цитата и опрос выше того же текста")
    func replyAndPollAddHeight() {
        let plain = BubbleHeightCache.estimate(row: row(text: "Вопрос?", day: nil), maxWidth: 280)
        let quoted = BubbleHeightCache.estimate(row: row(
            text: "Вопрос?",
            day: nil,
            content: MessageContent(reply: MessageReply(messageId: "1", authorName: "Аня", preview: "Да", kind: .text))
        ), maxWidth: 280)
        let poll = PollContent(id: "p", title: "Вопрос?", answers: [
            PollAnswer(id: "1", text: "Да"), PollAnswer(id: "2", text: "Нет"),
        ])
        let polled = BubbleHeightCache.estimate(row: row(
            text: "Вопрос?",
            day: nil,
            content: MessageContent(attachments: [.poll(poll)])
        ), maxWidth: 280)
        #expect(quoted - plain == BubbleHeightCache.reply)
        #expect(polled - plain == BubbleHeightCache.pollTitle + 2 * BubbleHeightCache.pollAnswer + BubbleHeightCache.pollFooter)
    }

    @Test("textHeightProvider заменяет эвристику символов")
    func textProvider() {
        let previous = BubbleHeightCache.textHeightProvider
        defer { BubbleHeightCache.textHeightProvider = previous }
        BubbleHeightCache.textHeightProvider = { _, _ in 99 }
        let short = BubbleHeightCache.estimate(row: row(text: "hi", day: nil), maxWidth: 280)
        let empty = BubbleHeightCache.estimate(row: row(text: "", day: nil), maxWidth: 280)
        // Provider даёт высоту текста; padding сверху. Пустой ряд без текста берёт minTextBubble,
        // поэтому нельзя сравнивать short с empty+99.
        #expect(short == BubbleHeightCache.bubblePaddingY + 99)
        #expect(short > empty)
    }

    private func row(text: String, day: String?, content: MessageContent = .empty) -> TranscriptRow {
        TranscriptRow(
            message: Message(
                id: "m-\(text.count)-\(day ?? "nil")-\(content.reply == nil ? 0 : 1)-\(content.poll == nil ? 0 : 1)",
                chatId: "c1",
                authorId: "u1",
                text: text,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                status: .sent,
                content: content,
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
