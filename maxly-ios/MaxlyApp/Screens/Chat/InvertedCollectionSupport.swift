import UIKit
import MaxlyPresentation

/// Поколение prewarm: смена ширины отменяет запись высот, посчитанных для старой ширины.
final class PrewarmEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }

    func matches(_ ticket: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return value == ticket
    }
}

/// Ячейка UIHostingConfiguration: после раскладки SwiftUI может поправить высоту в кэше.
final class MeasuredHostingCell: UICollectionViewCell {
    var onMeasuredHeight: ((CGFloat) -> Void)?
    private var measureAttempts = 0
    private var measuring = false

    static let invert = CGAffineTransform(scaleX: 1, y: -1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        transform = Self.invert
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        measureAttempts = 0
        measuring = false
        onMeasuredHeight = nil
        transform = Self.invert
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        // Атрибуты сбрасывают transform в identity и переворачивают текст.
        transform = Self.invert
    }

    func resetMeasurement() {
        measureAttempts = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !measuring, measureAttempts < 3, bounds.width > 1, bounds.height > 1 else { return }
        measuring = true
        let fitted = contentView.systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        measuring = false
        measureAttempts += 1
        let delta = abs(fitted.height - bounds.height)
        guard fitted.height > 8, fitted.height < 2500, delta > 2 else { return }
        // Безумный fitting (хост на всю высоту экрана) не должен затирать оценку TextKit.
        guard fitted.height < max(bounds.height * 2.5, bounds.height + 220) else {
            measureAttempts = 3
            return
        }
        measureAttempts = 3
        onMeasuredHeight?(fitted.height)
    }
}

/// UICollectionView с `scaleY(-1)`: системный индикатор тоже переворачивается,
/// VoiceOver без правки читает снизу вверх.
final class InvertedCollectionView: UICollectionView {
    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        insetsLayoutMarginsFromSafeArea = false
        keyboardDismissMode = .interactive
        scrollsToTop = false
        alwaysBounceVertical = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityElementCount() -> Int {
        indexPathsForVisibleItems.count
    }

    override func accessibilityElement(at index: Int) -> Any? {
        let ordered = InvertedAccessibilityOrder.topToBottom(visibleFeedPaths())
        guard ordered.indices.contains(index) else { return nil }
        let path = ordered[index]
        return cellForItem(at: IndexPath(item: path.item, section: path.section))
    }

    override func index(ofAccessibilityElement element: Any) -> Int {
        let ordered = InvertedAccessibilityOrder.topToBottom(visibleFeedPaths())
        guard let cell = element as? UIView else { return NSNotFound }
        return ordered.firstIndex { path in
            cellForItem(at: IndexPath(item: path.item, section: path.section)) === cell
        } ?? NSNotFound
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let page = bounds.height * 0.85
        let delta: CGFloat
        switch direction {
        case .up:
            delta = page
        case .down:
            delta = -page
        default:
            return super.accessibilityScroll(direction)
        }
        let minY = -adjustedContentInset.top
        let maxY = max(minY, contentSize.height - bounds.height + adjustedContentInset.bottom)
        let y = min(maxY, max(minY, contentOffset.y + delta))
        guard abs(y - contentOffset.y) > 1 else { return false }
        setContentOffset(CGPoint(x: contentOffset.x, y: y), animated: false)
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
        return true
    }

    private func visibleFeedPaths() -> [FeedIndexPath] {
        indexPathsForVisibleItems.map { FeedIndexPath(section: $0.section, item: $0.item) }
    }
}

/// Индикатор рисуется в координатах контроллера, не внутри перевёрнутой коллекции.
final class InvertedScrollThumb: UIView {
    private let thumb = UIView()
    private var fade: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        thumb.backgroundColor = UIColor.label.withAlphaComponent(0.35)
        thumb.layer.cornerRadius = 1.5
        addSubview(thumb)
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync(with scroll: UIScrollView, active: Bool) {
        let frame = InvertedThumbFrame.make(
            offset: Double(scroll.contentOffset.y),
            content: Double(scroll.contentSize.height),
            viewport: Double(scroll.bounds.height),
            track: Double(bounds.height)
        )
        guard !frame.hidden else {
            alpha = 0
            thumb.frame = .zero
            return
        }
        thumb.frame = CGRect(x: bounds.width - 5, y: frame.y, width: 3, height: frame.height)
        guard active else { return }
        fade?.cancel()
        alpha = 1
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.25) { self?.alpha = 0 }
        }
        fade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
}

/// Пачка поправок высоты на следующий ход, чтобы не звать invalidate из layoutSubviews.
@MainActor
final class MeasuredLayoutCommit {
    struct Batch {
        var rows: [String: Double]
        var chrome: [String: CGFloat]
    }

    private var rows: [String: Double] = [:]
    private var chrome: [String: CGFloat] = [:]
    private var scheduled = false
    private let apply: @MainActor (Batch) -> Void

    init(apply: @escaping @MainActor (Batch) -> Void) {
        self.apply = apply
    }

    func row(_ height: CGFloat, id: String, current: Double?) {
        guard accept(height) else { return }
        if let current, abs(current - Double(height)) < 2 { return }
        rows[id] = Double(height)
        schedule()
    }

    func chrome(_ height: CGFloat, id: String, current: CGFloat?) {
        guard accept(height) else { return }
        if let current, abs(current - height) < 2 { return }
        chrome[id] = height
        schedule()
    }

    private func accept(_ height: CGFloat) -> Bool {
        height.isFinite && height > 8 && height < 4000
    }

    private func schedule() {
        guard !scheduled else { return }
        scheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let batch = Batch(rows: self.rows, chrome: self.chrome)
            self.rows.removeAll()
            self.chrome.removeAll()
            self.scheduled = false
            guard !batch.rows.isEmpty || !batch.chrome.isEmpty else { return }
            self.apply(batch)
        }
    }
}

@MainActor
enum InvertedCollectionChrome {
    /// Клавиатура и шапка уже сидят в safe area SwiftUI. Автоинсет у flip
    /// приезжает не с той стороны и прячет новые сообщения под композером.
    static func pinVisualBottomIfNeeded(
        _ collection: UICollectionView,
        nearBottom: Bool,
        heightChanged: Bool
    ) {
        guard nearBottom, heightChanged else { return }
        collection.contentOffset.y = -collection.adjustedContentInset.top
    }

    static func compensateOffset(
        _ collection: UICollectionView,
        attributes: UICollectionViewLayoutAttributes?,
        newHeight: CGFloat,
        dragging: Bool
    ) -> CGFloat {
        guard !dragging, let attributes else { return 0 }
        let delta = Double(newHeight) - Double(attributes.frame.height)
        return CGFloat(MeasuredOffsetCompensation.delta(
            itemMaxY: Double(attributes.frame.maxY),
            viewportOffset: Double(collection.contentOffset.y),
            heightDelta: delta
        ))
    }
}
