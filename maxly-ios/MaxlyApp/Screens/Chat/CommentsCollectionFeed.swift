import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Комментарии на том же движке, что и чат: старое сверху, новое снизу.
struct CommentsCollectionFeed: UIViewControllerRepresentable {
    @Bindable var model: CommentsViewModel
    let width: CGFloat
    let reveal: PrivateModeReveal
    let reduceMotion: Bool
    let atBottom: Binding<Bool>
    /// Верх поля ввода в глобальных координатах. `nil` — ещё не измерен, лента берёт safe area окна.
    let composerTop: CGFloat?
    var onBlockAuthor: ((Message) async throws -> Void)?
    var onBlockNotice: (String) -> Void

    func makeUIViewController(context: Context) -> CommentsCollectionController {
        let controller = CommentsCollectionController()
        context.coordinator.controller = controller
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: CommentsCollectionController, context: Context) {
        context.coordinator.parent = self
        controller.coordinator = context.coordinator
        context.coordinator.apply(self)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
        var parent: CommentsCollectionFeed
        weak var controller: CommentsCollectionController?
        private var heightCache = BubbleHeightCache()
        private var prewarmKey = ""
        private var shownRows: [String: TranscriptRow] = [:]
        private var shownPost: Message?
        private var lastOffsetY: CGFloat = 0
        private var scrollingTowardOlder = false
        private var lastPrefetchKey = ""
        private let prewarmEpoch = PrewarmEpoch()

        init(_ parent: CommentsCollectionFeed) { self.parent = parent }

        func cancelPrewarm() {
            prewarmKey = ""
            _ = prewarmEpoch.next()
        }

        func apply(_ feed: CommentsCollectionFeed) {
            guard let controller else { return }
            controller.loadViewIfNeeded()
            controller.collectionView?.delegate = self
            controller.collectionView?.prefetchDataSource = self
            controller.setChrome(headerBottom: nil, composerTop: feed.composerTop)
            var seen = Set<String>()
            let rows = TranscriptLayout.rows(feed.model.comments, currentUserId: feed.model.currentUserId)
                .filter { seen.insert($0.id).inserted }
            prewarm(rows, width: feed.width)
            let changed = controller.setContent(
                post: feed.model.post,
                rows: rows,
                state: feed.model.state,
                hasMore: feed.model.hasMore,
                isLoadingOlder: feed.model.isLoadingOlder,
                emptyText: feed.model.emptyText,
                width: feed.width,
                heightCache: heightCache,
                stickToBottom: feed.atBottom.wrappedValue
            )
            syncVisibleCells(rows: rows, post: feed.model.post)
            if changed {
                loadOlderIfLoaderVisible()
            }
            schedulePrefetch(rows: rows, force: true)
        }

        func loadOlderIfLoaderVisible() {
            guard controller?.isOlderLoaderVisible == true else { return }
            Task { await parent.model.loadOlder() }
        }

        private func prewarm(_ rows: [TranscriptRow], width: CGFloat) {
            let key = "\(Int(width.rounded())):\(rows.count):\(rows.first?.id ?? ""):\(rows.last?.id ?? "")"
            guard key != prewarmKey else { return }
            prewarmKey = key
            let maxWidth = Double(width * MaxlyTheme.bubbleMax)
            let cache = heightCache
            let epoch = prewarmEpoch
            let ticket = epoch.next()
            Task.detached(priority: .utility) {
                for row in rows {
                    if !epoch.matches(ticket) { return }
                    cache.storeIfAbsent(id: row.id, height: BubbleHeightCache.estimate(row: row, maxWidth: maxWidth))
                }
            }
        }

        private func syncVisibleCells(rows: [TranscriptRow], post: Message) {
            guard let controller, let collection = controller.collectionView else { return }
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            shownRows = shownRows.filter { byID[$0.key] != nil }
            let interacting = FeedScroll.isInteracting(collection)
            for indexPath in collection.indexPathsForVisibleItems where indexPath.section == CommentsCollectionController.rowsSection {
                guard let item = controller.item(at: indexPath), case .row(let id) = item,
                      let row = byID[id], let cell = collection.cellForItem(at: indexPath) else { continue }
                guard shownRows[id] != row else { continue }
                let hadShown = shownRows[id] != nil
                shownRows[id] = row
                // Палец держит место: содержимое обновляем, перемер — после отпускания.
                if interacting, hadShown {
                    controller.deferRemeasure(id)
                    configure(cell, row: row)
                    continue
                }
                if let measured = cell as? MeasuredHostingCell {
                    measured.resetMeasurement()
                    measured.setNeedsLayout()
                }
                configure(cell, row: row)
            }
            if shownPost != post {
                shownPost = post
                controller.reconfigurePost()
            }
        }

        func configure(_ cell: UICollectionViewCell, row: TranscriptRow) {
            let model = parent.model
            let reveal = parent.reveal
            let reduceMotion = parent.reduceMotion
            let width = parent.width
            let onBlock = parent.onBlockAuthor
            let onNotice = parent.onBlockNotice
            let outgoing = row.isOutgoing
            let report: (CGFloat) -> Void = { [weak cell] height in
                (cell as? MeasuredHostingCell)?.onMeasuredHeight?(height)
            }
            if let measured = cell as? MeasuredHostingCell {
                measured.usesIntrinsicHeight = true
            }
            cell.contentConfiguration = UIHostingConfiguration {
                CommentsCollectionCell(
                    row: row,
                    model: model,
                    reveal: reveal,
                    reduceMotion: reduceMotion,
                    width: width,
                    onBlockAuthor: onBlock,
                    onBlockNotice: onNotice
                )
                .fixedSize(horizontal: false, vertical: true)
                .background(FeedContentHeightReader(onHeight: report))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.maxlyComposerFlight(outgoing: outgoing, reduceMotion: reduceMotion))
            }
            .margins(.all, 0)
            .minSize(width: 0, height: 0)
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            guard controller?.isOlderLoader(indexPath) == true, controller?.acceptsOlderLoad == true else { return }
            Task { await parent.model.loadOlder() }
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            guard let rows = controller?.currentRows else { return }
            schedulePrefetch(rows: rows, force: false)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            controller?.releaseBottomPin()
            controller?.setUserScrolling(true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { controller?.setUserScrolling(false) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            controller?.setUserScrolling(false)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            if abs(y - lastOffsetY) > 1 {
                scrollingTowardOlder = y < lastOffsetY
                lastOffsetY = y
            }
            updateAtBottom(scrollView)
            if let controller,
               let rows = controller.currentRows {
                schedulePrefetch(rows: rows, force: false)
            }
        }

        private func updateAtBottom(_ scrollView: UIScrollView) {
            let distance = FeedScroll.distanceFromBottom(scrollView)
            let next = distance < (parent.atBottom.wrappedValue ? 64 : 24)
            if next != parent.atBottom.wrappedValue {
                parent.atBottom.wrappedValue = next
            }
        }

        private func visibleRowRange() -> Range<Int>? {
            guard let collection = controller?.collectionView else { return nil }
            let items = collection.indexPathsForVisibleItems
                .filter { $0.section == CommentsCollectionController.rowsSection }
                .map(\.item)
                .sorted()
            guard let first = items.first, let last = items.last else { return nil }
            return first..<(last + 1)
        }

        private func schedulePrefetch(rows: [TranscriptRow], force: Bool) {
            let messages = rows.map(\.message)
            let plan = TranscriptImagePrefetch.plan(
                messages: messages,
                visibleRange: visibleRowRange(),
                scrollingTowardOlder: scrollingTowardOlder
            )
            let key = plan.urls.map(\.absoluteString).joined(separator: "|")
            guard force || key != lastPrefetchKey, !plan.urls.isEmpty else { return }
            lastPrefetchKey = key
            Task {
                await ImagePipeline.shared.prefetchDecoded(
                    plan.urls.map { ($0, TranscriptImagePrefetch.maxPixel) }
                )
            }
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
            section == CommentsCollectionController.newerSection ? 0 : CGFloat(BubbleHeightCache.rowSpacing)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            insetForSectionAt section: Int
        ) -> UIEdgeInsets {
            // Нижняя секция пустая: её inset не должен добавлять щель под последним комментарием.
            guard section != CommentsCollectionController.newerSection else { return .zero }
            return CommentsCollectionController.sectionInset
        }
    }
}

// MARK: - Cell

private struct CommentsCollectionCell: View {
    let row: TranscriptRow
    let model: CommentsViewModel
    let reveal: PrivateModeReveal
    let reduceMotion: Bool
    let width: CGFloat
    var onBlockAuthor: ((Message) async throws -> Void)?
    var onBlockNotice: (String) -> Void

