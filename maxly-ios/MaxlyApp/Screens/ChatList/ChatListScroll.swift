import SwiftUI
import UIKit
import MaxlyPresentation

/// Прокрутка списка чатов прямо из его `UIScrollView`.
///
/// Смещение из `onScrollGeometryChange` по-разному учитывает отступы под панели, поэтому
/// смещение, палец и инерция берутся у самого `UIScrollView`, а места строк шапки — у меток в
/// них (`ChatListProbe`), в координатах содержимого. Класс, а не состояние экрана: меняется
/// каждый кадр прокрутки, и экран не должен пересобираться из-за этого.
@MainActor
final class ChatListScroll {
    static let storiesId = "stories"
    static let searchId = "search"
    static let foldersId = "folders"

    /// Сдвиг прокрутки: прежний и новый верх видимой части, палец, инерция.
    var onScroll: ((_ previous: CGFloat, _ top: CGFloat, _ dragging: Bool, _ decelerating: Bool) -> Void)?
    /// Прокрутка остановилась.
    var onIdle: (() -> Void)?
    /// Истории уже вытянуты пальцем целиком: отклик один раз, пока они снова не спрячутся.
    var revealedByPull = false

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var idleTask: Task<Void, Never>?
    private var lastTop: CGFloat = 0
    private var probes: [String: WeakView] = [:]
    /// Последние известные места строк: строка, ушедшая далеко за экран, переиспользуется.
    private var frames: [String: CGRect] = [:]

    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    /// Верх видимой части в координатах содержимого: `0` — список у самого верха.
    var top: CGFloat {
        guard let scrollView else { return 0 }
        return scrollView.contentOffset.y + scrollView.adjustedContentInset.top
    }

    var isInteracting: Bool {
        guard let scrollView else { return false }
        return scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
    }

    func attach(_ scroll: UIScrollView) {
        guard scroll !== scrollView else { return }
        scrollView = scroll
        lastTop = top
        // Изменения приходят на главном потоке: их делает UIKit или SwiftUI.
        observation = scroll.observe(\.contentOffset) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.moved(view) }
        }
    }

    func register(_ view: UIView, id: String) {
        probes[id] = WeakView(view)
    }

    func geometry(stories: Bool, search: Bool, folders: Bool) -> ChatListHeaderGeometry {
        ChatListHeaderGeometry(
            stories: stories ? range(Self.storiesId) : nil,
            search: search ? range(Self.searchId) : nil,
            folders: folders ? frame(Self.foldersId)?.minY : nil
        )
    }

    /// Доехать до `target` (верх видимой части в координатах содержимого).
    func scroll(to target: CGFloat, animated: Bool) {
        guard let scroll = scrollView else { return }
        let insets = scroll.adjustedContentInset
        let maxY = max(-insets.top, scroll.contentSize.height + insets.bottom - scroll.bounds.height)
        let y = min(max(target - insets.top, -insets.top), maxY)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: animated)
    }

    /// Остановить инерцию и встать на `target`.
    func stop(at target: CGFloat) {
        guard let scroll = scrollView else { return }
        scroll.setContentOffset(scroll.contentOffset, animated: false)
        self.scroll(to: target, animated: false)
    }

    private func range(_ id: String) -> ClosedRange<CGFloat>? {
        frame(id).map { $0.minY...$0.maxY }
    }

    private func frame(_ id: String) -> CGRect? {
        if let view = probes[id]?.view, let scroll = scrollView, view.window != nil, view.isDescendant(of: scroll) {
            let frame = view.convert(view.bounds, to: scroll)
            frames[id] = frame
            return frame
        }
        return frames[id]
    }

    private func moved(_ scroll: UIScrollView) {
        let now = scroll.contentOffset.y + scroll.adjustedContentInset.top
        let previous = lastTop
        lastTop = now
        onScroll?(previous, now, scroll.isTracking || scroll.isDragging, scroll.isDecelerating)
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled, !self.isInteracting else { return }
            self.onIdle?()
        }
    }
}

/// Метка в строке шапки: находит `UIScrollView` списка и сообщает, где лежит строка.
struct ChatListProbe: UIViewRepresentable {
    let id: String
    let scroll: ChatListScroll

    func makeUIView(context: Context) -> ProbeView { ProbeView(id: id, scroll: scroll) }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        private let id: String
        private let scroll: ChatListScroll

        init(id: String, scroll: ChatListScroll) {
            self.id = id
            self.scroll = scroll
            super.init(frame: .zero)
            isHidden = true
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            scroll.register(self, id: id)
            var view = superview
            while let current = view {
                if let list = current as? UIScrollView {
                    scroll.attach(list)
                    return
                }
                view = current.superview
            }
        }
    }
}
