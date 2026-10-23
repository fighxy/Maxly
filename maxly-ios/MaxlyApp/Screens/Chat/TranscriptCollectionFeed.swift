import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Лента на UICollectionView: старое сверху, новое снизу.
/// Якорь и низ держатся `contentOffset` и `contentInset`. Слой не переворачивается.
struct TranscriptCollectionFeed: UIViewControllerRepresentable {
    typealias Reveal = FeedScroll.Reveal

    @Bindable var viewModel: ChatViewModel
    let rows: [TranscriptRow]
    let width: CGFloat
    let revealMode: PrivateModeReveal
    let feedInset: CGFloat
    let reduceMotion: Bool
    let isOpening: Bool
    let isRestoringHistory: Bool
    let scrollRequest: TranscriptScrollController.Request?
    let stickToBottom: Bool
    let reveal: Reveal?
    let canLoadOlder: Bool
    let isLoadingOlder: Bool
    let isJumped: Bool
    let emptyHint: String?
    let showsChannelReady: Bool
    let showsEmpty: Bool
    /// Низ шапки в глобальных координатах. `nil` — ещё не измерен, лента берёт safe area окна.
    let headerBottom: CGFloat?
    /// Верх поля ввода или клавиатуры в глобальных координатах. `nil` — ещё не измерен.
    let composerTop: CGFloat?

    var snapshot: (TranscriptRow) -> TranscriptBubble.Snapshot
    var onAuthor: (Message) -> Void
    var onFrames: (_ rows: [String: CGRect], _ viewport: CGRect, _ contentTop: CGFloat) -> Void
    var onBottomDistance: (Double, Double) -> Void
    var onUserScroll: (_ moving: Bool, _ takeover: Bool) -> Void
    var onTopVisible: (Bool) -> Void
    var onNearTopPrefix: (Int?) -> Void
    var onLoadOlder: () -> Void
    var onLoadNewer: () -> Void
    var onScrollFinished: (_ token: Int, _ confirmed: Bool) -> Void
    var onPrefetchURLs: ([URL]) -> Void

