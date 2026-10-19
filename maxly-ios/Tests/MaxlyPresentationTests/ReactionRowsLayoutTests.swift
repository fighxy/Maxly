import Foundation
import Testing
@testable import MaxlyPresentation

@Suite("Ряды реакций, время и строка комментариев")
struct ReactionRowsLayoutTests {
    /// Плашка «эмодзи и число» высотой 28, время — 34×16.
    private func chips(_ widths: [CGFloat]) -> [CGSize] { widths.map { CGSize(width: $0, height: 28) } }
    private let meta = CGSize(width: 34, height: 16)
    /// Строка комментариев пузыря поста: черта и ряд с отступами.
    private let commentsFooter: CGFloat = 40.5

    /// Верх строки комментариев, если она идёт сразу за рядом реакций с отступами пузыря.
    private func footerTop(_ layout: ReactionRowsLayout, top: CGFloat = 6, bottom: CGFloat = 8) -> CGFloat {
        top + layout.height + bottom
    }

    /// Низ последнего ряда плашек и времени: строка комментариев не должна быть выше.
    private func contentBottom(_ layout: ReactionRowsLayout, top: CGFloat = 6) -> CGFloat {
        let rows = layout.rows.map { $0.y + $0.height }.max() ?? 0
        let time = layout.metaFrame(width: 300).map(\.maxY) ?? 0
        return top + max(rows, time)
    }

    @Test("Один ряд: время в его правом углу, высота — один ряд")
    func oneRow() {
        let layout = ReactionRowsLayout(chips: chips([60, 52, 44]), meta: meta, maxWidth: 280)
        #expect(layout.rows.map(\.items) == [[0, 1, 2]])
        #expect(layout.meta == .lastRow)
        #expect(layout.height == 28)
        #expect(layout.metaFrame(width: 280) == CGRect(x: 246, y: 12, width: 34, height: 16))
        #expect(footerTop(layout) >= contentBottom(layout))
    }

    @Test("Два ряда: высота растёт на ряд, время в последнем ряду")
    func twoRows() {
        // Ширина 200: 60 + 6 + 60 + 6 + 60 = 192, четвёртая плашка уходит на второй ряд.
        let layout = ReactionRowsLayout(chips: chips([60, 60, 60, 50]), meta: meta, maxWidth: 200)
        #expect(layout.rows.map(\.items) == [[0, 1, 2], [3]])
        #expect(layout.rows.map(\.y) == [0, 34])
        #expect(layout.meta == .lastRow)
        #expect(layout.height == CGFloat(28 + 6 + 28))
        #expect(layout.metaFrame(width: 200)?.maxY == layout.height)
        #expect(footerTop(layout) >= contentBottom(layout))
    }

    @Test("Три ряда, как у поста с семью реакциями: строка комментариев ниже всех")
    func threeRowsWithComments() {
        // 😡151 👍61 👎8 / 👌4 🤬3 ✅2 / 🤔1 в ряду шириной 200 (пузырь без отступов).
        let widths: [CGFloat] = [70, 62, 54, 50, 50, 50, 50]
        let layout = ReactionRowsLayout(chips: chips(widths), meta: meta, maxWidth: 200)
        #expect(layout.rows.map(\.items) == [[0, 1, 2], [3, 4, 5], [6]])
        #expect(layout.meta == .lastRow)
        #expect(layout.height == CGFloat(28 * 3 + 6 * 2))
        let bubble = footerTop(layout) + commentsFooter
        #expect(bubble == CGFloat(6 + 96 + 8 + 40.5))
        #expect(footerTop(layout) >= contentBottom(layout))
    }

    @Test("Время не влезает в последний ряд: своя строка, высота её учитывает")
    func metaOnOwnLine() {
        // Последний ряд 60 + 6 + 60 + 6 + 60 = 192: с временем 192 + 8 + 34 > 200.
        let layout = ReactionRowsLayout(chips: chips([60, 60, 60]), meta: meta, maxWidth: 200)
        #expect(layout.rows.count == 1)
        #expect(layout.meta == .ownLine)
        #expect(layout.height == CGFloat(28 + 6 + 16))
        #expect(layout.metaFrame(width: 200) == CGRect(x: 166, y: 34, width: 34, height: 16))
        #expect(footerTop(layout) >= contentBottom(layout))
    }

    @Test("Много рядов: высота растёт с каждым рядом без предела")
    func manyRows() {
        for count in 1...12 {
            let layout = ReactionRowsLayout(chips: chips(Array(repeating: 90, count: count)), meta: meta, maxWidth: 190)
            let rows = (count + 1) / 2
            #expect(layout.rows.count == rows)
            let last = layout.rows.last!
            let metaFits = last.width + 8 + meta.width <= 190
            let expected = CGFloat(rows) * 28 + CGFloat(rows - 1) * 6 + (metaFits ? 0 : 6 + 16)
            #expect(layout.height == expected)
            #expect(footerTop(layout) >= contentBottom(layout))
        }
    }

    @Test("Раскладка на долю точки уже замера не добавляет ряд")
    func roundingKeepsRows() {
        let widths: [CGFloat] = [70, 62, 54, 50, 50, 50, 50]
        let measured = ReactionRowsLayout(chips: chips(widths), meta: meta, maxWidth: 198)
        // Самый широкий ряд ровно 198; SwiftUI может отдать 197.67 после округления до пикселя.
        #expect(measured.rows[0].width == 198)
        let placed = ReactionRowsLayout(chips: chips(widths), meta: meta, maxWidth: 197.67)
        #expect(placed.rows == measured.rows)
        #expect(placed.height == measured.height)
        // Раскладка в ширину, которую ряд сообщил, повторяет замер.
        let reported = ReactionRowsLayout(chips: chips(widths), meta: meta, maxWidth: measured.width)
        #expect(reported.rows == measured.rows && reported.meta == measured.meta)
    }

    @Test("Время выше плашки поднимает последний ряд, без времени — только плашки")
    func tallMetaAndNoMeta() {
        let tall = ReactionRowsLayout(chips: chips([40]), meta: CGSize(width: 34, height: 32), maxWidth: 200)
        #expect(tall.meta == .lastRow && tall.height == 32)
        let none = ReactionRowsLayout(chips: chips([60, 60, 60, 60]), maxWidth: 200)
        #expect(none.meta == nil && none.metaFrame(width: 200) == nil)
        #expect(none.rows.count == 2 && none.height == 62)
        #expect(ReactionRowsLayout(chips: [], maxWidth: 200).height == 0)
    }

    @Test("Без ограничения ширины — один ряд, время в нём")
    func unlimitedWidth() {
        let layout = ReactionRowsLayout(chips: chips([70, 62, 54, 50]), meta: meta, maxWidth: .infinity)
        #expect(layout.rows.count == 1)
        #expect(layout.meta == .lastRow)
        #expect(layout.width == CGFloat(70 + 62 + 54 + 50 + 18 + 8 + 34))
    }
}
