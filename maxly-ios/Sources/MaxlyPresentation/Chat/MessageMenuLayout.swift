import Foundation

/// All menu regions stay inside the available viewport. Overflow belongs to the
/// action/reaction scroll views, never to an offscreen menu.
///
/// A bubble taller than the space left between the reactions bar and the actions is
/// scaled down (never below `minimumPreviewScale`); whatever is still taller after that
/// is clipped from the bottom. The reactions bar and the actions always keep their place.
public struct MessageMenuLayout {
    /// Smallest scale for a tall preview: below it text and media become unreadable,
    /// so the rest is clipped instead.
    public static let minimumPreviewScale: CGFloat = 0.6

    /// Visible preview on screen (already scaled and clipped).
    public let preview: CGRect
    /// Scale applied to the bubble copy; `1` keeps it at its natural size.
    public let previewScale: CGFloat
    public let reactions: CGRect
    public let actions: CGRect

    /// The preview shows only the top part of the scaled bubble.
    public var previewClipped: Bool { preview.height + 0.5 < naturalSize.height * previewScale }

    private let naturalSize: CGSize

    public init(bounds: CGRect, source: CGRect, outgoing: Bool,
                actionHeight: CGFloat, actionWidth: CGFloat,
                reactionWidth: CGFloat, reactionHeight: CGFloat) {
        let width = max(0, bounds.width)
        let height = max(0, bounds.height)
        let sourceW = max(0, source.width)
        let sourceH = max(0, source.height)
        naturalSize = CGSize(width: sourceW, height: sourceH)

        let reactionH = min(max(0, reactionHeight), height)
        let reactionGap: CGFloat = reactionH > 0 ? min(8, max(0, height - reactionH)) : 0
        let remaining = max(0, height - reactionH - reactionGap)
        let gap = min(8, remaining)
        let minimumPreview = min(60, sourceH, max(0, remaining - gap))
        let menuH = min(max(0, actionHeight), max(0, remaining - gap - minimumPreview))
        let available = max(0, remaining - gap - menuH)

        // Scale to the free height first, then to the width; a tall bubble keeps at least
        // the minimum scale and is clipped below it.
        var scale: CGFloat = 1
        if sourceH > available, sourceH > 0 {
            scale = max(available / sourceH, Self.minimumPreviewScale)
        }
        if sourceW * scale > width, sourceW > 0 {
            scale = width / sourceW
        }
        previewScale = scale
        let previewW = min(sourceW * scale, width)
        let previewH = min(sourceH * scale, available)

        // The scaled copy stays on the bubble's side: incoming keeps its leading edge,
        // outgoing its trailing edge.
        let anchorX = outgoing ? source.maxX - previewW : source.minX
        let x = min(max(anchorX, bounds.minX), bounds.maxX - previewW)
        // Near the top the bubble moves down under the reactions bar, near the bottom it
        // moves up above the actions.
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
