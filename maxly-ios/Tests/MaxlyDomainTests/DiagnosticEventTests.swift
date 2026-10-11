import Foundation
import Testing
@testable import MaxlyDomain

@Suite("Structured diagnostics", .serialized)
struct DiagnosticEventTests {
    private final class Capture: @unchecked Sendable {
        let lock = NSLock()
        var lines: [String] = []
        func snapshot() -> [String] {
            lock.lock(); defer { lock.unlock() }
            return lines
        }
        func append(_ entry: Log.Entry) {
            guard entry.category == .diagnostics else { return }
            lock.lock(); defer { lock.unlock() }
            lines.append(entry.message)
        }
    }

    @Test func privateFieldsAndMarker() throws {
        let capture = Capture()
        let previous = Log.sink
        Log.sink = { capture.append($0) }
        defer { Log.sink = previous }
        DiagnosticEvent.event("chat.viewport", ["visible": "0", "text": "PRIVATE", "token": "SECRET", "chat": DiagnosticEvent.id("12345")], snapshot: true)
        let marker = DiagnosticEvent.problemNow()
        let lines = capture.snapshot()
        let rows = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        #expect(rows.count >= 3)
        #expect(rows.allSatisfy { $0["schema"] as? Int == 1 })
        #expect(!lines.joined().contains("PRIVATE"))
        #expect(!lines.joined().contains("SECRET"))
        #expect(DiagnosticEvent.id("12345") == DiagnosticEvent.id("12345"))
        #expect(DiagnosticEvent.id("12345") != "12345")
        let snapshot = rows.last { $0["event"] as? String == "problem.snapshot" && ($0["fields"] as? [String: String])?["source"] == "chat.viewport" }
        #expect((snapshot?["fields"] as? [String: String])?["marker"] == marker)
        let seqs = rows.compactMap { $0["seq"] as? Int }
        #expect(seqs == seqs.sorted())
    }
}