    func makeUIViewController(context: Context) -> TranscriptCollectionController {
        let controller = TranscriptCollectionController()
        context.coordinator.controller = controller
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: TranscriptCollectionController, context: Context) {
        context.coordinator.parent = self
        controller.coordinator = context.coordinator
        context.coordinator.apply(self)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
        var parent: TranscriptCollectionFeed
        weak var controller: TranscriptCollectionController?
        private var heightCache = BubbleHeightCache()
        private var lastRequestToken: Int?
        private var scrollTask: Task<Void, Never>?
        private var geometrySampler = TranscriptGeometrySampler()
        private var lastOffsetY: CGFloat = 0
        /// Палец тянет к истории (визуальный верх = старое).
        private var scrollingTowardOlder = false
        private var lastPrefetchKey = ""
        private var prewarmKey = ""
        private var shownSnapshots: [String: TranscriptBubble.Snapshot] = [:]
        private let prewarmEpoch = PrewarmEpoch()

        init(_ parent: TranscriptCollectionFeed) {
            self.parent = parent
        }

        func cancelPrewarm() {
            prewarmKey = ""
            _ = prewarmEpoch.next()
        }

        func apply(_ feed: TranscriptCollectionFeed) {
            guard let controller else { return }
            controller.loadViewIfNeeded()
            controller.collectionView?.delegate = self
            controller.collectionView?.prefetchDataSource = self
            controller.setChrome(headerBottom: feed.headerBottom, composerTop: feed.composerTop)
            prewarmHeights(feed.rows, width: feed.width, feedInset: feed.feedInset)
            controller.setRows(
                feed.rows,
                feedInset: feed.feedInset,
                heightCache: heightCache,
                header: headerKind(feed),
                footerLoading: feed.isJumped,
                stickToBottom: feed.stickToBottom,
                reveal: feed.reveal
            )
            syncVisibleCells()
            if let request = feed.scrollRequest, request.token != lastRequestToken {
                lastRequestToken = request.token
                runScroll(request)
            } else if feed.scrollRequest == nil {
                lastRequestToken = nil
            }
            scheduleImagePrefetch(force: true)
        }

        private func headerKind(_ feed: TranscriptCollectionFeed) -> TranscriptCollectionController.HeaderKind {
            if let hint = feed.emptyHint { return .hint(hint) }
            if feed.showsChannelReady { return .channelReady }
            if feed.showsEmpty { return .empty }
            if feed.canLoadOlder { return .olderLoader(loading: feed.isLoadingOlder) }
            return .none
        }

        private func prewarmHeights(_ rows: [TranscriptRow], width: CGFloat, feedInset: CGFloat) {
            let key = "\(Int(width.rounded())):\(rows.count):\(rows.first?.id ?? ""):\(rows.last?.id ?? "")"
            guard key != prewarmKey else { return }
            prewarmKey = key
            let maxWidth = Double(min(520, max(0, width - feedInset * 2) * MaxlyTheme.bubbleMax))
            let cache = heightCache
            let epoch = prewarmEpoch
            let ticket = epoch.next()
            Task.detached(priority: .utility) {
                for row in rows {
                    if !epoch.matches(ticket) { return }
                    let height = BubbleHeightCache.estimate(row: row, maxWidth: maxWidth)
                    cache.storeIfAbsent(id: row.id, height: height)
                }
            }
        }

        /// Видимые пузыри обновляются по снимку. Идентификатор строки в diffable — id сообщения,
        /// поэтому правка, реакция и ход голосового сами ячейку не пересоздают.
        private func syncVisibleCells() {
            guard let controller, let collection = controller.collectionView else { return }
            let live = Set(parent.rows.map(\.id))
            shownSnapshots = shownSnapshots.filter { live.contains($0.key) }
            let interacting = FeedScroll.isInteracting(collection)
            for indexPath in collection.indexPathsForVisibleItems where indexPath.section == TranscriptCollectionController.rowsSection {
                guard let row = controller.row(atDisplayIndex: indexPath.item),
                      let cell = collection.cellForItem(at: indexPath) else { continue }
                let snap = parent.snapshot(row)
                let previous = shownSnapshots[row.id]
                guard previous != snap else { continue }
                let layoutChanged = previous?.row != snap.row
                if interacting, !layoutChanged { continue }
                shownSnapshots[row.id] = snap
                if layoutChanged {
                    if interacting {
                        controller.deferRemeasure(row.id)
                    } else if let measured = cell as? MeasuredHostingCell {
                        measured.resetMeasurement()
                        measured.setNeedsLayout()
                    }
                }
                configure(cell, row: row)
            }
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            sampleGeometry(force: false)
        }

        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            sampleGeometry(force: false)
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            scheduleImagePrefetch(force: false)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            if abs(y - lastOffsetY) > 1 {
                scrollingTowardOlder = y < lastOffsetY
                lastOffsetY = y
            }
            reportBottom(scrollView)
            sampleGeometry(force: false)
            updateTopVisible()
            scheduleImagePrefetch(force: false)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            controller?.releaseBottomPin()
            controller?.setUserScrolling(true)
            parent.onUserScroll(true, true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                controller?.setUserScrolling(false)
                parent.onUserScroll(false, false)
                sampleGeometry(force: true)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            controller?.setUserScrolling(false)
            parent.onUserScroll(false, false)
            sampleGeometry(force: true)
        }

        func configure(_ cell: UICollectionViewCell, row: TranscriptRow) {
            let state = parent.snapshot(row)
            shownSnapshots[row.id] = state
            let revealMode = parent.revealMode
            let report: (CGFloat) -> Void = { [weak cell] height in
                (cell as? MeasuredHostingCell)?.onMeasuredHeight?(height)
            }
            if let measured = cell as? MeasuredHostingCell {
                measured.usesIntrinsicHeight = true
            }
            cell.contentConfiguration = UIHostingConfiguration {
                TranscriptBubble(
                    state: state,
                    viewModel: parent.viewModel,
                    reveal: revealMode,
                    onAuthor: parent.onAuthor
                )
                .equatable()
                .fixedSize(horizontal: false, vertical: true)
                .background(FeedContentHeightReader(onHeight: report))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .margins(.all, 0)
            .minSize(width: 0, height: 0)
        }

        private func runScroll(_ request: TranscriptScrollController.Request) {
            scrollTask?.cancel()
            scrollTask = Task { @MainActor [weak self] in
                guard let self, let controller else { return }
                await Task.yield()
                guard !Task.isCancelled, parent.scrollRequest?.token == request.token else { return }
                let confirmed = await controller.scrollTo(
                    id: request.id,
                    anchor: request.anchor,
                    latest: request.latest,
                    stillCurrent: { [weak self] in self?.parent.scrollRequest?.token == request.token }
                )
                guard !Task.isCancelled, parent.scrollRequest?.token == request.token else { return }
                parent.onScrollFinished(request.token, confirmed)
            }
        }

        private func sampleGeometry(force: Bool) {
            let now = DispatchTime.now().uptimeNanoseconds
            guard geometrySampler.shouldFire(nowNs: now, force: force) else { return }
            guard let controller, let collection = controller.collectionView,
                  let viewport = FeedScroll.windowFrame(collection) else { return }
            var frames: [String: CGRect] = [:]
            var chronoIndices: [Int] = []
            let visibleRows = collection.indexPathsForVisibleItems
                .filter { $0.section == TranscriptCollectionController.rowsSection }
            for indexPath in visibleRows {
                guard let row = controller.row(atDisplayIndex: indexPath.item),
                      let cell = collection.cellForItem(at: indexPath),
                      let chrono = controller.chronologicalIndex(display: indexPath.item)
                else { continue }
                let frame = cell.convert(cell.bounds, to: nil)
                frames[row.id] = frame
                chronoIndices.append(chrono)
            }
            parent.onFrames(frames, viewport, 0)
            parent.onNearTopPrefix(chronoIndices.min())
        }

        private func reportBottom(_ scrollView: UIScrollView) {
            guard let controller, let collection = controller.collectionView else { return }
            let inset = collection.adjustedContentInset
            let readableHeight = max(0, collection.bounds.height - inset.top - inset.bottom)
            if let viewport = FeedScroll.windowFrame(collection),
               let last = parent.rows.last,
               let display = controller.displayIndex(for: last.id),
               let cell = collection.cellForItem(at: IndexPath(item: display, section: TranscriptCollectionController.rowsSection)) {
                let frame = cell.convert(cell.bounds, to: nil)
                let distance = FeedOffset.distanceAboveCover(
                    rowMaxY: Double(frame.maxY),
                    viewportMaxY: Double(viewport.maxY),
                    cover: Double(inset.bottom)
                )
                parent.onBottomDistance(distance, Double(readableHeight))
                return
            }
            let distance = max(0, Double(FeedScroll.distanceFromBottom(scrollView)))
            parent.onBottomDistance(distance, Double(readableHeight))
        }

        private func updateTopVisible() {
            guard let controller else { return }
            parent.onTopVisible(controller.isOlderChromeVisibleOnScreen)
        }

        private func scheduleImagePrefetch(force: Bool) {
            guard let controller else { return }
            let visible = controller.collectionView?.indexPathsForVisibleItems
                .filter { $0.section == TranscriptCollectionController.rowsSection }
                .compactMap { controller.chronologicalIndex(display: $0.item) }
                .sorted()
            let range: Range<Int>? = {
                guard let visible, let first = visible.first, let last = visible.last else { return nil }
                return first..<(last + 1)
            }()
            let plan = TranscriptImagePrefetch.plan(
                messages: parent.viewModel.messages,
                visibleRange: range,
                scrollingTowardOlder: scrollingTowardOlder
            )
            let key = plan.urls.map(\.absoluteString).joined(separator: "|")
            guard force || key != lastPrefetchKey else { return }
            lastPrefetchKey = key
            guard !plan.urls.isEmpty else { return }
            parent.onPrefetchURLs(plan.urls)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            controller?.sizeForItem(at: indexPath, containerWidth: collectionView.bounds.width)
                ?? CGSize(width: max(1, collectionView.bounds.width), height: 44)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            minimumLineSpacingForSectionAt section: Int
        ) -> CGFloat {
            section == TranscriptCollectionController.rowsSection ? CGFloat(BubbleHeightCache.rowSpacing) : 0
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            insetForSectionAt section: Int
        ) -> UIEdgeInsets {
            controller?.inset(for: section) ?? .zero
        }
    }
}

// MARK: - Controller

@MainActor
final class TranscriptCollectionController: UIViewController {
    /// Сверху история, снизу новые сообщения. Секции не переворачиваются.
    static let olderSection = 0
    static let rowsSection = 1
    static let newerSection = 2

