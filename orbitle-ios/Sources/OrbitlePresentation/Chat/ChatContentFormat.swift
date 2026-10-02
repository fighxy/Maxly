import Foundation
import OrbitleDomain

/// Фаза воспроизведения голосового. Её считает экран, плеер только играет.
/// Расшифровка голосового в пузыре: кнопка «→Т», круг загрузки, раскрытый текст («^») или
/// раскрытая ошибка («^», «Не удалось расшифровать»), как в Komet (KometTeam/Komet#147).
public enum TranscriptPhase: Equatable, Sendable {
    case collapsed
    case loading
    case expanded
    case failed
}

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

/// Реакции в меню сообщения и на плашках.
public enum ReactionPalette {
    /// Быстрые реакции, пока каталог сервера не загрузился.
    public static let fallback = ["👍", "❤️", "🔥", "🤣", "😭", "😍"]
    /// Сколько реакций в быстром ряду меню.
    public static let quickCount = 6

    /// Быстрый ряд: начало каталога сервера (или запасной набор). Своя реакция, которой
    /// нет в ряду, встаёт первой, чтобы её было видно и можно было снять.
    public static func quick(catalog: [String], mine: String? = nil) -> [String] {
        var row = Array((catalog.isEmpty ? fallback : catalog).prefix(quickCount))
        if let mine, !mine.isEmpty, !row.contains(mine) {
            row.insert(mine, at: 0)
            if row.count > quickCount { row.removeLast() }
        }
        return row
    }

    /// Число на плашке: до тысячи как есть, дальше коротко («1,2K», «15K», «3,4M»).
    public static func countText(_ count: Int) -> String {
        let value = max(0, count)
        switch value {
        case ..<1000:
            return "\(value)"
        case ..<1_000_000:
            return short(value, unit: 1000, suffix: "K")
        default:
            return short(value, unit: 1_000_000, suffix: "M")
        }
    }

    private static func short(_ value: Int, unit: Int, suffix: String) -> String {
        let whole = value / unit
        // Десятая доля только у малых чисел и без округления вверх: 1999 — «1,9K».
        let tenth = (value % unit) / (unit / 10)
        if whole >= 10 || tenth == 0 { return "\(whole)\(suffix)" }
        return "\(whole),\(tenth)\(suffix)"
    }
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

/// Скругления плитки альбома: внешний край пластины скруглён, стык внутри прямой.
public struct AlbumCorners: Equatable, Sendable {
    public var topLeft: Bool
    public var topRight: Bool
    public var bottomLeft: Bool
    public var bottomRight: Bool

    public init(topLeft: Bool, topRight: Bool, bottomLeft: Bool, bottomRight: Bool) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
}

/// Прямоугольник одного кадра внутри альбома. Координаты от левого верхнего угла пластины.
public struct AlbumTile: Equatable, Sendable {
    public var index: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var corners: AlbumCorners

    public init(index: Int, x: Double, y: Double, width: Double, height: Double, corners: AlbumCorners) {
        self.index = index
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.corners = corners
    }
}

/// Раскладка нескольких фото и видео одной пластиной.
public struct AlbumLayout: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var gap: Double
    public var tiles: [AlbumTile]

