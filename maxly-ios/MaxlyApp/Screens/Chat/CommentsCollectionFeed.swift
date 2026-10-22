import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Комментарии на том же движке, что и чат: UICollectionView + invert + кэш высот.
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
    final class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: CommentsCollectionFeed
        weak var controller: CommentsCollectionController?
        private var heightCache = BubbleHeightCache()
        private var lastOffsetY: CGFloat = 0
        private var scrollingTowardOlder = false
        private var lastPrefetchKey = ""

        init(_ parent: CommentsCollectionFeed) { self.parent = parent }

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
                animate: feed.atBottom.wrappedValue && feed.model.commentsChange.animatesTranscript
            )
            schedulePrefetch(rows: rows, force: true)
        }

        private func prewarm(_ rows: [TranscriptRow], width: CGFloat) {
            let maxWidth = Double(width * MaxlyTheme.bubbleMax)
            let cache = heightCache
            Task.detached(priority: .utility) {
                for row in rows {
                    if cache[row.id] != nil { continue }
                    cache.store(id: row.id, height: BubbleHeightCache.estimate(row: row, maxWidth: maxWidth))
                }
            }
        }

        func configure(_ cell: UICollectionViewCell, row: TranscriptRow) {
            cell.transform = TranscriptCollectionController.invertTransform
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

        func estimatedHeight(for row: TranscriptRow, width: CGFloat) -> CGFloat {
            CGFloat(heightCache.estimated(for: row, maxWidth: Double(width * MaxlyTheme.bubbleMax)))
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            cell.transform = TranscriptCollectionController.invertTransform
            if indexPath.section == CommentsCollectionController.olderSection {
                Task { await parent.model.loadOlder() }
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            if abs(y - lastOffsetY) > 1 {
                scrollingTowardOlder = y > lastOffsetY
                lastOffsetY = y
            }
            updateAtBottom(scrollView)
            if let controller,
               let rows = controller.currentRows {
                schedulePrefetch(rows: rows, force: false)
            }
        }

        private func updateAtBottom(_ scrollView: UIScrollView) {
            // Inverted: низ ≈ маленький offset.
            let inset = scrollView.adjustedContentInset
            let distance = scrollView.contentOffset.y + inset.top
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
    static let newerSection = 0
    static let rowsSection = 1
    static let olderSection = 2

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
        let collection = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .interactive
        collection.scrollsToTop = false
        collection.transform = TranscriptCollectionController.invertTransform
        view.addSubview(collection)
        collectionView = collection
        configureDataSource()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView?.frame = view.bounds
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
        animate: Bool
    ) {
        self.post = post
        self.currentRows = rows
        self.state = state
        self.hasMore = hasMore
        self.isLoadingOlder = isLoadingOlder
        self.emptyText = emptyText
        self.width = width
        self.heightCache = heightCache
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([Self.newerSection, Self.rowsSection, Self.olderSection])
        snapshot.appendItems([.spacer], toSection: Self.newerSection)
        switch state {
        case .loading, .failed:
            snapshot.appendItems([.status], toSection: Self.rowsSection)
        case .loaded:
            snapshot.appendItems(rows.reversed().map { .row($0.id) }, toSection: Self.rowsSection)
            if let emptyText, rows.isEmpty {
                snapshot.appendItems([.status], toSection: Self.rowsSection)
            }
        }
        var older: [Item] = [.post]
        if hasMore { older.insert(.older, at: 0) }
        snapshot.appendItems(older, toSection: Self.olderSection)
        dataSource.apply(snapshot, animatingDifferences: animate)
        collectionView?.collectionViewLayout.invalidateLayout()
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] section, env in
            guard let self else {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
                let item = NSCollectionLayoutItem(layoutSize: size)
                return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [item]))
            }
            let estimated: CGFloat = {
                if let row = self.currentRows?.last {
                    return self.coordinator?.estimatedHeight(for: row, width: env.container.effectiveContentSize.width) ?? 72
                }
                return 72
            }()
            let height: NSCollectionLayoutDimension = section == Self.newerSection
                ? .absolute(1)
                : .estimated(section == Self.olderSection ? 120 : estimated)
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height)
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
            let layout = NSCollectionLayoutSection(group: group)
            layout.interGroupSpacing = 2
            layout.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: MaxlyTheme.pad, bottom: 4, trailing: MaxlyTheme.pad)
            return layout
        }
    }

    private func configureDataSource() {
        let rowRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
            guard let self, let row = self.currentRows?.first(where: { $0.id == id }) else { return }
            self.coordinator?.configure(cell, row: row)
        }
        let chromeRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, _, item in
            guard let self else { return }
            cell.transform = TranscriptCollectionController.invertTransform
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
