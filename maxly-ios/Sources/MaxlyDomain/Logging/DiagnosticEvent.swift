import Foundation
import CryptoKit

/// Local-only schema shared with Kotlin. No message content or raw identifiers.
public enum DiagnosticEvent {
    private final class State: @unchecked Sendable {
        let lock = NSRecursiveLock()
        let session = UUID().uuidString
        let started = ProcessInfo.processInfo.systemUptime
        var sequence = 0
        var detailedUntil: TimeInterval = 0
        var snapshots: [String: [String: String]] = [:]
    }
    private static let state = State()

    public static func id(_ value: String) -> String {
        SHA256.hash(data: Data((state.session + value).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public static func event(_ name: String, _ fields: [String: String] = [:], snapshot: Bool = false) {
        state.lock.lock()
        defer { state.lock.unlock() }
        let safe = Dictionary(uniqueKeysWithValues: fields.prefix(40).map { key, value in
            let forbidden = ["token", "password", "text", "caption", "url", "payload", "phone", "secret"].contains { key.lowercased().contains($0) }
            return (key, forbidden ? "[redacted]" : String(value.prefix(256)))
        })
        let uptime = Int((ProcessInfo.processInfo.systemUptime - state.started) * 1000)
        if snapshot {
            if state.snapshots.count >= 16 && state.snapshots[name] == nil { state.snapshots.removeValue(forKey: state.snapshots.keys.sorted().first!) }
            state.snapshots[name] = safe.merging(["observed_uptime_ms": String(uptime)]) { _, new in new }
        }
        state.sequence += 1
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let object: [String: Any] = ["schema": 1, "time": formatter.string(from: Date()), "uptime_ms": uptime,
            "session": state.session, "seq": state.sequence, "event": String(name.prefix(96)), "fields": safe]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        Log.info(.diagnostics, line)
    }

    @discardableResult public static func problemNow() -> String {
        state.lock.lock()
        defer { state.lock.unlock() }
        let marker = String(UUID().uuidString.prefix(8))
        event("problem.mark", ["marker": marker])
        for (name, fields) in state.snapshots {
            event("problem.snapshot", fields.merging(["source": name, "marker": marker]) { _, new in new })
        }
        return marker
    }

    public static func enableDetailed() {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.detailedUntil = ProcessInfo.processInfo.systemUptime + 900
        event("diagnostics.detail", ["duration_seconds": "900"])
    }

    public static var sampleInterval: TimeInterval {
        state.lock.lock()
        defer { state.lock.unlock() }
        return ProcessInfo.processInfo.systemUptime < state.detailedUntil ? 0.25 : 1
    }
}

/// Only coarse upload progress, bounded to five events per upload.
public final class DiagnosticProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1
    private let operation = UUID().uuidString
    public init() {}
    public func report(_ fraction: Double) {
        guard fraction.isFinite else { return }
        let bucket = Int(min(1, max(0, fraction)) * 4)
        lock.lock()
        guard bucket > last else { lock.unlock(); return }
        last = bucket
        lock.unlock()
        DiagnosticEvent.event("media.upload.progress", ["operation": operation, "percent": String(bucket * 25)])
    }
}
