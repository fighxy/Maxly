import Foundation

/// Ответы поиска и трендов gifka.me в памяти. Условия API разрешают кэш не дольше суток;
/// держим коротко (10 минут), чтобы снятые материалы быстро пропадали из выдачи.
public final class GifkaResponseCache: @unchecked Sendable {
    public static let defaultTTL: TimeInterval = 10 * 60
    public static let shared = GifkaResponseCache()

    private let ttl: TimeInterval
    private let capacity: Int
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var entries: [URL: (stored: Date, page: GifkaPage)] = [:]

    public init(ttl: TimeInterval = defaultTTL, capacity: Int = 64, now: @escaping @Sendable () -> Date = Date.init) {
        self.ttl = min(ttl, Self.defaultTTL)
        self.capacity = capacity
        self.now = now
    }

    /// Свежий ответ на адрес или `nil`; протухший сразу удаляется.
    public func page(for url: URL) -> GifkaPage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[url] else { return nil }
        if now().timeIntervalSince(entry.stored) < ttl { return entry.page }
        entries[url] = nil
        return nil
    }

    public func store(_ page: GifkaPage, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        let time = now()
        entries = entries.filter { time.timeIntervalSince($0.value.stored) < ttl }
        if entries.count >= capacity, let oldest = entries.min(by: { $0.value.stored < $1.value.stored })?.key {
            entries[oldest] = nil
        }
        entries[url] = (time, page)
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }
}
