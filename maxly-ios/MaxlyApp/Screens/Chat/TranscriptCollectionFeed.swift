import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Лента на UICollectionView: старое сверху, новое снизу, у каждой строки своя высота.
struct TranscriptCollectionFeed: UIViewControllerRepresentable {
    @Bindable var viewModel: ChatViewModel
    let rows: [TranscriptRow]
    let width: CGFloat
    let reveal: PrivateModeReveal
    let feedInset: CGFloat
    let reduceMotion: Bool
    let animateInserts: Bool
    let isOpening: Bool
    let isRestoringHistory: Bool
    let scrollRequest: TranscriptScrollController.Request?
    let canLoadOlder: Bool
    let isLoadingOlder: Bool
    let isJumped: Bool
    let emptyHint: String?
    let showsChannelReady: Bool
    let showsEmpty: Bool

    var snapshot: (TranscriptRow) -> TranscriptBubble.Snapshot
    var onAuthor: (Message) -> Void
    var onFrames: (_ rows: [String: CGRect], _ viewport: CGRect, _ contentTop: CGFloat) -> Void
    var onBottomDistance: (Double, Double) -> Void
    var onUserScroll: (_ moving: Bool, _ takeover: Bool) -> Void
    var onTopVisible: (Bool) -> Void
    var onNearTopPrefix: (Int?) -> Void
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
        private var userDragging = false
        private var lastOffsetY: CGFloat = 0
        /// Палец / инерция к истории (визуальный верх = старое).
        private var scrollingTowardOlder = false
        private var lastPrefetchKey = ""
        private let prewarmEpoch = PrewarmEpoch()

        init(_ parent: TranscriptCollectionFeed) {
            self.parent = parent
        }

        func cancelPrewarm() { _ = prewarmEpoch.next() }