    enum HeaderKind: Equatable {
        case none
        case hint(String)
        case channelReady
        case empty
        case olderLoader(loading: Bool)
    }

    private(set) var collectionView: UICollectionView!
    weak var coordinator: TranscriptCollectionFeed.Coordinator?
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
    /// Хронологический порядок (старое → новое), как в ViewModel.
    private var rows: [TranscriptRow] = []
    private var header: HeaderKind = .none
    private var footerLoading = false
    private var feedInset: CGFloat = 8
    private weak var heightCache: BubbleHeightCache?
    private var measuredChrome: [String: CGFloat] = [:]
    private var lastLayoutWidth: CGFloat = 0
    private var lastBoundsHeight: CGFloat = 0
    private var pendingBottomPin = false
    /// Смещение, которое UIKit иногда сбрасывает в том же ходе раскладки.
    private var holdOffset: CGFloat?
    private var pendingSettle: PendingSettle?
    private var userScrolling = false
    private var deferredHeights: MeasuredLayoutCommit.Batch?
    private var pendingRemeasure: Set<String> = []
    private lazy var commit = MeasuredLayoutCommit { [weak self] batch in
        self?.applyMeasured(batch)
    }

    /// Идентификаторы уникальны на весь снимок. Пустая секция не получает вторую заглушку:
    /// один и тот же item в двух секциях роняет diffable data source.
    enum Item: Hashable {
        case row(String)
        case olderHint(String)
        case olderChannel
        case olderEmpty
        case olderLoader
        case newer
    }

