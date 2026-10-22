import Foundation

/// Ограничивает работу геометрии ленты на главном потоке частотой кадра.
///
/// Per-row `onGeometryChange` и KVO скролла могут вызываться десятки раз за кадр.
/// Отметки прочтения и «кнопка вниз» достаточно обновлять ~раз в 16 ms.
public final class TranscriptGeometrySampler: @unchecked Sendable {
    public var minIntervalNs: UInt64
    private var lastFireNs: UInt64 = 0
    private let lock = NSLock()

    public init(minIntervalMs: Double = 16) {
        self.minIntervalNs = UInt64(max(1, minIntervalMs) * 1_000_000)
    }

    /// `true`, если с прошлого срабатывания прошло достаточно времени (или `force`).
    /// `nowNs` — монотонные наносекунды (`DispatchTime.now().uptimeNanoseconds` на клиенте).
    public func shouldFire(nowNs: UInt64, force: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if force || lastFireNs == 0 || nowNs &- lastFireNs >= minIntervalNs {
            lastFireNs = nowNs
            return true
        }
        return false
    }
}