        func apply(_ feed: TranscriptCollectionFeed) {
            guard let controller else { return }
            controller.loadViewIfNeeded()
            controller.collectionView?.delegate = self
            controller.collectionView?.prefetchDataSource = self
            let animate = feed.animateInserts && !feed.isOpening && !feed.isRestoringHistory && !feed.reduceMotion
            prewarmHeights(feed.rows, width: feed.width, feedInset: feed.feedInset)
            controller.setRows(
                feed.rows,
                feedInset: feed.feedInset,
                heightCache: heightCache,
                animate: animate,
                header: headerKind(feed),
                footerLoading: feed.isJumped,
                preferBottom: feed.isOpening || feed.scrollRequest?.latest == true
            )
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
            let maxWidth = Double(min(520, max(0, width - feedInset * 2) * MaxlyTheme.bubbleMax))
            let cache = heightCache
            let epoch = prewarmEpoch
            let ticket = epoch.next()
            Task.detached(priority: .utility) {
                for row in rows {
                    if !epoch.matches(ticket) { return }
                    if cache[row.id] != nil { continue }
                    let height = BubbleHeightCache.estimate(row: row, maxWidth: maxWidth)
                    cache.store(id: row.id, height: height)
                }
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
            userDragging = true
            controller?.releaseBottomPin()
            parent.onUserScroll(true, true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                userDragging = false
                parent.onUserScroll(false, false)
                sampleGeometry(force: true)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            userDragging = false
            parent.onUserScroll(false, false)
            sampleGeometry(force: true)
        }

        func configure(_ cell: UICollectionViewCell, row: TranscriptRow) {
            let state = parent.snapshot(row)
            let reduceMotion = parent.reduceMotion
            let outgoing = row.isOutgoing
            cell.contentConfiguration = UIHostingConfiguration {
                TranscriptBubble(
                    state: state,
                    viewModel: parent.viewModel,
                    reveal: parent.reveal,
                    onAuthor: parent.onAuthor
                )
                .equatable()
                .transition(.maxlyComposerFlight(outgoing: outgoing, reduceMotion: reduceMotion))
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
            guard let controller, let collection = controller.collectionView else { return }
            let viewport = collection.convert(collection.bounds, to: nil)
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
                heightCache.store(id: row.id, height: Double(cell.bounds.height))
                chronoIndices.append(chrono)
            }
            parent.onFrames(frames, viewport, 0)
            parent.onNearTopPrefix(chronoIndices.min())
        }

        private func reportBottom(_ scrollView: UIScrollView) {
            guard let controller, let collection = controller.collectionView else { return }
            let viewport = collection.convert(collection.bounds, to: nil)
            if let last = parent.rows.last,
               let display = controller.displayIndex(for: last.id),
               let cell = collection.cellForItem(at: IndexPath(item: display, section: TranscriptCollectionController.rowsSection)) {
                let frame = cell.convert(cell.bounds, to: nil)
                let distance = max(0, Double(viewport.maxY - frame.maxY))
                parent.onBottomDistance(distance, Double(viewport.height))
                return
            }
            let distance = max(0, Double(FeedScroll.distanceFromBottom(scrollView)))
            parent.onBottomDistance(distance, Double(scrollView.bounds.height))
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
    /// Сверху история, снизу новые сообщения.
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
    private lazy var commit = MeasuredLayoutCommit { [weak self] batch in
        self?.applyMeasured(batch)
    }

    enum Item: Hashable {
        case newer
        case row(String)
        case older
        case chromeEmpty
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let flow = UICollectionViewFlowLayout()
        flow.scrollDirection = .vertical
        flow.minimumInteritemSpacing = 0
        flow.minimumLineSpacing = 0
        flow.estimatedItemSize = .zero
        let collection = UICollectionView(frame: view.bounds, collectionViewLayout: flow)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .interactive
        collection.contentInsetAdjustmentBehavior = .never
        collection.insetsLayoutMarginsFromSafeArea = false
        collection.delegate = coordinator
        view.addSubview(collection)
        collectionView = collection
        configureDataSource()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let collectionView else { return }
        let nearBottom = FeedScroll.isNearBottom(collectionView)
        let heightChanged = lastBoundsHeight > 0 && abs(view.bounds.height - lastBoundsHeight) > 0.5
        lastBoundsHeight = view.bounds.height
        collectionView.frame = view.bounds
        if resetHeightsForWidth(view.bounds.width) {
            collectionView.collectionViewLayout.invalidateLayout()
        }
        InvertedCollectionChrome.pinBottomIfNeeded(
            collectionView,
            nearBottom: nearBottom,
            heightChanged: heightChanged
        )
        if pendingBottomPin, collectionView.bounds.height > 1, collectionView.contentSize.height > 1 {
            FeedScroll.pinToBottom(collectionView)
            pendingBottomPin = false
        }
    }

    func releaseBottomPin() {
        pendingBottomPin = false
    }

    func setRows(
        _ rows: [TranscriptRow],
        feedInset: CGFloat,
        heightCache: BubbleHeightCache,
        animate: Bool,
        header: HeaderKind,
        footerLoading: Bool,
        preferBottom: Bool
    ) {
        let collection = collectionView
        let wasNearBottom = collection.map { FeedScroll.isNearBottom($0) } ?? false
        let beforeHeight = collection?.contentSize.height ?? 0
        let beforeOffset = collection?.contentOffset.y ?? 0
        let beforeFirst = self.rows.first?.id
        let hadRows = !self.rows.isEmpty
        self.rows = rows
        self.feedInset = feedInset
        self.heightCache = heightCache
        self.header = header
        self.footerLoading = footerLoading
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([Self.olderSection, Self.rowsSection, Self.newerSection])
        if header != .none {
            snapshot.appendItems([.older], toSection: Self.olderSection)
        } else {
            snapshot.appendItems([.chromeEmpty], toSection: Self.olderSection)
        }
        snapshot.appendItems(rows.map { .row($0.id) }, toSection: Self.rowsSection)
        if footerLoading {
            snapshot.appendItems([.newer], toSection: Self.newerSection)
        } else {
            snapshot.appendItems([.chromeEmpty], toSection: Self.newerSection)
        }
        dataSource.apply(snapshot, animatingDifferences: animate && hadRows)
        let shouldPin = wasNearBottom || (preferBottom && !hadRows)
        pendingBottomPin = shouldPin
        guard let collection, collection.bounds.height > 1 else { return }
        collection.collectionViewLayout.invalidateLayout()
        collection.layoutIfNeeded()
        let grew = collection.contentSize.height - beforeHeight
        let prepended = hadRows && rows.first?.id != beforeFirst
        if shouldPin {
            FeedScroll.pinToBottom(collection)
            pendingBottomPin = false
        } else if prepended, grew > 1 {
            collection.contentOffset.y = beforeOffset + grew
        }
    }

    func displayIndex(for id: String) -> Int? {
        rows.firstIndex(where: { $0.id == id })
    }

    func chronologicalIndex(display: Int) -> Int? {
        rows.indices.contains(display) ? display : nil
    }

    func row(atDisplayIndex display: Int) -> TranscriptRow? {
        guard let chrono = chronologicalIndex(display: display) else { return nil }
        return rows[chrono]
    }

    var isOlderChromeVisibleOnScreen: Bool {
        guard header != .none, case .olderLoader = header, let collectionView else { return false }
        let indexPath = IndexPath(item: 0, section: Self.olderSection)
        let frame: CGRect
        if let cell = collectionView.cellForItem(at: indexPath) {
            frame = cell.convert(cell.bounds, to: nil)
        } else if let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
            frame = collectionView.convert(attributes.frame, to: nil)
        } else {
            return false
        }
        let viewport = collectionView.convert(collectionView.bounds, to: nil)
        return frame.intersects(CGRect(x: viewport.minX, y: viewport.minY, width: viewport.width, height: 120))
    }

    func scrollTo(
        id: String,
        anchor: Double,
        latest: Bool,
        stillCurrent: @escaping () -> Bool
    ) async -> Bool {
        guard let collectionView, let display = displayIndex(for: id) else { return false }
        let indexPath = IndexPath(item: display, section: Self.rowsSection)
        let position: UICollectionView.ScrollPosition
        if latest || anchor >= 0.85 {
            position = .bottom
        } else if anchor <= 0.15 {
            position = .top
        } else {
            position = .centeredVertically
        }
        collectionView.scrollToItem(at: indexPath, at: position, animated: false)
        var settled = 0
        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(60))
            guard stillCurrent() else { return false }
            guard let cell = collectionView.cellForItem(at: indexPath) else { continue }
            let row = cell.convert(cell.bounds, to: nil)
            let viewport = collectionView.convert(collectionView.bounds, to: nil)
            let reached = latest && id == rows.last?.id
                || TranscriptScrollController.reached(
                    anchor: anchor,
                    rowMin: Double(row.minY),
                    rowMax: Double(row.maxY),
                    viewportMin: Double(viewport.minY),
                    viewportMax: Double(viewport.maxY)
                )
            settled = reached ? settled + 1 : 0
            if settled >= 2 { return true }
            if !reached {
                collectionView.scrollToItem(at: indexPath, at: position, animated: false)
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
        let height: CGFloat
        switch indexPath.section {
        case Self.newerSection:
            let key = footerLoading ? "newer" : nil
            height = key.flatMap { measuredChrome[$0] } ?? (footerLoading ? 40 : 1)
        case Self.olderSection:
            height = olderChromeKey.flatMap { measuredChrome[$0] } ?? olderChromeHeight
        default:
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

    private var olderChromeHeight: CGFloat {
        switch header {
        case .none: return 1
        case .olderLoader: return 32
        case .hint, .channelReady, .empty: return 220
        }
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
        if key == "newer" { return dataSource.indexPath(for: .newer) }
        if key.hasPrefix("older"), header != .none { return dataSource.indexPath(for: .older) }
        return nil
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
        let offset = collectionView.contentOffset.y
        let dragging = collectionView.isDragging || collectionView.isDecelerating
        var compensate: CGFloat = 0
        for (id, height) in batch.rows {
            let path = dataSource.indexPath(for: .row(id))
            let attrs = path.flatMap { collectionView.layoutAttributesForItem(at: $0) }
            compensate += InvertedCollectionChrome.compensateOffset(
                collectionView,
                attributes: attrs,
                newHeight: CGFloat(height),
                dragging: dragging
            )
            heightCache?.store(id: id, height: height)
        }
        for (key, height) in batch.chrome {
            let isNewer = footerLoading && key == "newer"
            let isOlder = olderChromeKey.map { $0 == key } ?? false
            guard isNewer || isOlder else { continue }
            let attrs = indexPath(forChromeKey: key).flatMap { collectionView.layoutAttributesForItem(at: $0) }
            compensate += InvertedCollectionChrome.compensateOffset(
                collectionView,
                attributes: attrs,
                newHeight: height,
                dragging: dragging
            )
            measuredChrome[key] = height
        }
        UIView.performWithoutAnimation {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            if abs(compensate) >= 1 {
                collectionView.contentOffset.y = offset + compensate
            }
        }
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
            let key: String?
            switch item {
            case .newer: key = "newer"
            case .older: key = self.olderChromeKey
            default: key = nil
            }
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
            case .newer, .older, .chromeEmpty:
                return collectionView.dequeueConfiguredReusableCell(using: chromeRegistration, for: indexPath, item: item)
            }
        }
    }

    @ViewBuilder
    private func chromeView(for item: Item) -> some View {
        switch item {
        case .chromeEmpty:
            Color.clear.frame(height: 1)
        case .newer:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .onAppear { self.coordinator?.parent.onLoadNewer() }
        case .older:
            switch header {
            case .none:
                Color.clear.frame(height: 1)
            case .hint(let text):
                VStack(spacing: 12) {
                    MaxlyMark(size: 56).foregroundStyle(.tertiary)
                    Text(text)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 80)
            case .channelReady:
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
            case .empty:
                Text("Здесь пока нет сообщений")
                    .foregroundStyle(.secondary)
                    .padding(24)
            case .olderLoader(let loading):
                ZStack {
                    if loading { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
        case .row:
            EmptyView()
        }
    }
}
