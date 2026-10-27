import Foundation

/// Последние открытые модели экранов по ключу, не больше `capacity`. Новая модель вытесняет
/// самую давно открытую, кроме тех, которые велено оставить (например, чат, где играет
/// голосовое). Без предела модели всех открытых за сеанс чатов жили до выхода из аккаунта.
public struct RecentModels<Key: Hashable, Value> {
    public let capacity: Int
    private var values: [Key: Value] = [:]
    /// Ключи от давно открытых к недавним.
    private var order: [Key] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { values.count }

    /// Все модели, от давно открытых к недавним.
    public var all: [Value] { order.compactMap { values[$0] } }

    /// Модель по ключу; найденная становится самой недавней.
    public mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    /// Положить модель и вернуть вытесненные: их деактивирует хозяин. `keep` — ключи, которые
    /// нельзя вытеснять; если оставить нужно больше `capacity`, лишние остаются.
    public mutating func insert(_ value: Value, for key: Key, keep: (Key) -> Bool = { _ in false }) -> [Value] {
        values[key] = value
        touch(key)
        var evicted: [Value] = []
        var index = 0
        while values.count > capacity, index < order.count - 1 {
            let candidate = order[index]
            if keep(candidate) {
                index += 1
                continue
            }
            order.remove(at: index)
            if let gone = values.removeValue(forKey: candidate) { evicted.append(gone) }
        }
        return evicted
    }

    public mutating func removeAll() {
        values.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
