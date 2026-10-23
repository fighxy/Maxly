import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Высоты строк ленты")
struct FeedHeightStoreTests {
    private struct Key: Equatable {
        var text: String
        var reactions = 0
    }

    @Test("Отпечаток содержимого: правка текста или реакций делает высоту недействительной")
    func contentChangeInvalidates() {
        let store = FeedHeightStore()
        let original = FeedLayoutKey(Key(text: "привет"))
        #expect(store.store(id: "1", key: original, width: 320, height: 48, source: .measured))
        #expect(store.entry(id: "1", key: original, width: 320)?.height == 48)
        #expect(store.entry(id: "1", key: FeedLayoutKey(Key(text: "привет, как дела?")), width: 320) == nil)
        #expect(store.entry(id: "1", key: FeedLayoutKey(Key(text: "привет", reactions: 1)), width: 320) == nil)
        // Ширина другая (поворот): тоже заново.
        #expect(store.entry(id: "1", key: original, width: 480) == nil)
        // Отпечатки разных типов не равны, даже если похожи.
        #expect(FeedLayoutKey("привет") != FeedLayoutKey(Key(text: "привет")))
        #expect(FeedLayoutKey(Key(text: "a")) == FeedLayoutKey(Key(text: "a")))
    }

    @Test("Оценка не затирает замер, замер — высоту, которую сообщила сама строка")
    func sourcePriority() {
        let store = FeedHeightStore()
        let key = FeedLayoutKey(Key(text: "x"))
        store.store(id: "1", key: key, width: 320, height: 40, source: .estimate)
        #expect(!store.isMeasured(id: "1", key: key, width: 320))
        #expect(store.store(id: "1", key: key, width: 320, height: 64, source: .measured))
        #expect(store.isMeasured(id: "1", key: key, width: 320))
        #expect(!store.store(id: "1", key: key, width: 320, height: 40, source: .estimate))
        #expect(store.entry(id: "1", key: key, width: 320)?.height == 64)
        #expect(store.store(id: "1", key: key, width: 320, height: 70, source: .observed))
        #expect(!store.store(id: "1", key: key, width: 320, height: 64, source: .measured))
        #expect(store.entry(id: "1", key: key, width: 320)?.source == .observed)
        #expect(store.entry(id: "1", key: key, width: 320)?.height == 70)
        // Та же высота — не изменение: лента не перекладывается зря.
        #expect(!store.store(id: "1", key: key, width: 320, height: 70.2, source: .observed))
        // Новое содержимое начинается с чистого листа, и оценка снова принимается.
        let edited = FeedLayoutKey(Key(text: "xy"))
        #expect(store.store(id: "1", key: edited, width: 320, height: 40, source: .estimate))
        #expect(store.entry(id: "1", key: edited, width: 320)?.source == .estimate)
    }

    @Test("Пустые и битые высоты не пишутся, ушедшие строки забываются")
    func invalidAndRetain() {
        let store = FeedHeightStore()
        let key = FeedLayoutKey(Key(text: "x"))
        #expect(!store.store(id: "1", key: key, width: 320, height: 0, source: .measured))
        #expect(!store.store(id: "1", key: key, width: 320, height: .nan, source: .measured))
        #expect(!store.store(id: "1", key: key, width: 0, height: 20, source: .measured))
        store.store(id: "1", key: key, width: 320, height: 20, source: .measured)
        store.store(id: "2", key: key, width: 320, height: 20, source: .measured)
        store.retain(["2"])
        #expect(store.count == 1)
        #expect(store.entry(id: "1", key: key, width: 320) == nil)
        #expect(store.entry(id: "2", key: key, width: 320) != nil)
    }

    @Test("Окно замера: вокруг точки, в пределах ленты")
    func measureWindow() {
        #expect(FeedMeasureWindow.range(focus: 99, count: 100, before: 10, after: 10) == 89..<100)
        #expect(FeedMeasureWindow.range(focus: 0, count: 100, before: 10, after: 5) == 0..<6)
        #expect(FeedMeasureWindow.range(focus: 50, count: 100, before: 2, after: 3) == 48..<54)
        #expect(FeedMeasureWindow.range(focus: 500, count: 3) == 0..<3)
        #expect(FeedMeasureWindow.range(focus: 0, count: 0).isEmpty)
    }

