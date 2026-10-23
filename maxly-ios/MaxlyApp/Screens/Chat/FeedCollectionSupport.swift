import QuartzCore
import SwiftUI
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

/// Высота самого пузыря, а не рамки ячейки. Ячейка предлагает свою высоту, и замер
/// `systemLayoutSizeFitting` повторяет её: короткая оценка тогда навсегда обрезает пузырь,
/// а сосед рисуется поверх обрезанного края.
struct FeedContentHeightReader: View {
    var onHeight: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.height, initial: true) { _, height in
                    onHeight(height)
                }
        }
    }
}

/// Ячейка UIHostingConfiguration. Высота для ленты уже посчитана; здесь только поправка,
/// если SwiftUI оказался выше или ниже оценки. Содержимое не рисуется поверх соседа.
final class MeasuredHostingCell: UICollectionViewCell {
    var onMeasuredHeight: ((CGFloat) -> Void)?
    /// Строка сообщает свою высоту из SwiftUI. Повторный замер по рамке ячейки её затирает.
    var usesIntrinsicHeight = false
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
        usesIntrinsicHeight = false
    }

    func resetMeasurement() {
        attempts = 0
        candidate = 0
        reported = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clipsToBounds = true
        contentView.clipsToBounds = true
        guard !usesIntrinsicHeight, !measuring, attempts < 5, bounds.width > 1, onMeasuredHeight != nil else { return }
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

    /// Рамка ленты в окне. Вне окна `convert` возвращает bounds, и смещение −6 выглядит как верх экрана.
    static func windowFrame(_ view: UIView) -> CGRect? {
        guard view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }

    struct WindowChrome {
        var safeTop: CGFloat
        var safeBottom: CGFloat
        var height: CGFloat
    }

    static func windowChrome() -> WindowChrome {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        let safe = window?.safeAreaInsets ?? .zero
        return WindowChrome(safeTop: safe.top, safeBottom: safe.bottom, height: window?.bounds.height ?? 0)
    }

    /// Полный content inset шапки и поля ввода. `.never`: safe area не прибавляется второй раз.
    /// У верхнего края смещение остаётся на новом inset, иначе первый кадр показывает сообщения под шапкой.
    @discardableResult
    static func applyChrome(
        _ collection: UICollectionView,
        headerBottom: CGFloat?,
        composerTop: CGFloat?
    ) -> Bool {
        collection.contentInsetAdjustmentBehavior = .never
        collection.automaticallyAdjustsScrollIndicatorInsets = false
        hideSystemEdgeEffects(collection)
        let window = windowChrome()
        let safe = collection.safeAreaInsets
        let unresolvedHeader = FeedOffset.unresolvedHeader(
            safeTop: Double(safe.top),
            windowTop: Double(window.safeTop)
        )
        let unresolvedComposer = FeedOffset.unresolvedComposer(
            safeBottom: Double(safe.bottom),
            windowBottom: Double(window.safeBottom)
        )
        let headerOverlap: Double
        let composerOverlap: Double
        if let frame = windowFrame(collection), frame.height > 1, window.height > 1 {
            headerOverlap = FeedOffset.headerOverlap(
                frameMinY: Double(frame.minY),
                frameMaxY: Double(frame.maxY),
                headerBottom: headerBottom.map(Double.init),
                unresolved: unresolvedHeader
            )
            composerOverlap = FeedOffset.composerOverlap(
                frameMinY: Double(frame.minY),
                frameMaxY: Double(frame.maxY),
                frameReachesScreenBottom: frame.maxY >= window.height - 1,
                composerTop: composerTop.map(Double.init),
                unresolved: unresolvedComposer
            )
        } else {
            headerOverlap = unresolvedHeader
            composerOverlap = unresolvedComposer
        }
        let resolved = FeedOffset.chromeInsets(
            boundsHeight: Double(collection.bounds.height),
            contentHeight: Double(collection.contentSize.height),
            headerOverlap: headerOverlap,
            composerOverlap: composerOverlap
        )
        let top = CGFloat(resolved.top)
        let bottom = CGFloat(resolved.bottom)
        let oldTop = collection.contentInset.top
        let oldBottom = collection.contentInset.bottom
        guard abs(oldTop - top) > 0.5 || abs(oldBottom - bottom) > 0.5 else { return false }
        let restingAtTop = abs(collection.contentOffset.y + oldTop) < 1
            || (collection.contentSize.height < 1 && abs(collection.contentOffset.y) < 1)
            || (abs(collection.contentOffset.y) < 1 && oldTop < 1)
        performWithoutAnimation {
            collection.contentInset = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
            var indicator = collection.verticalScrollIndicatorInsets
            indicator.top = top
            indicator.bottom = bottom
            collection.verticalScrollIndicatorInsets = indicator
            if restingAtTop {
                collection.contentOffset.y = -top
            }
        }
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
        headerBottom: CGFloat? = nil,
        composerTop: CGFloat? = nil,
        rowFrame: (String) -> CGRect?
    ) -> Bool {
        if !interacting, applyChrome(collection, headerBottom: headerBottom, composerTop: composerTop) {
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

    /// Лента на весь экран, под полупрозрачной шапкой и полем ввода.
    /// `contentInsetAdjustmentBehavior = .never`: зазор задаётся вручную и не суммируется с safe area.
    /// Стартовый inset берётся из окна, чтобы первый кадр не был с зазором в 6 pt под шапкой.
    static func install(_ collection: UICollectionView) {
        collection.backgroundColor = .clear
        collection.clipsToBounds = true
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .interactive
        collection.scrollsToTop = false
        collection.contentInsetAdjustmentBehavior = .never
        collection.insetsLayoutMarginsFromSafeArea = false
        collection.automaticallyAdjustsScrollIndicatorInsets = false
        hideSystemEdgeEffects(collection)
        let window = windowChrome()
        let seed = FeedOffset.chromeInsets(
            boundsHeight: 0,
            contentHeight: 0,
            headerOverlap: FeedOffset.unresolvedHeader(safeTop: 0, windowTop: Double(window.safeTop)),
            composerOverlap: FeedOffset.unresolvedComposer(safeBottom: 0, windowBottom: Double(window.safeBottom))
        )
        let top = CGFloat(seed.top)
        let bottom = CGFloat(seed.bottom)
        collection.contentInset = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        collection.verticalScrollIndicatorInsets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        collection.contentOffset = CGPoint(x: 0, y: -top)
        if let flow = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            flow.sectionInsetReference = .fromContentInset
        }
    }

    /// Системный край прокрутки на новых iOS затемняет верх и низ ленты поверх своего размытия.
    static func hideSystemEdgeEffects(_ collection: UIScrollView) {
        if #available(iOS 26.0, *) {
            collection.topEdgeEffect.isHidden = true
            collection.bottomEdgeEffect.isHidden = true
            collection.leftEdgeEffect.isHidden = true
            collection.rightEdgeEffect.isHidden = true
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
    /// Поле ввода и клавиатура уже в content inset. Если читатель у низа и палец не держит ленту,
    /// низ остаётся у последнего сообщения.
    static func pinBottomIfNeeded(
        _ collection: UICollectionView,
        nearBottom: Bool,
        heightChanged: Bool,
        headerBottom: CGFloat? = nil,
        composerTop: CGFloat? = nil
    ) {
        guard nearBottom, heightChanged, !FeedScroll.isInteracting(collection) else { return }
        _ = FeedScroll.applyChrome(collection, headerBottom: headerBottom, composerTop: composerTop)
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
