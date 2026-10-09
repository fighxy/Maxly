import Foundation
import Testing
@testable import OrbitlePresentation

@Suite("Дорожка голосового")
struct WaveformLayoutTests {
    @Test("Столбики занимают всю ширину: первый у левого края, последний у правого")
    func fillsWidth() {
        for width in [72.0, 100, 163.5, 190, 241, 300] {
            let layout = WaveformLayout(width: width, barWidth: 3, spacing: 2)
            #expect(layout.x(of: 0) == 0)
            let end = layout.x(of: layout.count - 1) + layout.barWidth
            #expect(abs(end - width) < 0.0001, "ширина \(width)")
            // Зазор не меньше заданного и не больше двух заданных: столбиков столько, сколько влезает.
            let gap = layout.step - layout.barWidth
            #expect(gap >= 2 - 0.0001, "ширина \(width)")
            #expect(gap < 2 + 3 + 2, "ширина \(width)")
        }
    }

    @Test("Число столбиков растёт с шириной")
    func countScales() {
        let narrow = WaveformLayout(width: 100)
        let wide = WaveformLayout(width: 240)
        #expect(narrow.count == 20)
        #expect(wide.count == 48)
        #expect(wide.heights(samples: [1, 5, 3]).count == wide.count)
    }

    @Test("Узкая и нулевая ширина не ломают раскладку")
    func degenerate() {
        let zero = WaveformLayout(width: 0)
        #expect(zero.count == 1)
        #expect(zero.step == 0)
        let one = WaveformLayout(width: 4)
        #expect(one.count == 1)
        #expect(one.x(of: 0) == 0)
    }

    @Test("Прослушанная часть закрашивается по всей ширине")
    func played() {
        let layout = WaveformLayout(width: 200)
        let none = (0..<layout.count).filter { layout.isPlayed($0, progress: 0) }
        #expect(none.isEmpty)
        let all = (0..<layout.count).filter { layout.isPlayed($0, progress: 1) }
        #expect(all.count == layout.count)
        let half = (0..<layout.count).filter { layout.isPlayed($0, progress: 0.5) }
        #expect(half.count == layout.count / 2)
        // Граница монотонна: закрашены ровно первые столбики.
        #expect(half == Array(0..<half.count))
        let quarter = (0..<layout.count).filter { layout.isPlayed($0, progress: 0.25) }.count
        let threeQuarters = (0..<layout.count).filter { layout.isPlayed($0, progress: 0.75) }.count
        #expect(quarter < half.count && half.count < threeQuarters)
        // Последний столбик — только в самом конце.
        #expect(!layout.isPlayed(layout.count - 1, progress: 0.97))
    }

    @Test("Растянутая дорожка плавная, а не ступеньками")
    func upsampleInterpolates() {
        let bars = ChatContentFormat.waveBars(samples: [0, 100], count: 5)
        #expect(bars.count == 5)
        #expect(bars[0] == 0.12)
        #expect(abs(bars[1] - 0.25) < 0.0001)
        #expect(abs(bars[2] - 0.5) < 0.0001)
        #expect(abs(bars[3] - 0.75) < 0.0001)
        #expect(bars[4] == 1)
    }

    @Test("Сжатая дорожка берёт пик отрезка")
    func downsampleKeepsPeaks() {
        let bars = ChatContentFormat.waveBars(samples: [10, 50, 20, 100, 30, 40], count: 3)
        #expect(bars.count == 3)
        #expect(abs(bars[0] - 0.5) < 0.0001)
        #expect(bars[1] == 1)
        #expect(abs(bars[2] - 0.4) < 0.0001)
    }
}