    var body: some View {
        let comment = row.message
        let outgoing = row.isOutgoing
        PrivateBubbleGate(
            isRevealed: reveal.isRevealed(comment.id),
            accessibilityText: PrivateModeMask.messageText(for: comment, outgoing: outgoing),
            onReveal: { withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { reveal.reveal(comment.id) } },
            real: {
                MessageBubble(
                    message: comment,
                    isOutgoing: outgoing,
                    maxWidth: width * MaxlyTheme.bubbleMax,
                    showsAuthorName: row.showsAuthorName,
                    showsAuthorAvatar: row.showsAuthorAvatar,
                    reservesAvatar: !outgoing,
                    group: row.group,
                    onRetry: { Task { await model.retry(comment.id) } },
                    onReact: { emoji in Task { await model.toggleReaction(commentId: comment.id, emoji: emoji) } },
                    allowsReactions: model.canReact(comment),
                    quickReactions: model.quickReactions(for: comment)
                )
                .contextMenu {
                    if comment.authorId != "0", let onBlockAuthor {
                        Button("Заблокировать автора", role: .destructive) {
                            Task {
                                do {
                                    try await onBlockAuthor(comment)
                                    onBlockNotice("Автор комментария заблокирован")
                                } catch let error as MaxlyError {
                                    onBlockNotice(error.userMessage ?? "Не удалось заблокировать")
                                } catch is CancellationError {
                                    return
                                } catch {
                                    onBlockNotice("Не удалось заблокировать")
                                }
                            }
                        }
                    }
                }
            },
            masked: {
                MessageBubble(
                    message: PrivateModeMask.message(comment, outgoing: outgoing),
                    isOutgoing: outgoing,
                    maxWidth: width * MaxlyTheme.bubbleMax,
                    showsAuthorAvatar: row.showsAuthorAvatar,
                    reservesAvatar: !outgoing,
                    group: row.group,
                    allowsReactions: false
                )
            }
        )
    }
}

// MARK: - Controller

@MainActor
final class CommentsCollectionController: UIViewController {
    static let olderSection = 0
    static let rowsSection = 1
    static let newerSection = 2

