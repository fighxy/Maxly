import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Разметка поля ввода")
struct ComposerFormatTests {
    @Test("Жирный ставится на выделение и снимается вторым нажатием")
    func toggle() {
        var format = ComposerFormat()
        format.toggle(.strong, in: 0..<6)
        #expect(format.spans == [TextSpan(kind: .strong, from: 0, length: 6)])
        #expect(format.isActive(.strong, in: 2..<4))
        #expect(!format.isActive(.strong, in: 4..<8))
        format.toggle(.strong, in: 0..<6)
        #expect(format.spans.isEmpty)
    }

    @Test("Набор перед отрезком сдвигает его, на краю — не расширяет, стёртое выпадает")
    func typing() {
        var format = ComposerFormat()
        format.toggle(.emphasized, in: 8..<11)
        format.textChanged(from: "Привет, мир", to: "Ну, привет, мир")
        // «Ну, п» вместо «П»: вставлено 4 символа в начале.
        #expect(format.spans == [TextSpan(kind: .emphasized, from: 12, length: 3)])
        format.textChanged(from: "Ну, привет, мир", to: "Ну, привет, мир!")
        #expect(format.spans == [TextSpan(kind: .emphasized, from: 12, length: 3)])
        format.textChanged(from: "Ну, привет, мир!", to: "")
        #expect(format.spans.isEmpty)
    }

    @Test("Ссылка: адрес без схемы получает https, пустой снимает, мусор не принимается")
    func link() {
        var format = ComposerFormat()
        let accepted = format.setLink("max.ru", in: 0..<4)
        #expect(accepted)
        #expect(format.link(in: 0..<4) == "https://max.ru")
        let rejected = format.setLink("не ссылка", in: 0..<4)
        #expect(!rejected)
        #expect(format.link(in: 0..<4) == "https://max.ru")
        let removed = format.setLink("", in: 0..<4)
        #expect(removed)
        #expect(format.link(in: 0..<4) == nil)
    }

    @Test("«Обычный» снимает разметку панели, упоминание остаётся")
    func clear() {
        var format = ComposerFormat(spans: [
            TextSpan(kind: .strong, from: 0, length: 5),
            TextSpan(kind: .mention, from: 0, length: 5, userId: "7"),
        ])
        #expect(format.hasFormatting(in: 1..<3))
        format.clear(in: 0..<5)
        #expect(format.spans == [TextSpan(kind: .mention, from: 0, length: 5, userId: "7")])
        #expect(!format.hasFormatting(in: 0..<5))
    }
}
