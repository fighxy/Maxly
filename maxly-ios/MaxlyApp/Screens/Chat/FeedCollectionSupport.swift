import QuartzCore
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

/// Ячейка UIHostingConfiguration. Высота для ленты уже посчитана; здесь только поправка,
/// если SwiftUI оказался выше или ниже оценки. Содержимое не рисуется поверх соседа.
final class MeasuredHostingCell: UICollectionViewCell {
    var onMeasuredHeight: ((CGFloat) -> Void)?
    private var attempts = 0
    private var candidate: CGFloat = 0
    private var reported: CGFloat = 0
    private var measuring = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        contentView.clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetMeasurement()
        onMeasuredHeight = nil
    }

    func resetMeasurement() {
        attempts = 0
        candidate = 0
        reported = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !measuring, attempts < 5, bounds.width > 1, onMeasuredHeight != nil else { return }
        measuring = true
        let fitted = contentView.systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        measuring = false
        attempts += 1
        let height = fitted.height
        guard height.isFinite, height > 8, height < 4000 else { return }
        // Оценка уже совпала с тем, что нарисовал SwiftUI.
        if abs(height - bounds.height) <= 2 { return }
        if candidate == 0 || abs(height - candidate) > 1 {
            candidate = height
            if attempts < 5 {
                DispatchQueue.main.async { [weak self] in self?.setNeedsLayout() }
            }
            return
        }
        guard abs(height - reported) > 2 else { return }
        reported = height
        attempts = 5
        onMeasuredHeight?(height)
    }
}

@MainActor
enum FeedScroll {
    struct Anchor: Equatable {
        var id: String
        /// Верх строки минус contentOffset до обновления. Отрицательный — строка началась выше экрана.
        var topInViewport: CGFloat
    }

    struct Reveal: Equatable {
        var id: String
        var anchor: Double
        var latest: Bool
    }

    static func isInteracting(_ scroll: UIScrollView) -> Bool {
        scroll.isTracking || scroll.isDragging || scroll.isDecelerating
    }

    /// Расстояние до низа ленты. Отрицательное — контент короче экрана.
    static func distanceFromBottom(_ scroll: UIScrollView) -> CGFloat {
        let inset = scroll.adjustedContentInset
        let maxY = scroll.contentSize.height - scroll.bounds.height + inset.bottom
        return maxY - scroll.contentOffset.y
    }

    static func isNearBottom(_ scroll: UIScrollView, slack: CGFloat = 24) -> Bool {
        guard scroll.bounds.height > 1, scroll.contentSize.height > 1 else { return true }
        return distanceFromBottom(scroll) < slack
    }

    static func pinToBottom(_ scroll: UIScrollView) {
        guard scroll.bounds.height > 1 else { return }
        let inset = scroll.adjustedContentInset
        let minY = -inset.top
        let y = scroll.contentSize.height - scroll.bounds.height + inset.bottom
        scroll.contentOffset.y = max(minY, y)
    }

    /// Верхняя видимая строка — якорь. После вставки сверху её верх остаётся на том же месте экрана.
    static func captureAnchor(_ collection: UICollectionView, id: (IndexPath) -> String?) -> Anchor? {
        let offset = collection.contentOffset.y
        let paths = collection.indexPathsForVisibleItems.sorted {
            if $0.section != $1.section { return $0.section < $1.section }
            return $0.item < $1.item
        }
        for path in paths {
            guard let itemID = id(path),
                  let frame = collection.layoutAttributesForItem(at: path)?.frame,
                  frame.maxY > offset + 0.5 else { continue }
            return Anchor(id: itemID, topInViewport: frame.minY - offset)
        }
        return nil
    }

    @discardableResult
    static func applyShortInset(_ collection: UICollectionView) -> Bool {
        let top = CGFloat(FeedOffset.shortTopInset(
            boundsHeight: Double(collection.bounds.height),
            safeTop: Double(collection.safeAreaInsets.top),
            safeBottom: Double(collection.safeAreaInsets.bottom),
            contentHeight: Double(collection.contentSize.height)
        ))
        guard abs(collection.contentInset.top - top) > 0.5 else { return false }
        var inset = collection.contentInset
        inset.top = top
        inset.bottom = CGFloat(FeedOffset.baseBottomInset)
        collection.contentInset = inset
        return true
    }

    static func contentFits(_ collection: UICollectionView) -> Bool {
        let inset = collection.adjustedContentInset
        return FeedOffset.contentFits(
            contentHeight: Double(collection.contentSize.height),
            boundsHeight: Double(collection.bounds.height),
            insetTop: Double(inset.top),
            insetBottom: Double(inset.bottom)
        )
    }

