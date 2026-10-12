import Foundation
import UIKit
import MaxlyDomain

/// One correlation id per transcript. Geometry is sampled at most once a second;
/// explicit lifecycle/scroll events are recorded immediately. No message bodies.
@MainActor
final class TranscriptDiagnostics {
    private let session = String(UUID().uuidString.prefix(8))
    private var lastSample = -Double.infinity
    private weak var scroll: UIScrollView?
    var context: [String: String] = [:]

    func attach(_ scroll: UIScrollView) {
        self.scroll = scroll
        record("scroll-attached", immediate: true)
    }

    func detach() {
        record("scroll-detached", immediate: true)
        scroll = nil
    }

    func record(_ event: String, immediate: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard immediate || now - lastSample >= DiagnosticEvent.sampleInterval else { return }
        lastSample = now
        var fields = context
        fields["screen"] = session
        // Targets may contain server IDs: keep the reason and pseudonymize the target.
        let reason = event.split(separator: ":", maxSplits: 1)
        fields["reason"] = String(reason[0])
        if reason.count == 2 { fields["target"] = DiagnosticEvent.id(String(reason[1])) }
        fields["attached"] = String(scroll != nil)
        if let scroll {
            let inset = scroll.adjustedContentInset
            let maxY = max(-inset.top, scroll.contentSize.height + inset.bottom - scroll.bounds.height)
            fields.merge([
                "offset_y": Self.n(scroll.contentOffset.y), "content_height": Self.n(scroll.contentSize.height),
                "viewport_height": Self.n(scroll.bounds.height), "inset_top": Self.n(inset.top), "inset_bottom": Self.n(inset.bottom),
                "max_y": Self.n(maxY), "beyond_end": Self.n(scroll.contentOffset.y - maxY),
                "tracking": String(scroll.isTracking), "dragging": String(scroll.isDragging), "decelerating": String(scroll.isDecelerating)
            ]) { _, new in new }
        }
        DiagnosticEvent.event("chat.viewport", fields, snapshot: scroll != nil && event != "scroll-detached" && event != "disappear")
    }

    static func n(_ value: CGFloat) -> String {
        value.isFinite ? String(format: "%.1f", Double(value)) : "unknown"
    }

    static func frame(_ value: CGRect?) -> String {
        guard let value else { return "unmeasured" }
        return "y:\(n(value.minY)),h:\(n(value.height)),bottom:\(n(value.maxY))"
    }
}
