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
    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout {
        var parent: CommentsCollectionFeed
        weak var controller: CommentsCollectionController?
        private var heightCache = BubbleHeightCache()
        private var lastOffsetY: CGFloat = 0
        private var scrollingTowardOlder = false
        private var lastPrefetchKey = ""
        private let prewarmEpoch = PrewarmEpoch()

        init(_ parent: CommentsCollectionFeed) { self.parent = parent }

        func cancelPrewarm() { _ = prewarmEpoch.next() }

        func apply(_ feed: CommentsCollectionFeed) {
            guard let controller else { return }
            controller.loadViewIfNeeded()
            controller.collectionView?.delegate = self
            let rows = TranscriptLayout.rows(feed.model.comments, currentUserId: feed.model.currentUserId)
            prewarm(rows, width: feed.width)
            controller.setContent(
                post: feed.model.post,
                rows: rows,
                state: feed.model.state,
                hasMore: feed.model.hasMore,
                isLoadingOlder: feed.model.isLoadingOlder,
                emptyText: feed.model.emptyText,
                width: feed.width,
                heightCache: heightCache,
                animate: feed.atBottom.wrappedValue && feed.model.commentsChange.animatesTranscript,
                preferBottom: feed.atBottom.wrappedValue
            )
            schedulePrefetch(rows: rows, force: true)
        }

        private func prewarm(_ rows: [TranscriptRow], width: CGFloat) {
            let maxWidth = Double(width * MaxlyTheme.bubbleMax)
            let cache = heightCache
            let epoch = prewarmEpoch
            let ticket = epoch.next()
            Task.detached(priority: .utility) {
                for row in rows {
                    if !epoch.matches(ticket) { return }
                    if cache[row.id] != nil { continue }
                    cache.store(id: row.id, height: BubbleHeightCache.estimate(row: row, maxWidth: maxWidth))
                }
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
                .transition(.maxlyComposerFlight(outgoing: outgoing, reduceMotion: reduceMotion))
            }
            .margins(.all, 0)
            .minSize(width: 0, height: 0)
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            if indexPath.section == CommentsCollectionController.olderSection {
                Task { await parent.model.loadOlder() }
            }
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

        private func schedulePrefetch(rows: [TranscriptRow], force: Bool) {
            let messages = rows.map(\.message)
            let plan = TranscriptImagePrefetch.plan(
                messages: messages,
                visibleRange: nil,
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
            CommentsCollectionController.sectionInset
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
    private var sectionItems: [Int: [Item]] = [:]
    private var measuredChrome: [String: CGFloat] = [:]
    private var lastLayoutWidth: CGFloat = 0
    private var lastBoundsHeight: CGFloat = 0
    private var pendingBottomPin = false
    private lazy var commit = MeasuredLayoutCommit { [weak self] batch in
        self?.applyMeasured(batch)
    }

    static var sectionInset: UIEdgeInsets {
        UIEdgeInsets(top: 4, left: MaxlyTheme.pad, bottom: 4, right: MaxlyTheme.pad)
    }

    enum Item: Hashable {
        case post
        case row(String)
        case older
        case status
        case spacer
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
        FeedScroll.install(collection)
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

    private var userScrolling = false
    private var deferredHeights: MeasuredLayoutCommit.Batch?

    func setUserScrolling(_ scrolling: Bool) {
        let was = userScrolling
        userScrolling = scrolling
        if was, !scrolling { flushDeferredHeights() }
    }

    override func viewSafeAreaInsetsDidChange() {
        let wasNear = collectionView.map { FeedScroll.isNearBottom($0) } ?? false
        let dragging = collectionView?.isDragging == true || collectionView?.isDecelerating == true
        super.viewSafeAreaInsetsDidChange()
        guard let collectionView, (wasNear || pendingBottomPin), !dragging else { return }
        FeedScroll.pinToBottom(collectionView)
    }

    func setContent(
        post: Message,
        rows: [TranscriptRow],
        state: CommentsViewModel.State,
        hasMore: Bool,
        isLoadingOlder: Bool,
        emptyText: String?,
        width: CGFloat,
        heightCache: BubbleHeightCache,
        animate: Bool,
        preferBottom: Bool
    ) {
        if currentRows == rows, self.post == post, self.state == state, self.hasMore == hasMore,
           self.isLoadingOlder == isLoadingOlder, self.emptyText == emptyText, abs(self.width - width) < 0.5 {
            return
        }
        let collection = collectionView
        let wasNearBottom = collection.map { FeedScroll.isNearBottom($0) } ?? preferBottom
        let beforeHeight = collection?.contentSize.height ?? 0
        let beforeOffset = collection?.contentOffset.y ?? 0
        let beforeFirst = currentRows?.first?.id
        let hadRows = !(currentRows ?? []).isEmpty
        self.post = post
        self.currentRows = rows
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
            rowItems = rows.map { .row($0.id) }
            if let emptyText, rows.isEmpty {
                rowItems.append(.status)
            }
        }
        var older: [Item] = [.post]
        if hasMore { older.append(.older) }
        sectionItems = [
            Self.olderSection: older,
            Self.rowsSection: rowItems,
            Self.newerSection: [.spacer],
        ]
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([Self.olderSection, Self.rowsSection, Self.newerSection])
        snapshot.appendItems(older, toSection: Self.olderSection)
        snapshot.appendItems(rowItems, toSection: Self.rowsSection)
        snapshot.appendItems([.spacer], toSection: Self.newerSection)
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

    func sizeForItem(at indexPath: IndexPath, containerWidth: CGFloat) -> CGSize {
        let insets = Self.sectionInset
        let itemWidth = max(1, containerWidth - insets.left - insets.right)
        guard let item = item(at: indexPath) else {
            return CGSize(width: itemWidth, height: 44)
        }
        let height: CGFloat
        switch item {
        case .spacer:
            height = 1
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

    private func item(at indexPath: IndexPath) -> Item? {
        guard let items = sectionItems[indexPath.section], items.indices.contains(indexPath.item) else { return nil }
        return items[indexPath.item]
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
        if userScrolling || collectionView.isDragging || collectionView.isDecelerating {
            var rows = deferredHeights?.rows ?? [:]
            var chrome = deferredHeights?.chrome ?? [:]
            rows.merge(batch.rows) { _, new in new }
            chrome.merge(batch.chrome) { _, new in new }
            deferredHeights = .init(rows: rows, chrome: chrome)
            return
        }
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
            guard let item = chromeItem(forKey: key), let path = dataSource.indexPath(for: item) else { continue }
            let attrs = collectionView.layoutAttributesForItem(at: path)
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

    private func flushDeferredHeights() {
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
        case .spacer:
            Color.clear.frame(height: 1)
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
