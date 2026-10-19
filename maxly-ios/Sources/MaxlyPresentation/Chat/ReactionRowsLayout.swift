import Foundation

/// Раскладка ряда реакций пузыря без SwiftUI: плашки идут подряд и переносятся на новый ряд,
/// время встаёт в правый нижний угол последнего ряда, если влезает, иначе — отдельной строкой.
///
/// Высота — сумма всех рядов (и строки времени), сколько бы их ни было: блок под реакциями
/// (комментарии поста) всегда ниже последнего ряда. Раньше ряд реакций мерился одной ширине,
/// а раскладывался в другой, на долю точки уже (её округлял SwiftUI, а время стояло отдельной
/// колонкой рядом с плашками): лишний ряд не входил в высоту и наезжал на строку комментариев.
public struct ReactionRowsLayout: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        /// Номера плашек ряда по порядку.
        public var items: [Int]
        public var width: CGFloat
        public var height: CGFloat
        /// Верх ряда от верха раскладки.
        public var y: CGFloat
    }

    public enum MetaPlacement: Equatable, Sendable {
        /// Справа в последнем ряду реакций.
        case lastRow
        /// Отдельной строкой под реакциями, справа.
        case ownLine
    }

    /// Доля точки, на которую ширина раскладки может отличаться от ширины замера
    /// (округление до пикселя): из-за неё ряд не должен переноситься.
    public static let tolerance: CGFloat = 0.5

    public let rows: [Row]
    public let meta: MetaPlacement?
    /// Размер времени, если оно в этом ряду.
    public let metaSize: CGSize?
    /// Верх времени от верха раскладки: по низу последнего ряда или на своей строке.
    public let metaY: CGFloat?
    /// Ширина содержимого: самый широкий ряд или последний ряд вместе со временем.
    public let width: CGFloat
    /// Полная высота: все ряды, промежутки между ними и строка времени, если она своя.
    public let height: CGFloat

    /// - Parameters:
    ///   - chips: размеры плашек по порядку.
    ///   - meta: размер времени со статусом; `nil` — время в другом месте пузыря.
    ///   - maxWidth: доступная ширина; `.infinity` — один ряд.
    ///   - spacing: промежуток между плашками в ряду.
    ///   - lineSpacing: промежуток между рядами (и до строки времени).
    ///   - metaSpacing: наименьший промежуток между последней плашкой и временем.
    public init(
        chips: [CGSize],
        meta: CGSize? = nil,
        maxWidth: CGFloat,
        spacing: CGFloat = 6,
        lineSpacing: CGFloat = 6,
        metaSpacing: CGFloat = 8
    ) {
        let limit = maxWidth.isNaN ? .infinity : max(0, maxWidth) + Self.tolerance
        var rows: [Row] = []
        var current = Row(items: [], width: 0, height: 0, y: 0)
        for (index, chip) in chips.enumerated() {
            let added = current.items.isEmpty ? chip.width : current.width + spacing + chip.width
            if !current.items.isEmpty, added > limit {
                rows.append(current)
                current = Row(items: [], width: 0, height: 0, y: 0)
            }
            current.width = current.items.isEmpty ? chip.width : current.width + spacing + chip.width
            current.height = max(current.height, chip.height)
            current.items.append(index)
        }
        if !current.items.isEmpty { rows.append(current) }

        var y: CGFloat = 0
        for index in rows.indices {
            if index > 0 { y += lineSpacing }
            rows[index].y = y
            y += rows[index].height
        }
        var width = rows.map(\.width).max() ?? 0

        guard let meta else {
            self.rows = rows
            self.meta = nil
            self.metaSize = nil
            self.metaY = nil
            self.width = width
            self.height = y
            return
        }
        if let last = rows.indices.last, rows[last].width + metaSpacing + meta.width <= limit {
            // Время в последнем ряду: ряд не ниже времени, время — по низу ряда.
            if meta.height > rows[last].height {
                y += meta.height - rows[last].height
                rows[last].height = meta.height
            }
            width = max(width, rows[last].width + metaSpacing + meta.width)
            self.meta = .lastRow
            self.metaY = rows[last].y + rows[last].height - meta.height
        } else {
            if !rows.isEmpty { y += lineSpacing }
            width = max(width, meta.width)
            self.meta = .ownLine
            self.metaY = y
            y += meta.height
        }
        self.rows = rows
        self.metaSize = meta
        self.width = width
        self.height = y
    }

    /// Рамка времени в раскладке шириной `width`: время прижато к правому краю.
    public func metaFrame(width: CGFloat) -> CGRect? {
        guard let metaSize, let metaY else { return nil }
        return CGRect(x: max(0, width - metaSize.width), y: metaY, width: metaSize.width, height: metaSize.height)
    }
}
