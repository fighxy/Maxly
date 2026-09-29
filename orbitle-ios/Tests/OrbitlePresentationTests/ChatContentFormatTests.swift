import Foundation
import Testing
@testable import OrbitlePresentation

@Suite("Подписи контента")
struct ChatContentFormatTests {
    @Test("Длительность в миллисекундах становится часами пузыря")
    func clock() {
        #expect(ChatContentFormat.clock(ms: 3200) == "0:03")
        #expect(ChatContentFormat.clock(ms: 0) == "0:00")
        #expect(ChatContentFormat.clock(ms: 65_000) == "1:05")
        #expect(ChatContentFormat.clock(ms: -20) == "0:00")
    }

    @Test("Подпись комментариев склоняется")
    func comments() {
        #expect(ChatContentFormat.comments(0) == "Комментировать")
        #expect(ChatContentFormat.comments(-1) == "Комментировать")
        #expect(ChatContentFormat.comments(1) == "1 комментарий")
        #expect(ChatContentFormat.comments(2) == "2 комментария")
        #expect(ChatContentFormat.comments(4) == "4 комментария")
        #expect(ChatContentFormat.comments(5) == "5 комментариев")
        #expect(ChatContentFormat.comments(11) == "11 комментариев")
        #expect(ChatContentFormat.comments(21) == "21 комментарий")
        #expect(ChatContentFormat.comments(22) == "22 комментария")
        #expect(ChatContentFormat.comments(25) == "25 комментариев")
    }

    @Test("Дорожка читается и у тихого голоса, пустая берёт спокойный контур")
    func wave() {
        let calm = ChatContentFormat.waveBars(samples: [])
        #expect(calm.count == 28)
        #expect(calm.allSatisfy { $0 >= 0.12 && $0 <= 1 })
        #expect(calm.max() == 1)

        let bars = ChatContentFormat.waveBars(samples: [10, 200, 40], count: 3)
        #expect(bars.count == 3)
        #expect(bars[0] == 0.12)
        #expect(bars[1] == 1)
        #expect(abs(bars[2] - 0.2) < 0.0001)
    }

    @Test("Кадр не растягивается в ленту и не выше предела")
    func frame() {
        let square = ChatContentFormat.frame(pixelWidth: nil, pixelHeight: nil, maxWidth: 300)
        #expect(square.width == 300)
        #expect(square.height == 300)

        let wide = ChatContentFormat.frame(pixelWidth: 4000, pixelHeight: 100, maxWidth: 300)
        #expect(wide.width == 300)
        #expect(abs(wide.height - 300 / 1.91) < 0.01)

        let tall = ChatContentFormat.frame(pixelWidth: 100, pixelHeight: 4000, maxWidth: 300)
        #expect(tall.height == 420)
        #expect(abs(tall.width - 420 * 0.45) < 0.01)

        let photo = ChatContentFormat.frame(pixelWidth: 800, pixelHeight: 600, maxWidth: 300)
        #expect(photo.width == 300)
        #expect(abs(photo.height - 225) < 0.01)
    }
}
