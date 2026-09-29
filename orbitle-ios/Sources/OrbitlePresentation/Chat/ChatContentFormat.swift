import Foundation
import OrbitleDomain

/// Фаза воспроизведения голосового. Её считает экран, плеер только играет.
public enum VoicePhase: Equatable, Sendable {
    case idle
    case downloading(Double)
    case playing(Double)
    case paused(Double)
    case failed

    public var progress: Double {
        switch self {
        case .playing(let value), .paused(let value), .downloading(let value): value
        default: 0
        }
    }

    public var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}

/// Быстрые реакции в меню сообщения.
public enum ReactionPalette {
    public static let quick = ["❤️", "👍", "👎", "🔥", "😂", "😮", "😢", "🎉"]
}

/// Размер одного кадра в пузыре.
public struct ContentFrame: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// Слайд просмотра фото или видео. Адреса уже выбраны: постер отдельно от файла ролика.
public struct MediaSlide: Identifiable, Hashable, Sendable {
    public var id: String
    public var stillURL: URL?
    public var playURL: URL?
    public var isVideo: Bool

    public init(id: String, stillURL: URL?, playURL: URL?, isVideo: Bool) {
        self.id = id
        self.stillURL = stillURL
        self.playURL = playURL
        self.isVideo = isVideo
    }
}

/// Открытый просмотр вложений одного сообщения.
public struct MediaViewerRequest: Identifiable, Hashable, Sendable {
    public var id: String
    public var slides: [MediaSlide]

    public init(id: String, slides: [MediaSlide]) {
        self.id = id
        self.slides = slides
    }
}

/// Подписи и размеры контента в пузыре. Без SwiftUI, чтобы их считали тесты.
public enum ChatContentFormat {
    public static func clock(ms: Int64) -> String {
        let seconds = max(0, Int(ms / 1000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    public static func comments(_ count: Int) -> String {
        if count <= 0 { return "Комментировать" }
        let n = abs(count) % 100
        let last = n % 10
        if n > 10 && n < 20 { return "\(count) комментариев" }
        if last == 1 { return "\(count) комментарий" }
        if last >= 2 && last <= 4 { return "\(count) комментария" }
        return "\(count) комментариев"
    }

    /// Высоты столбиков 0.12…1. Пик дорожки становится единицей, чтобы тихий голос тоже читался.
    public static func waveBars(samples: [Int], count: Int = 28) -> [Double] {
        let source = samples.isEmpty ? calmWave : samples
        let buckets = max(count, 1)
        let peak = max(source.max() ?? 1, 1)
        var bars: [Double] = []
        bars.reserveCapacity(buckets)
        for index in 0..<buckets {
            let start = index * source.count / buckets
            let end = min(source.count, max(start + 1, (index + 1) * source.count / buckets))
            let slice = source[start..<end]
            let height = Double(slice.max() ?? 0) / Double(peak)
            bars.append(min(max(height, 0.12), 1))
        }
        return bars
    }

    /// Рамка одного кадра: широкие не становятся лентой, высокие не уезжают за экран.
    public static func frame(pixelWidth: Int?, pixelHeight: Int?, maxWidth: Double, maxHeight: Double = 420) -> ContentFrame {
        let widthLimit = max(120, maxWidth)
        let pixelsWide = Double(pixelWidth ?? 0)
        let pixelsHigh = Double(pixelHeight ?? 0)
        let ratio: Double
        if pixelsWide > 0, pixelsHigh > 0 {
            ratio = min(max(pixelsWide / pixelsHigh, 0.45), 1.91)
        } else {
            ratio = 1
        }
        var width = widthLimit
        var height = width / ratio
        if height > maxHeight {
            height = maxHeight
            width = height * ratio
        }
        return ContentFrame(width: width, height: height)
    }

    private static let calmWave = [40, 90, 140, 200, 120, 70, 160, 220, 100, 60, 180, 130, 50, 150, 210, 80]
}

/// Воспроизведение файла. Реализация живёт в приложении: здесь нет AVFoundation.
@MainActor
public protocol VoicePlaying: AnyObject {
    func play(url: URL) -> Bool
    func pause()
    func resume() -> Bool
    func stop()
    var progress: Double { get }
    var isPlaying: Bool { get }
    var failed: Bool { get }
}
