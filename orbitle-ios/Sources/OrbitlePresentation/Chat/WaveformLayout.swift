import Foundation

/// Раскладка столбиков дорожки голосового по ширине, которую дал пузырь.
///
/// Ширина и шаг столбиков постоянны по смыслу: столбиков столько, сколько влезает при
/// заданном зазоре, а остаток делится между зазорами поровну — первый столбик у левого
/// края, последний упирается в правый. Пустого хвоста в конце дорожки нет. Громкость
/// пересчитывается под это число столбиков (`ChatContentFormat.waveBars`).
public struct WaveformLayout: Equatable, Sendable {
    public let width: Double
    public let barWidth: Double
    /// Шаг от начала одного столбика до начала следующего.
    public let step: Double
    public let count: Int

    public init(width: Double, barWidth: Double = 3, spacing: Double = 2) {
        let width = max(0, width)
        let bar = max(0.5, min(barWidth, max(width, 0.5)))
        let gap = max(0, spacing)
        let fits = Int(((width + gap) / (bar + gap)).rounded(.down))
        let count = max(1, fits)
        self.width = width
        self.barWidth = bar
        self.count = count
        self.step = count > 1 ? (width - bar) / Double(count - 1) : 0
    }

    /// Левый край столбика `index`.
    public func x(of index: Int) -> Double {
        Double(index) * step
    }

    /// Столбик закрашен, если середина его уже прозвучала: при `progress` 1 закрашена вся
    /// дорожка, при 0 — ничего, между ними граница идёт по всей ширине.
    public func isPlayed(_ index: Int, progress: Double) -> Bool {
        guard progress > 0, width > 0 else { return false }
        if progress >= 1 { return true }
        let middle = x(of: index) + barWidth / 2
        return middle <= progress * width
    }

    /// Доля дорожки под пальцем: `x` — расстояние от левого края дорожки. Левее начала — 0,
    /// правее конца — 1, так что протяжка за край не теряет перемотку. Граница закраски
    /// (`isPlayed`) при этой доле проходит прямо под пальцем.
    public func progress(atX x: Double) -> Double {
        guard width > 0, x.isFinite else { return 0 }
        return min(max(x / width, 0), 1)
    }

    /// Высоты 0.12…1 для каждого столбика: дорожка сервера, сжатая или растянутая под `count`.
    public func heights(samples: [Int]) -> [Double] {
        ChatContentFormat.waveBars(samples: samples, count: count)
    }
}