    private struct PendingSettle {
        var anchor: FeedScroll.Anchor?
        var reveal: FeedScroll.Reveal?
        var stick: Bool
        var beforeOffset: CGFloat
        var beforeHeight: CGFloat
    }

    /// Низ шапки и верх поля ввода в глобальных координатах. `nil` — ещё не измерены.
    private var headerBottom: CGFloat?
    private var composerTop: CGFloat?
    /// Палец уже сдвигал ленту: смещение 0 после этого — настоящее место, а не сброс UIKit.
    private var userDidScroll = false
    /// Открытие или новое сообщение держит низ, пока палец не забрал ленту.
    private var followsBottom = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        view.insetsLayoutMarginsFromSafeArea = false
        let flow = UICollectionViewFlowLayout()
        flow.scrollDirection = .vertical
        flow.minimumInteritemSpacing = 0
        flow.minimumLineSpacing = 0
        // Явная высота каждой строки. `.estimated` / self-sizing берёт один размер на секцию.
        flow.estimatedItemSize = .zero
        let collection = UICollectionView(frame: view.bounds, collectionViewLayout: flow)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        FeedScroll.install(collection)
        collection.delegate = coordinator
        view.addSubview(collection)
        collectionView = collection
        configureDataSource()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let collectionView else { return }
        let interacting = FeedScroll.isInteracting(collectionView)
        let nearBottom = FeedScroll.isNearBottom(collectionView)
        let heightChanged = lastBoundsHeight > 0 && abs(view.bounds.height - lastBoundsHeight) > 0.5
        lastBoundsHeight = view.bounds.height
        collectionView.frame = view.bounds
        if resetHeightsForWidth(view.bounds.width) {
            collectionView.collectionViewLayout.invalidateLayout()
        }
        let insetChanged = !interacting && FeedScroll.applyChrome(
            collectionView,
            headerBottom: headerBottom,
            composerTop: composerTop
        )
        if insetChanged { holdOffset = nil }
        if let pending = pendingSettle, collectionView.bounds.height > 1 {
            pendingSettle = nil
            if interacting {
                pendingBottomPin = false
            } else {
                applySettle(
                    pending.anchor,
                    reveal: pending.reveal,
                    stick: pending.stick,
                    beforeOffset: pending.beforeOffset,
                    beforeHeight: pending.beforeHeight,
                    interacting: false
                )
            }
        }
        var held = false
        if let hold = holdOffset {
            holdOffset = nil
            held = true
            if !interacting, abs(collectionView.contentOffset.y - hold) > 0.5 {
                collectionView.contentOffset.y = hold
            }
        }
        guard !interacting else { return }
        let zeroed = !userDidScroll && abs(collectionView.contentOffset.y) < 1 && collectionView.contentInset.top > 1
        let shouldPin = (!held && (nearBottom || pendingBottomPin) && (heightChanged || insetChanged || pendingBottomPin))
            || (zeroed && (followsBottom || pendingBottomPin))
        if shouldPin {
            FeedScroll.pinToBottom(collectionView)
            pendingBottomPin = false
        } else if zeroed, !held {
            collectionView.contentOffset.y = -collectionView.contentInset.top
        }
    }

    func releaseBottomPin() {
        userDidScroll = true
        followsBottom = false
        pendingBottomPin = false
        pendingSettle = nil
        holdOffset = nil
    }

    func setChrome(headerBottom: CGFloat?, composerTop: CGFloat?) {
        guard self.headerBottom != headerBottom || self.composerTop != composerTop else { return }
        self.headerBottom = headerBottom
        self.composerTop = composerTop
        guard let collectionView, collectionView.bounds.height > 1,
              !FeedScroll.isInteracting(collectionView) else { return }
        let near = FeedScroll.isNearBottom(collectionView) || pendingBottomPin
        if FeedScroll.applyChrome(
            collectionView,
            headerBottom: headerBottom,
            composerTop: composerTop
        ), near {
            FeedScroll.pinToBottom(collectionView)
            pendingBottomPin = false
        }
    }

