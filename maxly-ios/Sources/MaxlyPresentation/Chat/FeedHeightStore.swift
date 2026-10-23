import Foundation

/// Отпечаток всего, от чего зависит высота строки ленты: текст, вложения, реакции, соседи
/// (склейка, разделители), раскрытие в приватном режиме, режим выбора. Равный отпечаток —
/// записанная высота остаётся верной; другой — строка измеряется заново.
///
/// Обёртка над любым `Equatable`: у чата и комментариев свои отпечатки.
public struct FeedLayoutKey: Equatable, @unchecked Sendable {
    private let value: Any
    private let equals: (Any) -> Bool

    public init<Value: Equatable>(_ value: Value) {
        self.value = value
        self.equals = { other in (other as? Value) == value }
    }

    public static func == (lhs: FeedLayoutKey, rhs: FeedLayoutKey) -> Bool {
        lhs.equals(rhs.value)
    }
}

/// Откуда высота строки.
public enum FeedHeightSource: Int, Comparable, Sendable {
    /// Быстрая оценка по содержимому (TextKit и правила пузыря), пока строка далеко от экрана.
    case estimate
    /// Замер той же SwiftUI-строки вне экрана, до показа.
    case measured
    /// Строка на экране сама сообщила свою высоту, отличную от замера.
    case observed

    public static func < (lhs: FeedHeightSource, rhs: FeedHeightSource) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Единственный источник высоты строк ленты.
///
/// Высота привязана к отпечатку содержимого и к ширине ленты: смена текста, реакций, соседей
/// или поворот экрана делают её недействительной без отдельной очистки. Рамка ячейки сюда
/// не пишется никогда — только оценка, замер вне экрана и собственная высота содержимого.
/// Более точный источник не затирается менее точным для того же отпечатка и ширины.
public final class FeedHeightStore {
    public struct Entry: Equatable {
        public var key: FeedLayoutKey
        public var width: Double
        public var height: Double
        public var source: FeedHeightSource
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// Высота строки `id` для отпечатка `key` при ширине `width`; `nil` — нет действительной.
    public func entry(id: String, key: FeedLayoutKey, width: Double) -> Entry? {
        guard let entry = entries[id], Self.matches(entry, key: key, width: width) else { return nil }
        return entry
    }

    /// Высота, если строка уже измерена (замер или сама строка), а не только оценена.
    public func isMeasured(id: String, key: FeedLayoutKey, width: Double) -> Bool {
        (entry(id: id, key: key, width: width)?.source ?? .estimate) >= .measured
    }

    /// Записать высоту (с округлением вверх до полуточки: содержимое не обрезается на доли точки).
    /// Возвращает `true`, если действительная высота строки изменилась хотя бы на точку.
    /// Оценка не затирает замер, замер — высоту, которую сообщила сама строка.
    @discardableResult
    public func store(id: String, key: FeedLayoutKey, width: Double, height: Double, source: FeedHeightSource) -> Bool {
        guard height.isFinite, height > 0, width.isFinite, width > 0 else { return false }
        let rounded = (height * 2).rounded(.up) / 2
        if let current = entries[id], Self.matches(current, key: key, width: width) {
            guard source >= current.source else { return false }
            entries[id] = Entry(key: key, width: width, height: rounded, source: source)
            // Разница меньше точки ленту не перекладывает.
            return abs(current.height - rounded) >= 1
        }
        entries[id] = Entry(key: key, width: width, height: rounded, source: source)
        return true
    }

    public func remove(id: String) {
        entries[id] = nil
    }

    /// Строки, которых больше нет в ленте, не держат память.
    public func retain(_ ids: Set<String>) {
        guard entries.count > ids.count else { return }
        entries = entries.filter { ids.contains($0.key) }
    }

    public func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }

    public var count: Int { entries.count }

    private static func matches(_ entry: Entry, key: FeedLayoutKey, width: Double) -> Bool {
        abs(entry.width - width) < 0.5 && entry.key == key
    }
}

/// Какие строки мерить вне экрана до показа.
///
/// Замер SwiftUI-строки стоит миллисекунды, поэтому меряются не все строки, а окно вокруг места,
/// где лента встанет (последняя строка, цель перехода, верхняя видимая), и вперёд по прокрутке.
/// Остальные живут на оценке, пока к ним не подъехали.
public enum FeedMeasureWindow {
    /// Строк над и под точкой, где лента встанет. Экран вмещает до ~20 коротких строк.
    public static let around = 20
    /// Сколько строк вперёд по прокрутке мерить заранее.
    public static let ahead = 12
    /// Сколько строк замерить за один кадр прокрутки.
    public static let perScrollStep = 3

    /// Окно индексов `[focus - before, focus + after]` в пределах `count`.
    public static func range(focus: Int, count: Int, before: Int = around, after: Int = around) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let center = min(max(focus, 0), count - 1)
        let lower = max(0, center - max(0, before))
        let upper = min(count, center + max(0, after) + 1)
        return lower..<upper
    }

    /// Порядок замера при прокрутке: сначала видимые, затем вперёд по направлению (ближние раньше),
    /// затем немного назад. `towardOlder` — палец тянет к истории (вверх по ленте).
    public static func scrollOrder(visible: Range<Int>, count: Int, towardOlder: Bool, ahead: Int = ahead) -> [Int] {
        guard count > 0, !visible.isEmpty else { return [] }
        let lower = max(0, visible.lowerBound)
        let upper = min(count, visible.upperBound)
        var order = Array(lower..<max(lower, upper))
        let forward = towardOlder
            ? stride(from: lower - 1, through: max(0, lower - ahead), by: -1).map { $0 }
            : Array(upper..<min(count, upper + ahead))
        let backward = towardOlder
            ? Array(upper..<min(count, upper + ahead / 3))
            : stride(from: lower - 1, through: max(0, lower - ahead / 3), by: -1).map { $0 }
        order += forward + backward
        return order.filter { $0 >= 0 && $0 < count }
    }
}
