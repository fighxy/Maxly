import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Перемотка голосового по дорожке: касание переходит к месту под пальцем, протяжка
/// пальцем по горизонтали двигает его. Координаты — в собственном пространстве вида.
///
/// Протяжка начинается, только если палец идёт в основном по горизонтали: вертикальный
/// жест достаётся прокрутке ленты. На iOS 18 и новее это `UIPanGestureRecognizer` с такой
/// проверкой до начала (как у свайпа для ответа, `ReplySwipe`), он может идти вместе со
/// свайпом ответа, но не с прокруткой; пузырь сам гасит свайп ответа, пока идёт перемотка.
/// На iOS 17 — `DragGesture` рядом с прокруткой, направление решает первый сдвиг.
struct WaveformScrub: ViewModifier {
    let isEnabled: Bool
    let onTap: (CGFloat) -> Void
    let onBegin: () -> Void
    let onChange: (CGFloat) -> Void
    /// `true` — палец отпущен, перемотать; `false` — жест сорвался, оставить как было.
    let onEnd: (Bool) -> Void

    @State private var axis: Axis?

    func body(content: Content) -> some View {
        if !isEnabled {
            content
        } else {
            #if canImport(UIKit)
            if #available(iOS 18.0, *) {
                content
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { onTap($0.x) }
                    .gesture(ScrubPan(onBegin: onBegin, onChange: onChange, onEnd: onEnd))
            } else {
                fallback(content)
            }
            #else
            fallback(content)
            #endif
        }
    }

    private func fallback(_ content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { onTap($0.x) }
            .simultaneousGesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                if axis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    if dx > dy * 1.2 {
                        axis = .horizontal
                        onBegin()
                    } else if dy > dx {
                        axis = .vertical
                    }
                }
                if axis == .horizontal { onChange(value.location.x) }
            }
            .onEnded { _ in
                if axis == .horizontal { onEnd(true) }
                axis = nil
            }
    }
}

#if canImport(UIKit)
@available(iOS 18.0, *)
private struct ScrubPan: UIGestureRecognizerRepresentable {
    let onBegin: () -> Void
    let onChange: (CGFloat) -> Void
    let onEnd: (Bool) -> Void

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
        case .began:
            onBegin()
            onChange(context.converter.localLocation.x)
        case .changed:
            onChange(context.converter.localLocation.x)
        case .ended:
            onEnd(true)
        case .cancelled, .failed:
            onEnd(false)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }

        /// Вместе со свайпом ответа можно (его гасит пузырь), с прокруткой ленты — нет.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            !(other.view is UIScrollView)
        }
    }
}
#endif

extension View {
    func waveformScrub(
        enabled: Bool,
        onTap: @escaping (CGFloat) -> Void,
        onBegin: @escaping () -> Void,
        onChange: @escaping (CGFloat) -> Void,
        onEnd: @escaping (Bool) -> Void
    ) -> some View {
        modifier(WaveformScrub(isEnabled: enabled, onTap: onTap, onBegin: onBegin, onChange: onChange, onEnd: onEnd))
    }
}