    func setUserScrolling(_ scrolling: Bool) {
        let was = userScrolling
        userScrolling = scrolling
        if scrolling {
            userDidScroll = true
            followsBottom = false
        }
        guard was, !scrolling else { return }
        flushDeferredHeights()
        guard let collectionView, !FeedScroll.isInteracting(collectionView) else { return }
        let near = FeedScroll.isNearBottom(collectionView) || pendingBottomPin
        if FeedScroll.applyChrome(
            collectionView,
            headerBottom: headerBottom,
            composerTop: composerTop
        ), near {
            FeedScroll.pinToBottom(collectionView)
            pendingBottomPin = false
        }
    }

    func deferRemeasure(_ id: String) {
        pendingRemeasure.insert(id)
    }

    override func viewSafeAreaInsetsDidChange() {
        let wasNear = collectionView.map { FeedScroll.isNearBottom($0) } ?? false
        let interacting = collectionView.map { FeedScroll.isInteracting($0) } ?? false
        super.viewSafeAreaInsetsDidChange()
        guard let collectionView, collectionView.bounds.height > 1, !interacting else { return }
        let changed = FeedScroll.applyChrome(
            collectionView,
            headerBottom: headerBottom,
            composerTop: composerTop
        )
        if changed, wasNear || pendingBottomPin {
            FeedScroll.pinToBottom(collectionView)
            pendingBottomPin = false
        }
    }

    func setRows(
        _ rows: [TranscriptRow],
        feedInset: CGFloat,
        heightCache: BubbleHeightCache,
        header: HeaderKind,
        footerLoading: Bool,
        stickToBottom: Bool,
        reveal: FeedScroll.Reveal?
    ) {
        var seen = Set<String>()
        let unique = rows.filter { seen.insert($0.id).inserted }
        if self.rows == unique, self.header == header, self.footerLoading == footerLoading, abs(self.feedInset - feedInset) < 0.5 {
            // Первый кадр ещё без размера: цель открытия могла уточниться, снимок тот же.
            if pendingSettle != nil {
                pendingSettle?.reveal = reveal
                pendingSettle?.stick = stickToBottom
                pendingBottomPin = stickToBottom || reveal?.latest == true
            }
            if !userDidScroll { followsBottom = stickToBottom || reveal?.latest == true }
            return
        }
        let collection = collectionView
        let interacting = collection.map { FeedScroll.isInteracting($0) } ?? false
        let anchor = collection.flatMap { view in
            FeedScroll.captureAnchor(view) { path in
                guard path.section == Self.rowsSection, self.rows.indices.contains(path.item) else { return nil }
                return self.rows[path.item].id
            }
        }
        let beforeHeight = collection?.contentSize.height ?? 0
        let beforeOffset = collection?.contentOffset.y ?? 0
        if !userDidScroll { followsBottom = stickToBottom || reveal?.latest == true }
        let previous = Dictionary(uniqueKeysWithValues: self.rows.map { ($0.id, $0) })
        let previousHeader = self.header
        let previousFooter = self.footerLoading
        for row in unique where previous[row.id] != row {
            heightCache.remove(id: row.id)
        }
        self.rows = unique
        self.feedInset = feedInset
        self.heightCache = heightCache
        self.header = header
        self.footerLoading = footerLoading
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([Self.olderSection, Self.rowsSection, Self.newerSection])
        if let older = olderItem(for: header) {
            snapshot.appendItems([older], toSection: Self.olderSection)
        }
        snapshot.appendItems(unique.map { .row($0.id) }, toSection: Self.rowsSection)
        if footerLoading {
            snapshot.appendItems([.newer], toSection: Self.newerSection)
        }
        FeedScroll.performWithoutAnimation {
            self.dataSource.apply(snapshot, animatingDifferences: false)
            if previousHeader != header || previousFooter != footerLoading {
                var refresh = self.dataSource.snapshot()
                let chrome = refresh.itemIdentifiers.filter {
                    if case .row = $0 { return false }
                    return true
                }
                if !chrome.isEmpty {
                    refresh.reconfigureItems(chrome)
                    self.dataSource.apply(refresh, animatingDifferences: false)
                }
            }
            guard let collection else { return }
            guard collection.bounds.height > 1 else {
                self.pendingSettle = PendingSettle(
                    anchor: anchor,
                    reveal: reveal,
                    stick: stickToBottom,
                    beforeOffset: beforeOffset,
                    beforeHeight: beforeHeight
                )
                self.pendingBottomPin = stickToBottom || reveal?.latest == true
                return
            }
            collection.collectionViewLayout.invalidateLayout()
            collection.layoutIfNeeded()
            self.applySettle(
                anchor,
                reveal: reveal,
                stick: stickToBottom,
                beforeOffset: beforeOffset,
                beforeHeight: beforeHeight,
                interacting: interacting
            )
        }
    }