    public init(width: Double, height: Double, gap: Double, tiles: [AlbumTile]) {
        self.width = width
        self.height = height
        self.gap = gap
        self.tiles = tiles
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

/// Кружок, играющий в ленте: id вложения и адрес ролика (файл или поток).
public struct RoundPlayback: Hashable, Sendable {
    public var id: String
    public var url: URL

    public init(id: String, url: URL) {
        self.id = id
        self.url = url
    }
}

/// Открытый просмотр вложений одного сообщения.
public struct MediaViewerRequest: Identifiable, Hashable, Sendable {
    public var id: String
    public var slides: [MediaSlide]
    /// Сообщение, из которого открыт просмотр: по нему сохраняется текущий кадр.
    public var messageId: String?

    public init(id: String, slides: [MediaSlide], messageId: String? = nil) {
        self.id = id
        self.slides = slides
        self.messageId = messageId
    }
}

/// Скачанный файл, который экран открывает предпросмотром.
public struct OpenedFile: Identifiable, Hashable, Sendable {
    public var id: String
    public var url: URL
    public var name: String

    public init(id: String, url: URL, name: String) {
        self.id = id
        self.url = url
        self.name = name
    }
}

/// Склейка пузыря с соседями одного автора.
public struct BubbleGroup: Hashable, Sendable {
    public var joinsPrevious: Bool
    public var joinsNext: Bool

    public init(joinsPrevious: Bool = false, joinsNext: Bool = false) {
        self.joinsPrevious = joinsPrevious
        self.joinsNext = joinsNext
    }

    public static let single = BubbleGroup()
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

    /// Размер файла: байты, затем КБ, МБ и ГБ. Дробь одна и с запятой, чтобы подпись не зависела от локали.
    public static func fileSize(_ bytes: Int64) -> String {
        let value = max(0, bytes)
        if value < 1024 { return "\(value) Б" }
        let units = ["КБ", "МБ", "ГБ"]
        var size = Double(value)
        var unit = -1
        while size >= 1024 && unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        let tenths = Int((size * 10).rounded())
        let whole = tenths / 10
        let fraction = tenths % 10
        if fraction == 0 { return "\(whole) \(units[unit])" }
        return "\(whole),\(fraction) \(units[unit])"
    }

    /// Имя видно у первого сообщения серии. Пустое имя и свои пузыри его не показывают.
    public static func showsAuthorName(outgoing: Bool, authorName: String, authorId: String, previousAuthorId: String?) -> Bool {
        guard !outgoing, !authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let previousAuthorId else { return true }
        return !sameAuthor(authorId, previousAuthorId)
    }

    /// Аватар стоит у последнего сообщения серии, чтобы колонка пузырей не прыгала.
    public static func showsAuthorAvatar(outgoing: Bool, authorId: String, nextAuthorId: String?) -> Bool {
        guard !outgoing else { return false }
        guard let nextAuthorId else { return true }
        return !sameAuthor(authorId, nextAuthorId)
    }

    /// Пузыри одного автора подряд (в пределах `window` и одного дня) слипаются: у склеенной
    /// стороны угол меньше, имя стоит у первого, аватар у последнего.
    public static func group(
        authorId: String,
        date: Date,
        previous: (authorId: String, date: Date)?,
        next: (authorId: String, date: Date)?,
        window: TimeInterval = 10 * 60,
        calendar: Calendar = .current
    ) -> BubbleGroup {
        func joins(_ other: (authorId: String, date: Date)?) -> Bool {
            guard let other, sameAuthor(authorId, other.authorId) else { return false }
            guard abs(other.date.timeIntervalSince(date)) <= window else { return false }
            return calendar.isDate(other.date, inSameDayAs: date)
        }
        return BubbleGroup(joinsPrevious: joins(previous), joinsNext: joins(next))
    }

    /// Перед сообщением нужен заголовок дня: первое в ленте или первое за новый день.
    public static func startsDay(_ date: Date, after previous: Date?, calendar: Calendar = .current) -> Bool {
        guard let previous else { return true }
        return !calendar.isDate(previous, inSameDayAs: date)
    }

    /// «Сегодня», «Вчера», «12 марта», в другом году — «12 марта 2025».
    public static func dayTitle(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Сегодня" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Вчера"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.dateFormat = sameYear ? "d MMMM" : "d MMMM yyyy"
        return formatter.string(from: date)
    }

    /// Прошедшее время голосового по ходу воспроизведения, иначе вся длительность.
    public static func voiceClock(durationMs: Int64, phase: VoicePhase) -> String {
        switch phase {
        case .playing(let progress), .paused(let progress):
            return clock(ms: Int64(Double(max(0, durationMs)) * min(max(progress, 0), 1)))
        default:
            return clock(ms: durationMs)
        }
    }

    /// Один кадр во всю ширину пузыря (у фото с подписью): высота по пропорции в пределах
    /// `minHeight…maxHeight`, лишнее обрезается, а не сужает кадр.
    public static func fullWidthTile(aspect: Double, width: Double, minHeight: Double = 120, maxHeight: Double = 360) -> AlbumLayout {
        let ratio = clampedAspect(aspect)
        let w = max(1, width)
        let h = min(max(w / ratio, minHeight), maxHeight)
        let corners = AlbumCorners(topLeft: true, topRight: true, bottomLeft: true, bottomRight: true)
        return AlbumLayout(width: w, height: h, gap: 0, tiles: [AlbumTile(index: 0, x: 0, y: 0, width: w, height: h, corners: corners)])
    }

    /// Альбом: пропорции кадров собираются в ряды, внешние углы скругляются, внутренние остаются прямыми.
    public static func album(aspects: [Double], maxWidth: Double, maxHeight: Double = 360, gap: Double = 2) -> AlbumLayout {
        let width = max(1, maxWidth)
        let space = max(0, gap)
        let ratios = aspects.map(clampedAspect)
        guard !ratios.isEmpty else { return AlbumLayout(width: 0, height: 0, gap: space, tiles: []) }
        let placed: [Placed]
        if ratios.count == 3, ratios[0] < 1.15 {
            placed = portraitTrio(ratios, width: width, gap: space)
        } else {
            placed = pack(rowCounts(ratios), aspects: ratios, width: width, gap: space)
        }
        return finish(placed, width: width, maxHeight: max(1, maxHeight), gap: space)
    }

    private static func sameAuthor(_ lhs: String, _ rhs: String) -> Bool {
        !lhs.isEmpty && lhs == rhs
    }

    private static func clampedAspect(_ value: Double) -> Double {
        let ratio = value.isFinite && value > 0 ? value : 1
        return min(max(ratio, 0.45), 2.2)
    }

    private static func rowCounts(_ aspects: [Double]) -> [Int] {
        switch aspects.count {
        case 1:
            return [1]
        case 2:
            return aspects.allSatisfy({ $0 >= 1.15 }) ? [1, 1] : [2]
        case 3:
            return [1, 2]
        case 4:
            return [2, 2]
        case 5:
            return [2, 3]
        case 6:
            return [3, 3]
        case 7:
            return [2, 3, 2]
        default:
            var rows: [Int] = []
            var left = aspects.count
            while left > 0 {
                if left == 4 {
                    rows.append(contentsOf: [2, 2])
                    break
                }
                let take = min(3, left)
                rows.append(take)
                left -= take
            }
            return rows
        }
    }

    private static func pack(_ counts: [Int], aspects: [Double], width: Double, gap: Double) -> [Placed] {
        var tiles: [Placed] = []
        var cursor = 0
        var y = 0.0
        for count in counts {
            let slice = Array(aspects[cursor..<(cursor + count)])
            let measured = measure(slice, width: width, gap: gap)
            var x = 0.0
            for (offset, tileWidth) in measured.widths.enumerated() {
                tiles.append(Placed(index: cursor + offset, x: x, y: y, width: tileWidth, height: measured.height))
                x += tileWidth + gap
            }
            y += measured.height + (cursor + count < aspects.count ? gap : 0)
            cursor += count
        }
        return tiles
    }

    private static func measure(_ aspects: [Double], width: Double, gap: Double) -> (height: Double, widths: [Double]) {
        if aspects.count <= 1 {
            let ratio = aspects.first ?? 1
            return (width / ratio, [width])
        }
        let available = max(1, width - gap * Double(aspects.count - 1))
        let height = available / aspects.reduce(0, +)
        return (height, aspects.map { height * $0 })
    }

    /// Узкий первый кадр стоит слева, два остальных делят правую колонку.
    private static func portraitTrio(_ aspects: [Double], width: Double, gap: Double) -> [Placed] {
        let leftWidth = (width - gap) * 0.64
        let rightWidth = width - gap - leftWidth
        let top = rightWidth / aspects[1]
        let bottom = rightWidth / aspects[2]
        let height = top + gap + bottom
        return [
            Placed(index: 0, x: 0, y: 0, width: leftWidth, height: height),
            Placed(index: 1, x: leftWidth + gap, y: 0, width: rightWidth, height: top),
            Placed(index: 2, x: leftWidth + gap, y: top + gap, width: rightWidth, height: bottom),
        ]
    }

    private static func finish(_ placed: [Placed], width: Double, maxHeight: Double, gap: Double) -> AlbumLayout {
        var tiles = placed
        var albumWidth = width
        var albumHeight = tiles.map { $0.y + $0.height }.max() ?? 0
        var albumGap = gap
        tiles = snap(tiles, width: albumWidth, height: albumHeight)
        if albumHeight > maxHeight, albumHeight > 0 {
            let scale = maxHeight / albumHeight
            tiles = tiles.map {
                Placed(index: $0.index, x: $0.x * scale, y: $0.y * scale, width: $0.width * scale, height: $0.height * scale)
            }
            albumWidth *= scale
            albumHeight = maxHeight
            albumGap *= scale
            tiles = snap(tiles, width: albumWidth, height: albumHeight)
        }
        let drawn = tiles.map { tile in
            AlbumTile(
                index: tile.index,
                x: tile.x,
                y: tile.y,
                width: tile.width,
                height: tile.height,
                corners: corners(of: tile, width: albumWidth, height: albumHeight)
            )
        }
        return AlbumLayout(width: albumWidth, height: albumHeight, gap: albumGap, tiles: drawn)
    }

    private static func snap(_ tiles: [Placed], width: Double, height: Double) -> [Placed] {
        tiles.map { tile in
            var copy = tile
            if tile.x + tile.width >= width - 1 { copy.width = max(1, width - tile.x) }
            if tile.y + tile.height >= height - 1 { copy.height = max(1, height - tile.y) }
            return copy
        }
    }

    private static func corners(of tile: Placed, width: Double, height: Double) -> AlbumCorners {
        let eps = 0.5
        return AlbumCorners(
            topLeft: tile.x <= eps && tile.y <= eps,
            topRight: tile.x + tile.width >= width - eps && tile.y <= eps,
            bottomLeft: tile.x <= eps && tile.y + tile.height >= height - eps,
            bottomRight: tile.x + tile.width >= width - eps && tile.y + tile.height >= height - eps
        )
    }

    private struct Placed {
        var index: Int
        var x: Double
        var y: Double
        var width: Double
        var height: Double
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
