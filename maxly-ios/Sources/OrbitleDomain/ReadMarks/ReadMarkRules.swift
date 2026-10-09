import Foundation

/// Правила отметки прочтения, общие для iOS, Android и ПК. Оба значения живут только здесь:
/// лента, модель чата и тесты берут их отсюда. Общий для клиентов файл
/// `test-fixtures/client-rules/constants.json` (`readMarks`) сверяет `ClientRulesFixtureTests`.
public enum ReadMarkRules {
    /// Отметка уходит через столько после последней смены кандидата: быстрая прокрутка
    /// через несколько сообщений шлёт одну отметку — о последнем.
    public static let delay: Duration = .milliseconds(200)

    /// Сообщение считается увиденным, когда в видимой области чата хотя бы такая доля его
    /// высоты. Видимая область — без шапки, поля ввода и клавиатуры (`ReadVisibility.area`).
    public static let minVisibleFraction: Double = 0.3
}

/// Вертикальный отрезок экрана: от `minY` до `maxY` в одних координатах со строками ленты.
public struct ReadSpan: Hashable, Sendable {
    public var minY: Double
    public var maxY: Double

    public init(minY: Double, maxY: Double) {
        self.minY = minY
        self.maxY = maxY
    }

    /// Пустой отрезок ничего не показывает.
    public var isEmpty: Bool { maxY <= minY }
    public var height: Double { max(0, maxY - minY) }
}

/// Строка ленты, как её видит экран: `id` сообщения, `order` — место в ленте (больше —
/// новее), верх `minY` и высота `height` в тех же координатах, что и видимая область.
public struct ReadRowFrame: Hashable, Sendable {
    public var id: String
    public var order: Int
    public var minY: Double
    public var height: Double

    public init(id: String, order: Int, minY: Double, height: Double) {
        self.id = id
        self.order = order
        self.minY = minY
        self.height = height
    }
}

/// Какое сообщение ленты увидено. Чистые функции над рамками: экран меряет, здесь считается.
public enum ReadVisibility {
    /// Видимая область чата. `viewport` — рамка ленты на экране, `safeTop` и `safeBottom` —
    /// её безопасные отступы (под ними строки рисуются, но закрыты панелью навигации, полем
    /// ввода или клавиатурой). Дальше область режется явно: снизу шапки (`headerBottom`:
    /// панель навигации и плашки под ней), сверху поля ввода (`composerTop`) и клавиатуры
    /// (`keyboardTop`, `nil` — клавиатура закрыта). Так область верна, даже если какой-то из
    /// отступов уже вошёл в рамку ленты: двойной вычет ничего не меняет.
    public static func area(
        viewport: ReadSpan,
        safeTop: Double = 0,
        safeBottom: Double = 0,
        headerBottom: Double? = nil,
        composerTop: Double? = nil,
        keyboardTop: Double? = nil
    ) -> ReadSpan {
        var top = viewport.minY + max(0, safeTop)
        var bottom = viewport.maxY - max(0, safeBottom)
        if let headerBottom { top = max(top, headerBottom) }
        if let composerTop, composerTop > 0 { bottom = min(bottom, composerTop) }
        if let keyboardTop, keyboardTop > 0 { bottom = min(bottom, keyboardTop) }
        return ReadSpan(minY: top, maxY: max(top, bottom))
    }

    /// Доля высоты строки (верх `minY`, высота `height`), попавшая в `area`: от 0 до 1.
    public static func visibleFraction(minY: Double, height: Double, in area: ReadSpan) -> Double {
        guard height > 0, !area.isEmpty else { return 0 }
        let shown = min(minY + height, area.maxY) - max(minY, area.minY)
        return max(0, shown) / height
    }

    /// Строка увидена: в области не меньше `threshold` её высоты. Допуск 1e-4 гасит ошибку
    /// округления дробных точек, чтобы ровно 30 % считались увиденными.
    public static func isSeen(_ row: ReadRowFrame, in area: ReadSpan, threshold: Double = ReadMarkRules.minVisibleFraction) -> Bool {
        visibleFraction(minY: row.minY, height: row.height, in: area) + 1e-4 >= threshold
    }

    /// Самое новое увиденное сообщение: наибольший `order` среди увиденных строк. `nil` —
    /// ни одна строка не видна на нужную долю.
    public static func newestSeen(_ rows: [ReadRowFrame], in area: ReadSpan, threshold: Double = ReadMarkRules.minVisibleFraction) -> String? {
        rows.filter { isSeen($0, in: area, threshold: threshold) }.max { $0.order < $1.order }?.id
    }
}