    private func applySettle(
        _ anchor: FeedScroll.Anchor?,
        reveal: FeedScroll.Reveal?,
        stick: Bool,
        beforeOffset: CGFloat,
        beforeHeight: CGFloat,
        interacting: Bool
    ) {
        guard let collection = collectionView else { return }
        let settled = FeedScroll.settle(
            collection,
            anchor: anchor,
            reveal: reveal,
            stickToBottom: stick,
            interacting: interacting,
            headerBottom: headerBottom,
            composerTop: composerTop,
            rowFrame: { [weak self] id in self?.frame(for: id) }
        )
        if !settled, let fallback = FeedScroll.fallbackOffset(collection, beforeOffset: beforeOffset, beforeHeight: beforeHeight) {
            collection.contentOffset.y = fallback
        }
        if !interacting {
            holdOffset = collection.contentOffset.y
        }
        pendingBottomPin = false
    }

    private func olderItem(for header: HeaderKind) -> Item? {
        switch header {
        case .none: return nil
        case .hint(let text): return .olderHint(text)
        case .channelReady: return .olderChannel
        case .empty: return .olderEmpty
        case .olderLoader: return .olderLoader
        }
    }

    func displayIndex(for id: String) -> Int? {
        rows.firstIndex(where: { $0.id == id })
    }

    func chronologicalIndex(display: Int) -> Int? {
        rows.indices.contains(display) ? display : nil
    }

    func row(atDisplayIndex display: Int) -> TranscriptRow? {
        guard rows.indices.contains(display) else { return nil }
        return rows[display]
    }