    /// `true`, если смещение уже выставлено (низ, цель или якорь).
    @discardableResult
    static func settle(
        _ collection: UICollectionView,
        anchor: Anchor?,
        reveal: Reveal?,
        stickToBottom: Bool,
        interacting: Bool,
        rowFrame: (String) -> CGRect?
    ) -> Bool {
        if !interacting, applyShortInset(collection) {
            collection.layoutIfNeeded()
        }
        let plan = FeedSettle.plan(
            interacting: interacting,
            contentFits: !interacting && contentFits(collection),
            stickToBottom: stickToBottom,
            hasHistoryReveal: reveal.map { !$0.latest } ?? false,
            pinToLatest: reveal?.latest == true,
            hasAnchor: anchor != nil
        )
        switch plan {
        case .pinBottom:
            pinToBottom(collection)
            return true
        case .reveal:
            guard let reveal, let frame = rowFrame(reveal.id) else { return false }
            revealRow(collection, frame: frame, anchor: CGFloat(reveal.anchor))
            return true
        case .restore:
            guard let anchor, let frame = rowFrame(anchor.id) else { return false }
            restore(collection, anchor: anchor, rowMinY: frame.minY)
            return true
        case .keep:
            return false
        }
    }

    static func revealRow(_ collection: UICollectionView, frame: CGRect, anchor: CGFloat) {
        let inset = collection.adjustedContentInset
        let viewport = collection.bounds.height - inset.top - inset.bottom
        let minOffset = -inset.top
        let maxOffset = collection.contentSize.height - collection.bounds.height + inset.bottom
        collection.contentOffset.y = CGFloat(FeedOffset.revealing(
            rowMinY: Double(frame.minY),
            rowHeight: Double(frame.height),
            anchor: Double(anchor),
            viewportHeight: Double(max(0, viewport)),
            insetTop: Double(inset.top),
            minOffset: Double(minOffset),
            maxOffset: Double(maxOffset)
        ))
    }

    static func restore(_ collection: UICollectionView, anchor: Anchor, rowMinY: CGFloat) {
        let inset = collection.adjustedContentInset
        let minOffset = -inset.top
        let maxOffset = collection.contentSize.height - collection.bounds.height + inset.bottom
        let y = CGFloat(FeedOffset.restoring(
            rowMinY: Double(rowMinY),
            topInViewport: Double(anchor.topInViewport),
            minOffset: Double(minOffset),
            maxOffset: Double(maxOffset)
        ))
        if abs(collection.contentOffset.y - y) > 0.5 {
            collection.contentOffset.y = y
        }
    }

    static func fallbackOffset(_ collection: UICollectionView, beforeOffset: CGFloat, beforeHeight: CGFloat) -> CGFloat? {
        guard beforeHeight > 1 else { return nil }
        let delta = collection.contentSize.height - beforeHeight
        guard abs(delta) > 1 else { return nil }
        let inset = collection.adjustedContentInset
        let minOffset = -inset.top
        let maxOffset = collection.contentSize.height - collection.bounds.height + inset.bottom
        return CGFloat(FeedOffset.clamped(
            Double(beforeOffset + delta),
            min: Double(minOffset),
            max: Double(maxOffset)
        ))
    }

    /// Шапка и поле ввода приходят как safe area SwiftUI. Лента их учитывает один раз
    /// и добавляет небольшой зазор, чтобы первое и последнее сообщение не прилипали к краям.
    static func install(_ collection: UICollectionView) {
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .interactive
        collection.contentInsetAdjustmentBehavior = .automatic
        collection.insetsLayoutMarginsFromSafeArea = false
        collection.contentInset = UIEdgeInsets(
            top: CGFloat(FeedOffset.baseTopInset),
            left: 0,
            bottom: CGFloat(FeedOffset.baseBottomInset),
            right: 0
        )
        if let flow = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            flow.sectionInsetReference = .fromContentInset
        }
    }

    /// Снимок и смещение в одном ходе, без анимации слоя: иначе вставка двигает пальцевое место.
    static func performWithoutAnimation(_ work: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation(work)
        CATransaction.commit()
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
enum FeedLayoutAdjust {
    /// Клавиатура и поле ввода уже сидят в safe area. Если читатель у низа и палец не держит ленту,
    /// низ остаётся у последнего сообщения.
    static func pinBottomIfNeeded(
        _ collection: UICollectionView,
        nearBottom: Bool,
        heightChanged: Bool
    ) {
        guard nearBottom, heightChanged, !FeedScroll.isInteracting(collection) else { return }
        _ = FeedScroll.applyShortInset(collection)
        FeedScroll.pinToBottom(collection)
    }

    static func compensateOffset(
        _ collection: UICollectionView,
        attributes: UICollectionViewLayoutAttributes?,
        newHeight: CGFloat,
        dragging: Bool
    ) -> CGFloat {
        guard !dragging, let attributes else { return 0 }
        let delta = Double(newHeight) - Double(attributes.frame.height)
        return CGFloat(FeedOffset.compensation(
            itemMaxY: Double(attributes.frame.maxY),
            viewportOffset: Double(collection.contentOffset.y),
            heightDelta: delta
        ))
    }
}