    private(set) var collectionView: UICollectionView!
    weak var coordinator: CommentsCollectionFeed.Coordinator?
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
    private(set) var currentRows: [TranscriptRow]?
    private var post: Message?
    private var state: CommentsViewModel.State = .loading
    private var hasMore = false
    private var isLoadingOlder = false
    private var emptyText: String?
    private var width: CGFloat = 0
    private weak var heightCache: BubbleHeightCache?
    private var measuredChrome: [String: CGFloat] = [:]
    private var lastLayoutWidth: CGFloat = 0
    private var lastBoundsHeight: CGFloat = 0
    private var pendingBottomPin = false
    /// Смещение, которое UIKit иногда сбрасывает в том же ходе раскладки.
    private var holdOffset: CGFloat?
    private var pendingSettle: PendingSettle?
    /// Пока снимок ещё не встал на якорь, верхний загрузчик не должен тянуть историю.
    private(set) var acceptsOlderLoad = false
    private var userScrolling = false
    private var deferredHeights: MeasuredLayoutCommit.Batch?
    private var pendingRemeasure: Set<String> = []
    private lazy var commit = MeasuredLayoutCommit { [weak self] batch in
        self?.applyMeasured(batch)
    }

    private struct PendingSettle {
        var anchor: FeedScroll.Anchor?
        var stick: Bool
        var beforeOffset: CGFloat
        var beforeHeight: CGFloat
    }

