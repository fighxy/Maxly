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

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
        contentView.clipsToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        measureAttempts = 0
        measuring = false
        onMeasuredHeight = nil
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
        // Длинный пост канала выше оценки в разы. Режем только безумный fitting.
        guard fitted.height > 8, fitted.height < 4000, delta > 2 else { return }
        measureAttempts = 3
        onMeasuredHeight?(fitted.height)
    }
}

@MainActor
enum FeedScroll {
    /// Расстояние до низа ленты. Отрицательное — контент короче экрана.
    static func distanceFromBottom(_ scroll: UIScrollView) -> CGFloat {
        let inset = scroll.adjustedContentInset
        let maxY = scroll.contentSize.height - scroll.bounds.height + inset.bottom
        return maxY - scroll.contentOffset.y
    }

    static func isNearBottom(_ scroll: UIScrollView, slack: CGFloat = 64) -> Bool {
        guard scroll.bounds.height > 1, scroll.contentSize.height > 1 else { return true }
        return distanceFromBottom(scroll) < slack
    }

    static func pinToBottom(_ scroll: UIScrollView) {
        guard scroll.bounds.height > 1 else { return }
        let inset = scroll.adjustedContentInset
        let y = scroll.contentSize.height - scroll.bounds.height + inset.bottom
        scroll.contentOffset.y = max(-inset.top, y)
    }

    /// Шапка и поле ввода приходят как safe area. Лента их учитывает, плюс небольшой зазор,
    /// чтобы первое и последнее сообщение не прилипали к краям.
    static func install(_ collection: UICollectionView) {
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .interactive
        collection.contentInsetAdjustmentBehavior = .automatic
        collection.contentInset = UIEdgeInsets(top: 6, left: 0, bottom: 10, right: 0)
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
    /// Клавиатура уже сжимает ленту через safe area SwiftUI.
    static func pinBottomIfNeeded(
        _ collection: UICollectionView,
        nearBottom: Bool,
        heightChanged: Bool
    ) {
        guard nearBottom, heightChanged else { return }
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
        return CGFloat(MeasuredOffsetCompensation.delta(
            itemMaxY: Double(attributes.frame.maxY),
            viewportOffset: Double(collection.contentOffset.y),
            heightDelta: delta
        ))
    }
}
