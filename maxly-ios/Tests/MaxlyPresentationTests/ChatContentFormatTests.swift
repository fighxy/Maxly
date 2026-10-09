import Foundation
import Testing
@testable import MaxlyPresentation

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

    @Test("Размер файла пишется байтами, килобайтами и мегабайтами")
    func fileSize() {
        #expect(ChatContentFormat.fileSize(0) == "0 Б")
        #expect(ChatContentFormat.fileSize(1023) == "1023 Б")
        #expect(ChatContentFormat.fileSize(1024) == "1 КБ")
        #expect(ChatContentFormat.fileSize(1536) == "1,5 КБ")
        #expect(ChatContentFormat.fileSize(5 * 1024 * 1024) == "5 МБ")
        #expect(ChatContentFormat.fileSize(-4) == "0 Б")
    }

    @Test("Имя у первого в серии, аватар у последнего")
    func authorChrome() {
        #expect(ChatContentFormat.showsAuthorName(outgoing: false, authorName: "Анна", authorId: "2", previousAuthorId: nil))
        #expect(!ChatContentFormat.showsAuthorName(outgoing: false, authorName: "Анна", authorId: "2", previousAuthorId: "2"))
        #expect(ChatContentFormat.showsAuthorName(outgoing: false, authorName: "Анна", authorId: "2", previousAuthorId: "3"))
        #expect(!ChatContentFormat.showsAuthorName(outgoing: true, authorName: "Анна", authorId: "1", previousAuthorId: nil))
        #expect(!ChatContentFormat.showsAuthorName(outgoing: false, authorName: "  ", authorId: "2", previousAuthorId: nil))
        #expect(ChatContentFormat.showsAuthorAvatar(outgoing: false, authorId: "2", nextAuthorId: nil))
        #expect(!ChatContentFormat.showsAuthorAvatar(outgoing: false, authorId: "2", nextAuthorId: "2"))
        #expect(ChatContentFormat.showsAuthorAvatar(outgoing: false, authorId: "2", nextAuthorId: "3"))
        #expect(!ChatContentFormat.showsAuthorAvatar(outgoing: true, authorId: "1", nextAuthorId: nil))
        #expect(ChatContentFormat.showsAuthorAvatar(outgoing: false, authorId: "", nextAuthorId: ""))
    }

    @Test("Альбом держит пропорции, портреты рядом, внешние углы только по краю")
    func album() {
        let landscape = ChatContentFormat.album(aspects: [1.6], maxWidth: 300)
        #expect(landscape.tiles.count == 1)
        #expect(landscape.width == 300)
        #expect(abs(landscape.height - 187.5) < 0.01)
        let only = landscape.tiles[0].corners
        #expect(only.topLeft && only.topRight && only.bottomLeft && only.bottomRight)

        let portraits = ChatContentFormat.album(aspects: [0.7, 0.8], maxWidth: 300)
        #expect(portraits.tiles.count == 2)
        #expect(abs(portraits.tiles[0].y - portraits.tiles[1].y) < 0.01)
        #expect(portraits.tiles[1].x > portraits.tiles[0].x)
        #expect(portraits.tiles[0].corners.topLeft && portraits.tiles[0].corners.bottomLeft)
        #expect(!portraits.tiles[0].corners.topRight && !portraits.tiles[0].corners.bottomRight)
        #expect(portraits.tiles[1].corners.topRight && portraits.tiles[1].corners.bottomRight)
        #expect(!portraits.tiles[1].corners.topLeft && !portraits.tiles[1].corners.bottomLeft)

        let grid = ChatContentFormat.album(aspects: [1, 1, 1, 1], maxWidth: 300)
        #expect(grid.tiles.count == 4)
        #expect(grid.tiles[2].y > grid.tiles[0].y)
        #expect(abs(grid.tiles[0].y - grid.tiles[1].y) < 0.01)
        #expect(abs(grid.tiles[2].y - grid.tiles[3].y) < 0.01)
        #expect(grid.tiles[0].corners.topLeft && !grid.tiles[0].corners.topRight && !grid.tiles[0].corners.bottomLeft)
        #expect(grid.tiles[1].corners.topRight && !grid.tiles[1].corners.bottomRight)
        #expect(grid.tiles[2].corners.bottomLeft && !grid.tiles[2].corners.topLeft)
        #expect(grid.tiles[3].corners.bottomRight && !grid.tiles[3].corners.topLeft)

        let stacked = ChatContentFormat.album(aspects: [1.5, 1.6], maxWidth: 300)
        #expect(stacked.tiles.count == 2)
        #expect(stacked.tiles[0].x == 0)
        #expect(stacked.tiles[1].x == 0)
        #expect(stacked.tiles[1].y > stacked.tiles[0].y)
        #expect(stacked.height <= 360.01)
    }
}
