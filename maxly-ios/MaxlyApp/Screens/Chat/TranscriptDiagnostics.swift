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
    var context = "context=pending"

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
        guard immediate || now - lastSample >= 1 else { return }
        lastSample = now
        var metrics = "scroll=unattached"
        if let scroll {
            let inset = scroll.adjustedContentInset
            let maxY = max(-inset.top, scroll.contentSize.height + inset.bottom - scroll.bounds.height)
            metrics = "offsetY=\(Self.n(scroll.contentOffset.y)) contentH=\(Self.n(scroll.contentSize.height)) viewportH=\(Self.n(scroll.bounds.height)) insetTop=\(Self.n(inset.top)) insetBottom=\(Self.n(inset.bottom)) maxY=\(Self.n(maxY)) beyondEnd=\(Self.n(scroll.contentOffset.y - maxY)) tracking=\(scroll.isTracking) dragging=\(scroll.isDragging) decelerating=\(scroll.isDecelerating)"
        }
        Log.info(.ui, "chat-scroll session=\(session) event=\(event) \(context) \(metrics)")
    }

    static func n(_ value: CGFloat) -> String {
        value.isFinite ? String(format: "%.1f", Double(value)) : "unknown"
    }

    static func frame(_ value: CGRect?) -> String {
        guard let value else { return "unmeasured" }
        return "y:\(n(value.minY)),h:\(n(value.height)),bottom:\(n(value.maxY))"
    }
}