    @Test("Порядок замера при прокрутке: видимые, затем вперёд по прокрутке, затем немного назад")
    func scrollOrder() {
        let down = FeedMeasureWindow.scrollOrder(visible: 10..<13, count: 30, towardOlder: false, ahead: 6)
        #expect(Array(down.prefix(3)) == [10, 11, 12])
        #expect(Array(down.dropFirst(3).prefix(6)) == [13, 14, 15, 16, 17, 18])
        #expect(Array(down.suffix(2)) == [9, 8])
        let up = FeedMeasureWindow.scrollOrder(visible: 10..<13, count: 30, towardOlder: true, ahead: 6)
        #expect(Array(up.dropFirst(3).prefix(6)) == [9, 8, 7, 6, 5, 4])
        #expect(Array(up.suffix(2)) == [13, 14])
        let edge = FeedMeasureWindow.scrollOrder(visible: 0..<2, count: 2, towardOlder: true, ahead: 6)
        #expect(edge == [0, 1])
    }
}

@Suite("Размеры пузыря для оценки")
struct BubbleMetricsTests {
    @Test("Текст переносится по ширине колонки без аватара и полей пузыря")
    func textWidthSubtractsChrome() {
        // Колонка 300: без аватара пузырь 300, текст 276.
        #expect(BubbleMetrics.bubbleWidth(maxWidth: 300, reservesAvatar: false) == 300)
        #expect(BubbleMetrics.textWidth(bubbleWidth: 300) == 276)
        // Входящие в группе: аватар 34 и зазор 6.
        #expect(BubbleMetrics.bubbleWidth(maxWidth: 300, reservesAvatar: true) == 260)
        #expect(BubbleMetrics.textWidth(bubbleWidth: 260) == 236)
        // Узкая колонка не сжимает пузырь меньше его наименьшей ширины.
        #expect(BubbleMetrics.bubbleWidth(maxWidth: 100, reservesAvatar: true) == BubbleMetrics.minBubbleWidth)
    }

    @Test("Оценка меряет текст по ширине строки с местом под время, а аватар группы её сужает")
    func estimateUsesTextWidth() {
        let recorder = Recorder()
        let measure: @Sendable (String, Double) -> Double = { text, width in
            recorder.record(text, width)
            return 20
        }
        let incoming = row(text: "Добрый вечер", outgoing: false)
        _ = BubbleHeightCache.estimate(row: incoming, maxWidth: 300, textHeight: measure)
        _ = BubbleHeightCache.estimate(row: incoming, maxWidth: 300, reservesAvatar: true, textHeight: measure)
        let outgoing = row(text: "Добрый вечер", outgoing: true)
        _ = BubbleHeightCache.estimate(row: outgoing, maxWidth: 300, reservesAvatar: true, textHeight: measure)
        #expect(recorder.widths == [276, 236, 276])
        #expect(recorder.texts.first == "Добрый вечер" + BubbleMetrics.timeReserve(outgoing: false))
        #expect(recorder.texts.last == "Добрый вечер" + BubbleMetrics.timeReserve(outgoing: true))
    }

    @Test("Фото в оценке — той же раскладкой, что в пузыре: страница документа не квадрат")
    func mediaEstimateFollowsAspect() {
        let page = MessageContent(attachments: [.photo(PhotoContent(id: "p", url: nil, width: 1240, height: 1754))])
        let wide = MessageContent(attachments: [.photo(PhotoContent(id: "w", url: nil, width: 2400, height: 1000))])
        let pageHeight = BubbleHeightCache.mediaHeight(page, bubbleWidth: 260, hasFill: false)
        let wideHeight = BubbleHeightCache.mediaHeight(wide, bubbleWidth: 260, hasFill: false)
        // 260 / (1240 / 1754) ≈ 368, предел альбома 360: страница сужается, а не обрезается.
        #expect(abs(pageHeight - 360) < 0.5)
        #expect(abs(wideHeight - 260 / 2.4) < 0.5)
        #expect(BubbleHeightCache.mediaHeight(.empty, bubbleWidth: 260, hasFill: true) == 0)
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var widths: [Double] = []
        private(set) var texts: [String] = []

        func record(_ text: String, _ width: Double) {
            lock.lock(); defer { lock.unlock() }
            widths.append(width)
            texts.append(text)
        }
    }

    private func row(text: String, outgoing: Bool) -> TranscriptRow {
        TranscriptRow(
            message: Message(
                id: "m",
                chatId: "c1",
                authorId: outgoing ? "me" : "u1",
                text: text,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                status: .sent,
                authorName: "A"
            ),
            dayTitle: nil,
            group: .single,
            showsAuthorName: false,
            showsAuthorAvatar: false,
            isOutgoing: outgoing
        )
    }
}
