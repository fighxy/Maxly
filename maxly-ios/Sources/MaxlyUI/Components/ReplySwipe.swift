import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Свайп влево по пузырю для ответа.
///
/// На iOS 18 и новее это `UIPanGestureRecognizer`, который начинается, только если палец
/// с самого начала идёт влево и в основном по горизонтали. Вертикальную прокрутку ленты он
/// не видит вовсе, поэтому не цепляет её и не мешает ей начаться. На iOS 17 — прежний
/// `DragGesture` с той же проверкой направления.
struct ReplySwipe: ViewModifier {
    let isEnabled: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: () -> Void

    func body(content: Content) -> some View {
        if !isEnabled {
            content
        } else {
            #if canImport(UIKit)
            if #available(iOS 18.0, *) {
                content.gesture(HorizontalPan(onChange: onChange, onEnd: onEnd))
            } else {
                content.simultaneousGesture(drag)
            }
            #else
            content.simultaneousGesture(drag)
            #endif
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                guard dx < 0, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                onChange(dx)
            }
            .onEnded { _ in onEnd() }
    }
}

#if canImport(UIKit)
@available(iOS 18.0, *)
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(min(0, recognizer.translation(in: recognizer.view).x))
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.5
        }
    }
}
#endif

extension View {
    func replySwipe(enabled: Bool, onChange: @escaping (CGFloat) -> Void, onEnd: @escaping () -> Void) -> some View {
        modifier(ReplySwipe(isEnabled: enabled, onChange: onChange, onEnd: onEnd))
    }
}