    /// Верх поля ввода. Шапка комментариев не измеряется отдельно: её даёт safe area окна.
    private var composerTop: CGFloat?
    /// Палец уже сдвигал ленту: смещение 0 после этого — настоящее место, а не сброс UIKit.
    private var userDidScroll = false
    /// Новые комментарии держат низ, пока палец не забрал ленту.
    private var followsBottom = false

    static var sectionInset: UIEdgeInsets {
        UIEdgeInsets(top: 4, left: MaxlyTheme.pad, bottom: 4, right: MaxlyTheme.pad)
    }

    /// Идентификаторы уникальны на весь снимок. Пустая нижняя секция не получает заглушку.
    enum Item: Hashable {
        case post
        case row(String)
        case older
        case status
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        view.insetsLayoutMarginsFromSafeArea = false
        let flow = UICollectionViewFlowLayout()
        flow.scrollDirection = .vertical
        flow.minimumInteritemSpacing = 0
        flow.minimumLineSpacing = 0
        // Явная высота каждой строки. `.estimated` берёт один размер на секцию.
        flow.estimatedItemSize = .zero
        let collection = UICollectionView(frame: view.bounds, collectionViewLayout: flow)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        FeedScroll.install(collection)
        collection.delegate = coordinator
        collection.prefetchDataSource = coordinator
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
            headerBottom: nil,
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
                    stick: pending.stick,
                    beforeOffset: pending.beforeOffset,
                    beforeHeight: pending.beforeHeight,
                    interacting: false
                )
            }
            acceptsOlderLoad = true
            if !interacting {
                coordinator?.loadOlderIfLoaderVisible()
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
        guard self.composerTop != composerTop else { return }
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
            headerBottom: nil,
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
            headerBottom: nil,
            composerTop: composerTop
        )
        if changed, wasNear || pendingBottomPin {
            FeedScroll.pinToBottom(collectionView)
            pendingBottomPin = false
        }
    }

    /// `true`, если состав ленты изменился и снимок применён.
    @discardableResult
    func setContent(
        post: Message,
        rows: [TranscriptRow],
        state: CommentsViewModel.State,
        hasMore: Bool,
        isLoadingOlder: Bool,
        emptyText: String?,
        width: CGFloat,
        heightCache: BubbleHeightCache,
        stickToBottom: Bool
    ) -> Bool {
        var seen = Set<String>()
        let unique = rows.filter { seen.insert($0.id).inserted }
        if currentRows == unique, self.post == post, self.state == state, self.hasMore == hasMore,
           self.isLoadingOlder == isLoadingOlder, self.emptyText == emptyText, abs(self.width - width) < 0.5 {
            if pendingSettle != nil {
                pendingSettle?.stick = stickToBottom
                pendingBottomPin = stickToBottom
            }
            if !userDidScroll { followsBottom = stickToBottom }
            return false
        }
        let collection = collectionView
        let interacting = collection.map { FeedScroll.isInteracting($0) } ?? false
        let previousRows = currentRows ?? []
        let anchor = collection.flatMap { view in
            FeedScroll.captureAnchor(view) { path in
                guard path.section == Self.rowsSection, previousRows.indices.contains(path.item) else { return nil }
                return previousRows[path.item].id
            }
        }
        let beforeHeight = collection?.contentSize.height ?? 0
        let beforeOffset = collection?.contentOffset.y ?? 0
        if !userDidScroll { followsBottom = stickToBottom }
        let previous = Dictionary(uniqueKeysWithValues: previousRows.map { ($0.id, $0) })
        let chromeChanged = self.post != post || self.state != state || self.hasMore != hasMore
            || self.isLoadingOlder != isLoadingOlder || self.emptyText != emptyText
        for row in unique where previous[row.id] != row {
            heightCache.remove(id: row.id)
        }
        if self.post != post {
            measuredChrome["post"] = nil
        }
        self.post = post
        self.currentRows = unique
        self.state = state
        self.hasMore = hasMore
        self.isLoadingOlder = isLoadingOlder
        self.emptyText = emptyText
        self.width = width
        self.heightCache = heightCache
        var rowItems: [Item]
        switch state {
        case .loading, .failed:
            rowItems = [.status]
        case .loaded:
            rowItems = unique.map { .row($0.id) }
            if emptyText != nil, unique.isEmpty {
                rowItems.append(.status)
            }
        }
        var older: [Item] = [.post]
        if hasMore { older.append(.older) }
        acceptsOlderLoad = false
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([Self.olderSection, Self.rowsSection, Self.newerSection])
        snapshot.appendItems(older, toSection: Self.olderSection)
        snapshot.appendItems(rowItems, toSection: Self.rowsSection)
        FeedScroll.performWithoutAnimation {
            self.dataSource.apply(snapshot, animatingDifferences: false)
            if chromeChanged {
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
                    stick: stickToBottom,
                    beforeOffset: beforeOffset,
                    beforeHeight: beforeHeight
                )
                self.pendingBottomPin = stickToBottom
                return
            }
            collection.collectionViewLayout.invalidateLayout()
            collection.layoutIfNeeded()
            self.applySettle(
                anchor,
                stick: stickToBottom,
                beforeOffset: beforeOffset,
                beforeHeight: beforeHeight,
                interacting: interacting
            )
        }
        if collectionView?.bounds.height ?? 0 > 1 {
            acceptsOlderLoad = true
        }
        return true
    }

    func isOlderLoader(_ indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) == .older
    }

    /// Загрузчик истории виден после якоря. Пост в той же секции сам по себе историю не тянет.
    var isOlderLoaderVisible: Bool {
        guard acceptsOlderLoad, hasMore, let collectionView,
              let indexPath = dataSource.indexPath(for: .older),
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return false }
        let visible = CGRect(
            x: collectionView.contentOffset.x,
            y: collectionView.contentOffset.y,
            width: collectionView.bounds.width,
            height: collectionView.bounds.height
        )
        return frame.intersects(visible)
    }

    func reconfigurePost() {
        guard let collectionView, let path = dataSource.indexPath(for: .post) else { return }
        if let cell = collectionView.cellForItem(at: path) as? MeasuredHostingCell {
            cell.resetMeasurement()
        }
        var snapshot = dataSource.snapshot()
        guard snapshot.itemIdentifiers.contains(.post) else { return }
        snapshot.reconfigureItems([.post])
        FeedScroll.performWithoutAnimation {
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    private func applySettle(
        _ anchor: FeedScroll.Anchor?,
        stick: Bool,
        beforeOffset: CGFloat,
        beforeHeight: CGFloat,
        interacting: Bool
    ) {
        guard let collection = collectionView else { return }
        let settled = FeedScroll.settle(
            collection,
            anchor: anchor,
            reveal: nil,
            stickToBottom: stick,
            interacting: interacting,
            headerBottom: nil,
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

    private func frame(for id: String) -> CGRect? {
        guard let collectionView, let index = currentRows?.firstIndex(where: { $0.id == id }) else { return nil }
        return collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: Self.rowsSection))?.frame
    }

    func sizeForItem(at indexPath: IndexPath, containerWidth: CGFloat) -> CGSize {
        let insets = Self.sectionInset
        let itemWidth = max(1, containerWidth - insets.left - insets.right)
        guard let item = item(at: indexPath) else {
            return CGSize(width: itemWidth, height: 44)
        }
        let height: CGFloat
        switch item {
        case .older:
            height = measuredChrome["older"] ?? 36
        case .status:
            height = measuredChrome["status"] ?? 96
        case .post:
            height = measuredChrome["post"] ?? estimatedPostHeight()
        case .row(let id):
            let chrono = currentRows ?? []
            let index = chrono.firstIndex(where: { $0.id == id }) ?? indexPath.item
            let resolved = CollectionFeedLayout.height(
                index: index,
                chronological: chrono,
                maxWidth: Double(width * MaxlyTheme.bubbleMax),
                cache: heightCache ?? BubbleHeightCache()
            )
            height = max(1, CGFloat(resolved ?? 72))
        }
        return CGSize(width: itemWidth, height: max(1, height))
    }

    func item(at indexPath: IndexPath) -> Item? {
        dataSource.itemIdentifier(for: indexPath)
    }

    private func chromeItem(forKey key: String) -> Item? {
        switch key {
        case "older": return .older
        case "post": return .post
        case "status": return .status
        default: return nil
        }
    }

    private func estimatedPostHeight() -> CGFloat {
        guard let post, let cache = heightCache,
              let row = TranscriptLayout.rows([post], currentUserId: "").first else { return 180 }
        // У одиночного поста есть разделитель дня — как «Начало обсуждения» в шапке.
        return CGFloat(cache.estimated(for: row, maxWidth: Double(width * MaxlyTheme.bubbleMax))) + 10
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
            guard let item = chromeItem(forKey: key), let path = dataSource.indexPath(for: item) else { continue }
            let attrs = collectionView.layoutAttributesForItem(at: path)
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
                    headerBottom: nil,
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
                guard case .row(let id) = item(at: indexPath), ids.contains(id),
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
            guard let self, let row = self.currentRows?.first(where: { $0.id == id }) else { return }
            cell.onMeasuredHeight = { [weak self] height in
                self?.commit.row(height, id: id, current: self?.heightCache?[id])
            }
            self.coordinator?.configure(cell, row: row)
        }
        let chromeRegistration = UICollectionView.CellRegistration<MeasuredHostingCell, Item> { [weak self] cell, _, item in
            guard let self else { return }
            let key: String?
            switch item {
            case .older: key = "older"
            case .post: key = "post"
            case .status: key = "status"
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
                self.chrome(item)
            }
            .margins(.all, 0)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .row(let id):
                return collectionView.dequeueConfiguredReusableCell(using: rowRegistration, for: indexPath, item: id)
            default:
                return collectionView.dequeueConfiguredReusableCell(using: chromeRegistration, for: indexPath, item: item)
            }
        }
    }

    @ViewBuilder
    private func chrome(_ item: Item) -> some View {
        switch item {
        case .post:
            if let post {
                let reveal = coordinator?.parent.reveal
                let reduceMotion = coordinator?.parent.reduceMotion ?? false
                VStack(spacing: 6) {
                    PrivateBubbleGate(
                        isRevealed: reveal?.isRevealed(post.id) ?? true,
                        accessibilityText: PrivateModeMask.messageText(for: post, outgoing: false),
                        onReveal: {
                            guard let reveal else { return }
                            withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { reveal.reveal(post.id) }
                        },
                        real: {
                            MessageBubble(
                                message: post,
                                isOutgoing: false,
                                maxWidth: width * MaxlyTheme.bubbleMax,
                                allowsReactions: false
                            )
                        },
                        masked: {
                            MessageBubble(
                                message: PrivateModeMask.message(post, outgoing: false),
                                isOutgoing: false,
                                maxWidth: width * MaxlyTheme.bubbleMax,
                                allowsReactions: false
                            )
                        }
                    )
                    DaySeparator("Начало обсуждения")
                }
                .padding(.bottom, 4)
            }
        case .older:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .opacity(isLoadingOlder ? 1 : 0.4)
        case .status:
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Повторить") { Task { await self.coordinator?.parent.model.reload() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            case .loaded:
                if let emptyText {
                    Text(emptyText)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
            }
        case .row:
            EmptyView()
        }
    }
}