    func frame(for id: String) -> CGRect? {
        guard let collectionView, let index = displayIndex(for: id) else { return nil }
        return collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: Self.rowsSection))?.frame
    }

    var isOlderChromeVisibleOnScreen: Bool {
        guard case .olderLoader = header, let collectionView,
              let indexPath = dataSource.indexPath(for: .olderLoader),
              let viewport = FeedScroll.windowFrame(collectionView) else { return false }
        let frame: CGRect
        if let cell = collectionView.cellForItem(at: indexPath) {
            frame = cell.convert(cell.bounds, to: nil)
        } else if let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
            frame = collectionView.convert(attributes.frame, to: nil)
        } else {
            return false
        }
        let readableTop = viewport.minY + collectionView.adjustedContentInset.top
        return frame.intersects(CGRect(x: viewport.minX, y: readableTop, width: viewport.width, height: 120))
    }

    func scrollTo(
        id: String,
        anchor: Double,
        latest: Bool,
        stillCurrent: @escaping () -> Bool
    ) async -> Bool {
        guard let collectionView, displayIndex(for: id) != nil else { return false }
        let reveal = FeedScroll.Reveal(id: id, anchor: anchor, latest: latest)
        FeedScroll.performWithoutAnimation {
            collectionView.layoutIfNeeded()
            _ = FeedScroll.settle(
                collectionView,
                anchor: nil,
                reveal: reveal,
                stickToBottom: latest,
                interacting: FeedScroll.isInteracting(collectionView),
                headerBottom: headerBottom,
                composerTop: composerTop,
                rowFrame: { [weak self] rowID in self?.frame(for: rowID) }
            )
        }
        let indexPath = IndexPath(item: displayIndex(for: id) ?? 0, section: Self.rowsSection)
        var settled = 0
        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(60))
            guard stillCurrent() else { return false }
            if FeedScroll.isInteracting(collectionView) { return false }
            guard let cell = collectionView.cellForItem(at: indexPath) else {
                FeedScroll.performWithoutAnimation {
                    _ = FeedScroll.settle(
                        collectionView,
                        anchor: nil,
                        reveal: reveal,
                        stickToBottom: latest,
                        interacting: false,
                        headerBottom: headerBottom,
                        composerTop: composerTop,
                        rowFrame: { [weak self] rowID in self?.frame(for: rowID) }
                    )
                }
                continue
            }
            let row = cell.convert(cell.bounds, to: nil)
            guard let viewport = FeedScroll.windowFrame(collectionView) else { continue }
            let inset = collectionView.adjustedContentInset
            let reached = latest && id == rows.last?.id
                || TranscriptScrollController.reached(
                    anchor: anchor,
                    rowMin: Double(row.minY),
                    rowMax: Double(row.maxY),
                    viewportMin: Double(viewport.minY + inset.top),
                    viewportMax: Double(viewport.maxY - inset.bottom)
                )
            settled = reached ? settled + 1 : 0
            if settled >= 2 { return true }
            if !reached {
                FeedScroll.performWithoutAnimation {
                    _ = FeedScroll.settle(
                        collectionView,
                        anchor: nil,
                        reveal: reveal,
                        stickToBottom: latest,
                        interacting: false,
                        headerBottom: headerBottom,
                        composerTop: composerTop,
                        rowFrame: { [weak self] rowID in self?.frame(for: rowID) }
                    )
                }
            }
        }
        return false
    }

    func inset(for section: Int) -> UIEdgeInsets {
        guard section == Self.rowsSection else { return .zero }
        return UIEdgeInsets(top: 8, left: feedInset, bottom: 0, right: feedInset)
    }

    func sizeForItem(at indexPath: IndexPath, containerWidth: CGFloat) -> CGSize {
        let width = max(1, containerWidth)
        let insets = inset(for: indexPath.section)
        let itemWidth = max(1, width - insets.left - insets.right)
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            return CGSize(width: itemWidth, height: 44)
        }
        let height: CGFloat
        switch item {
        case .newer:
            height = measuredChrome["newer"] ?? 40
        case .olderLoader:
            height = measuredChrome["older-loader"] ?? 44
        case .olderHint, .olderChannel, .olderEmpty:
            height = olderChromeKey.flatMap { measuredChrome[$0] } ?? 220
        case .row:
            let maxWidth = Double(min(520, itemWidth * MaxlyTheme.bubbleMax))
            let resolved = CollectionFeedLayout.height(
                index: indexPath.item,
                chronological: rows,
                maxWidth: maxWidth,
                cache: heightCache ?? BubbleHeightCache()
            )
            height = max(1, CGFloat(resolved ?? 72))
        }
        return CGSize(width: itemWidth, height: max(1, height))
    }

    private var olderChromeKey: String? {
        switch header {
        case .none: return nil
        case .olderLoader: return "older-loader"
        case .hint: return "older-hint"
        case .channelReady: return "older-channel"
        case .empty: return "older-empty"
        }
    }

    private func indexPath(forChromeKey key: String) -> IndexPath? {
        switch key {
        case "newer":
            return dataSource.indexPath(for: .newer)
        case "older-loader":
            return dataSource.indexPath(for: .olderLoader)
        case "older-channel":
            return dataSource.indexPath(for: .olderChannel)
        case "older-empty":
            return dataSource.indexPath(for: .olderEmpty)
        case "older-hint":
            if case .hint(let text) = header { return dataSource.indexPath(for: .olderHint(text)) }
            return nil
        default:
            return nil
        }
    }

    private func resetHeightsForWidth(_ width: CGFloat) -> Bool {
        guard lastLayoutWidth > 0, abs(width - lastLayoutWidth) > 0.5 else {
            if lastLayoutWidth == 0 { lastLayoutWidth = width }
            return false
        }
        lastLayoutWidth = width
        coordinator?.cancelPrewarm()
        heightCache?.removeAll()
        measuredChrome.removeAll()
        collectionView?.visibleCells.compactMap { $0 as? MeasuredHostingCell }.forEach { $0.resetMeasurement() }
        return true
    }

    private func applyMeasured(_ batch: MeasuredLayoutCommit.Batch) {
        guard let collectionView else { return }
        if userScrolling || FeedScroll.isInteracting(collectionView) {
            var rows = deferredHeights?.rows ?? [:]
            var chrome = deferredHeights?.chrome ?? [:]
            rows.merge(batch.rows) { _, new in new }
            chrome.merge(batch.chrome) { _, new in new }
            deferredHeights = .init(rows: rows, chrome: chrome)
            return
        }
        let wasNearBottom = FeedScroll.isNearBottom(collectionView)
        let offset = collectionView.contentOffset.y
        var compensate: CGFloat = 0
        for (id, height) in batch.rows {
            let path = dataSource.indexPath(for: .row(id))
            let attrs = path.flatMap { collectionView.layoutAttributesForItem(at: $0) }
            compensate += FeedLayoutAdjust.compensateOffset(
                collectionView,
                attributes: attrs,
                newHeight: CGFloat(height),
                dragging: false
            )
            heightCache?.store(id: id, height: height)
        }
        for (key, height) in batch.chrome {
            let isNewer = footerLoading && key == "newer"
            let isOlder = olderChromeKey.map { $0 == key } ?? false
            guard isNewer || isOlder else { continue }
            let attrs = indexPath(forChromeKey: key).flatMap { collectionView.layoutAttributesForItem(at: $0) }
            compensate += FeedLayoutAdjust.compensateOffset(
                collectionView,
                attributes: attrs,
                newHeight: height,
                dragging: false
            )
            measuredChrome[key] = height
        }
        FeedScroll.performWithoutAnimation {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            if wasNearBottom {
                _ = FeedScroll.applyChrome(
                    collectionView,
                    headerBottom: headerBottom,
                    composerTop: composerTop
                )
                FeedScroll.pinToBottom(collectionView)
            } else if abs(compensate) >= 1 {
                collectionView.contentOffset.y = offset + compensate
            }
        }
    }

    private func flushDeferredHeights() {
        let ids = pendingRemeasure
        pendingRemeasure = []
        if let collectionView, !ids.isEmpty {
            for indexPath in collectionView.indexPathsForVisibleItems where indexPath.section == Self.rowsSection {
                guard let row = row(atDisplayIndex: indexPath.item), ids.contains(row.id),
                      let cell = collectionView.cellForItem(at: indexPath) as? MeasuredHostingCell else { continue }
                cell.resetMeasurement()
                cell.setNeedsLayout()
            }
        }
        guard let batch = deferredHeights else { return }
        deferredHeights = nil
        applyMeasured(batch)
    }

    private func configureDataSource() {
        let rowRegistration = UICollectionView.CellRegistration<MeasuredHostingCell, String> { [weak self] cell, _, id in
            guard let self, let row = self.rows.first(where: { $0.id == id }) else { return }
            cell.onMeasuredHeight = { [weak self] height in
                self?.commit.row(height, id: id, current: self?.heightCache?[id])
            }
            self.coordinator?.configure(cell, row: row)
        }
        let chromeRegistration = UICollectionView.CellRegistration<MeasuredHostingCell, Item> { [weak self] cell, _, item in
            guard let self else { return }
            let key = self.chromeKey(for: item)
            if let key {
                cell.onMeasuredHeight = { [weak self] height in
                    self?.commit.chrome(height, id: key, current: self?.measuredChrome[key])
                }
            } else {
                cell.onMeasuredHeight = nil
            }
            cell.contentConfiguration = UIHostingConfiguration {
                self.chromeView(for: item)
            }
            .margins(.all, 0)
            .minSize(width: 0, height: 0)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .row(let id):
                return collectionView.dequeueConfiguredReusableCell(using: rowRegistration, for: indexPath, item: id)
            case .newer, .olderHint, .olderChannel, .olderEmpty, .olderLoader:
                return collectionView.dequeueConfiguredReusableCell(using: chromeRegistration, for: indexPath, item: item)
            }
        }
    }

    private func chromeKey(for item: Item) -> String? {
        switch item {
        case .newer: return "newer"
        case .olderLoader: return "older-loader"
        case .olderHint: return "older-hint"
        case .olderChannel: return "older-channel"
        case .olderEmpty: return "older-empty"
        case .row: return nil
        }
    }

    @ViewBuilder
    private func chromeView(for item: Item) -> some View {
        switch item {
        case .row:
            EmptyView()
        case .newer:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .onAppear { self.coordinator?.parent.onLoadNewer() }
        case .olderHint(let text):
            VStack(spacing: 12) {
                MaxlyMark(size: 56).foregroundStyle(.tertiary)
                Text(text)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 80)
        case .olderChannel:
            VStack(spacing: 10) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.maxlyAccent, in: Circle())
                Text("Канал готов").font(.app(.headline))
                Text("Добавляйте посты и приглашайте подписчиков")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 32)
            .padding(.top, 80)
        case .olderEmpty:
            Text("Здесь пока нет сообщений")
                .foregroundStyle(.secondary)
                .padding(24)
        case .olderLoader:
            olderLoader
        }
    }

    @ViewBuilder
    private var olderLoader: some View {
        let loading: Bool = {
            if case .olderLoader(let value) = header { return value }
            return false
        }()
        ZStack {
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Button("Загрузить предыдущие сообщения") {
                    self.coordinator?.parent.onLoadOlder()
                }
                .font(.app(.caption))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }
}
