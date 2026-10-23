import Foundation
import MaxlyDomain

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
    /// Фото: что пробовать по порядку, если `stillURL` не загрузился (размеры фото профиля).
    public var fallbackURLs: [URL]
    /// Миниатюра для ленты внизу просмотра; `nil` — `stillURL`.
    public var thumbnailURL: URL?

    public init(id: String, stillURL: URL?, playURL: URL?, isVideo: Bool, fallbackURLs: [URL] = [], thumbnailURL: URL? = nil) {
        self.id = id
        self.thumbnailURL = thumbnailURL
        self.stillURL = stillURL
        self.playURL = playURL
        self.isVideo = isVideo
        self.fallbackURLs = fallbackURLs
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
    /// Шапка просмотра: кто прислал («Вы» — своё) и когда; подпись к фото или видео.
    public var author: String?
    public var date: Date?
    public var caption: String?
    /// Сколько всего кадров, если загружены не все (история фото профиля); `nil` — `slides.count`.
    public var total: Int?

    public init(id: String, slides: [MediaSlide], messageId: String? = nil, author: String? = nil, date: Date? = nil, caption: String? = nil, total: Int? = nil) {
        self.id = id
        self.total = total
        self.slides = slides
        self.messageId = messageId
        self.author = author
        self.date = date
        self.caption = caption
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
    /// Сообщение из одних эмодзи (от одного до трёх, пробелы не в счёт) рисуется крупно без
    /// подложки. `nil` — обычный текст.
    public static func bigEmoji(_ text: String, limit: Int = 3) -> [String]? {
        var found: [String] = []
        for character in text where !character.isWhitespace {
            guard isEmoji(character), found.count < limit else { return nil }
            found.append(String(character))
        }
        return found.isEmpty ? nil : found
    }

    /// Символ — эмодзи: со своим видом эмодзи или с модификатором (флаг, ZWJ, `FE0F`).
    /// Цифры и `#` с одним скаляром сюда не попадают.
    public static func isEmoji(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        return first.properties.isEmoji && character.unicodeScalars.count > 1
    }

    /// Размер шрифта крупных эмодзи: один — крупнее всего.
    public static func bigEmojiSize(count: Int) -> Double {
        switch count {
        case 1: 64
        case 2: 52
        default: 44
        }
    }

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
    ///
    /// Столбиков меньше, чем точек, — каждый берёт громкий пик своего отрезка. Больше (дорожка
    /// растянута на широкий пузырь) — точки плавно интерполируются, а не повторяются
    /// ступеньками.
    public static func waveBars(samples: [Int], count: Int = 28) -> [Double] {
        let source = samples.isEmpty ? calmWave : samples
        let buckets = max(count, 1)
        var raw: [Double] = []
        raw.reserveCapacity(buckets)
        if buckets <= source.count {
            for index in 0..<buckets {
                let start = index * source.count / buckets
                let end = min(source.count, max(start + 1, (index + 1) * source.count / buckets))
                raw.append(Double(source[start..<end].max() ?? 0))
            }
        } else {
            let last = source.count - 1
            for index in 0..<buckets {
                let position = Double(index) * Double(last) / Double(buckets - 1)
                let low = Int(position.rounded(.down))
                let high = min(low + 1, last)
                let t = position - Double(low)
                raw.append(Double(source[low]) * (1 - t) + Double(source[high]) * t)
            }
        }
        let peak = max(raw.max() ?? 0, 1)
        return raw.map { min(max($0 / peak, 0.12), 1) }
    }

    /// Рамка одного кадра. Картинка целиком внутри предела: высокая становится уже,
    /// широкая — ниже. Пропорцию не подменяем, иначе края фото обрезаются.
    public static func frame(pixelWidth: Int?, pixelHeight: Int?, maxWidth: Double, maxHeight: Double = 420) -> ContentFrame {
        let fitted = fittedMedia(aspect: {
            let pixelsWide = Double(pixelWidth ?? 0)
            let pixelsHigh = Double(pixelHeight ?? 0)
            guard pixelsWide > 0, pixelsHigh > 0 else { return 1 }
            return pixelsWide / pixelsHigh
        }(), maxWidth: max(1, maxWidth), maxHeight: max(1, maxHeight))
        return ContentFrame(width: fitted.width, height: fitted.height)
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

    /// Пузыри одного автора подряд (в пределах `window` и одного дня) слипаются.
    /// Нижний угол автора меньше только у последнего в серии. Имя стоит у первого, аватар у последнего.
    public static func group(
        authorId: String,
        date: Date,
        previous: (authorId: String, date: Date)?,
        next: (authorId: String, date: Date)?,
        window: TimeInterval = 15 * 60,
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

    /// Один кадр у подписи. Влезает в ширину пузыря и в `maxHeight`, пропорция фото сохраняется:
    /// высокая страница становится уже, а не обрезается слева и справа.
    public static func fullWidthTile(aspect: Double, width: Double, minHeight: Double = 120, maxHeight: Double = 360) -> AlbumLayout {
        let ratio = aspect.isFinite && aspect > 0 ? aspect : 1
        var fitted = fittedMedia(aspect: ratio, maxWidth: max(1, width), maxHeight: max(1, maxHeight))
        if fitted.height < minHeight {
            let grownWidth = minHeight * ratio
            if grownWidth <= max(1, width) {
                fitted = (grownWidth, minHeight)
            }
        }
        let corners = AlbumCorners(topLeft: true, topRight: true, bottomLeft: true, bottomRight: true)
        return AlbumLayout(
            width: fitted.width,
            height: fitted.height,
            gap: 0,
            tiles: [AlbumTile(index: 0, x: 0, y: 0, width: fitted.width, height: fitted.height, corners: corners)]
        )
    }

    /// Альбом: пропорции кадров собираются в ряды, внешние углы скругляются, внутренние остаются прямыми.
    public static func album(aspects: [Double], maxWidth: Double, maxHeight: Double = 360, gap: Double = 2) -> AlbumLayout {
        let width = max(1, maxWidth)
        let space = max(0, gap)
        let ratios = aspects.map { value in
            let ratio = value.isFinite && value > 0 ? value : 1
            return ratio
        }
        guard !ratios.isEmpty else { return AlbumLayout(width: 0, height: 0, gap: space, tiles: []) }
        // Большому альбому можно быть выше: иначе он сужается под предел высоты.
        let limit = max(1, ratios.count >= 7 ? maxHeight * 1.35 : maxHeight)
        let placed: [Placed]
        if ratios.count == 3, ratios[0] < 1.15, let trio = portraitTrio(ratios, width: width, gap: space) {
            placed = trio
        } else if ratios.count >= 4 {
            placed = pack(balancedRows(ratios, width: width, gap: space, maxHeight: limit), aspects: ratios, width: width, gap: space)
        } else {
            placed = pack(rowCounts(ratios), aspects: ratios, width: width, gap: space)
        }
        return finish(placed, width: width, maxHeight: limit, gap: space)
    }

    /// Ряды альбома из четырёх и больше кадров по их пропорциям: перебираются все разбиения
    /// на ряды по 1–4 кадра, лучшее — с рядами высотой ближе к 0,4 ширины, без рядов ниже
    /// 0,22 ширины и в пределах `maxHeight`; при равенстве ряд сверху не больше нижнего.
    /// Шесть широких сканов ложатся по два в ряд, а не по три полосками в 45 точек.
    static func balancedRows(_ aspects: [Double], width: Double, gap: Double, maxHeight: Double) -> [Int] {
        let ideal = width * 0.4
        let lowest = width * 0.22
        var best: (score: Double, rows: [Int]) = (.infinity, [aspects.count])
        func score(_ rows: [Int]) -> Double {
            var cursor = 0
            var total = gap * Double(rows.count - 1)
            var result = 0.0
            for (index, count) in rows.enumerated() {
                let height = measure(Array(aspects[cursor..<(cursor + count)]), width: width, gap: gap).height
                cursor += count
                total += height
                result += pow((height - ideal) / ideal, 2)
                if height < lowest { result += 3 }
                if index > 0, rows[index - 1] > count { result += 0.05 }
            }
            if total > maxHeight {
                let over = (total - maxHeight) / maxHeight
                result += over * over * 20 + over * 2
            }
            return result
        }
        func walk(_ rows: [Int], left: Int) {
            guard left > 0 else {
                let value = score(rows)
                if value < best.score { best = (value, rows) }
                return
            }
            for count in 1...min(4, left) { walk(rows + [count], left: left - count) }
        }
        walk([], left: aspects.count)
        return best.rows
    }

    private static func sameAuthor(_ lhs: String, _ rhs: String) -> Bool {
        !lhs.isEmpty && lhs == rhs
    }

    /// Весь кадр внутри прямоугольника. Стороны не обрезаются: лишняя высота сужает ширину.
    static func fittedMedia(aspect: Double, maxWidth: Double, maxHeight: Double) -> (width: Double, height: Double) {
        let ratio = aspect.isFinite && aspect > 0 ? aspect : 1
        let widthLimit = max(1, maxWidth)
        let heightLimit = max(1, maxHeight)
        var width = widthLimit
        var height = width / ratio
        if height > heightLimit {
            height = heightLimit
            width = max(1, height * ratio)
        }
        return (width, height)
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

    /// Узкий первый кадр стоит слева, два остальных делят правую колонку. Ширина левой колонки
    /// подбирается так, чтобы у всех трёх кадров осталась своя пропорция: высота левого равна
    /// высоте правой колонки. Иначе кадр вписывался бы с пустыми полосами по бокам. Слишком узкая
    /// или широкая левая колонка — `nil`, альбом раскладывается рядами.
    private static func portraitTrio(_ aspects: [Double], width: Double, gap: Double) -> [Placed]? {
        let rightSum = 1 / aspects[1] + 1 / aspects[2]
        let leftWidth = ((width - gap) * rightSum + gap) / (1 / aspects[0] + rightSum)
        guard leftWidth.isFinite, leftWidth >= width * 0.35, leftWidth <= width * 0.75 else { return nil }
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
    /// Перейти к доле `fraction` (0…1) открытого файла, не меняя, играет он или нет.
    func seek(to fraction: Double)
    var progress: Double { get }
    var isPlaying: Bool { get }
    var failed: Bool { get }
    /// Скорость 1…2 для этого и следующих голосовых; высота голоса не меняется.
    var rate: Float { get set }
}

extension VoicePlaying {
    /// Плеер без перемотки: голосовое играет с того места, где было.
    public func seek(to fraction: Double) {}

    /// Плеер без ускорения.
    public var rate: Float {
        get { 1 }
        set {}
    }
}
