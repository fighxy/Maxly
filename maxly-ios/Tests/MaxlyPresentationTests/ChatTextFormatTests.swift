import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Текст пузыря: форматирование и цитаты")
struct ChatTextFormatTests {
    @Test("Без цитат — один блок, отрезки на месте")
    func plain() {
        let spans = [TextSpan(kind: .strong, from: 0, length: 6)]
        let blocks = ChatTextFormat.blocks(text: "Жирный и обычный", spans: spans)
        #expect(blocks == [TextBlock(text: "Жирный и обычный", isQuote: false, spans: spans)])
    }

    @Test("Цитата отдельным блоком, отрезки сдвигаются к началу блока, переводы строк на стыках уходят")
    func quote() {
        let text = "Вот:\nцитата тут\nи ответ"
        let spans = [
            TextSpan(kind: .quote, from: 5, length: 10),
            TextSpan(kind: .emphasized, from: 12, length: 3),
            TextSpan(kind: .strong, from: 16, length: 1),
        ]
        let blocks = ChatTextFormat.blocks(text: text, spans: spans)
        #expect(blocks.map(\.text) == ["Вот:", "цитата тут", "и ответ"])
        #expect(blocks.map(\.isQuote) == [false, true, false])
        #expect(blocks[1].spans == [TextSpan(kind: .emphasized, from: 7, length: 3)])
        #expect(blocks[2].spans == [TextSpan(kind: .strong, from: 0, length: 1)])
    }

    @Test("Отрезки за концом текста обрезаются, пустые выбрасываются; смещения в UTF-16")
    func clamping() {
        // «👍» занимает две единицы UTF-16.
        let blocks = ChatTextFormat.blocks(text: "👍 ок", spans: [
            TextSpan(kind: .monospaced, from: 3, length: 50),
            TextSpan(kind: .strong, from: 40, length: 2),
        ])
        #expect(blocks.count == 1)
        #expect(blocks[0].spans == [TextSpan(kind: .monospaced, from: 3, length: 2)])
    }

    @Test("Пустой текст — один пустой блок")
    func empty() {
        #expect(ChatTextFormat.blocks(text: "", spans: []) == [TextBlock(text: "", isQuote: false, spans: [])])
    }
}
