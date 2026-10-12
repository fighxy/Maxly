import Foundation

/// All menu regions stay inside the available viewport. Overflow belongs to the
/// action/reaction scroll views, never to an offscreen menu.
public struct MessageMenuLayout {
    public let preview: CGRect
    public let reactions: CGRect
    public let actions: CGRect

    public init(bounds: CGRect, source: CGRect, outgoing: Bool,
                actionHeight: CGFloat, actionWidth: CGFloat,
                reactionWidth: CGFloat, reactionHeight: CGFloat) {
        let width = max(0, bounds.width)
        let height = max(0, bounds.height)
        let reactionH = min(max(0, reactionHeight), height)
        let reactionGap: CGFloat = reactionH > 0 ? min(8, max(0, height - reactionH)) : 0
        let remaining = max(0, height - reactionH - reactionGap)
        let gap = min(8, remaining)
        let minimumPreview = min(60, max(0, source.height), max(0, remaining - gap))
        let menuH = min(max(0, actionHeight), max(0, remaining - gap - minimumPreview))
        let previewH = min(max(0, source.height), max(0, remaining - gap - menuH))
        let previewW = min(max(0, source.width), width)
        let x = min(max(source.minX, bounds.minX), bounds.maxX - previewW)
        let y = min(max(source.minY, bounds.minY + reactionH + reactionGap),
                    bounds.maxY - menuH - gap - previewH)
        preview = CGRect(x: x, y: y, width: previewW, height: previewH)
        func aligned(_ desired: CGFloat, y: CGFloat, height: CGFloat) -> CGRect {
            let w = min(max(0, desired), width)
            let leading = outgoing ? x + previewW - w : x
            return CGRect(x: min(max(leading, bounds.minX), bounds.maxX - w), y: y, width: w, height: height)
        }
        reactions = aligned(reactionWidth, y: y - reactionGap - reactionH, height: reactionH)
        actions = aligned(actionWidth, y: y + previewH + gap, height: menuH)
    }
}
