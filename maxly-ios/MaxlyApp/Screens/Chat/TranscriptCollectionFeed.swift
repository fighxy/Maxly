import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Лента на UICollectionView: recycling ячеек, оценка высоты, рамки из UIKit.
///
/// Ячейки — SwiftUI `TranscriptBubble` через `UIHostingConfiguration`. Команды прокрутки
/// и геометрия для read marks / «вниз» идут через координатор, без per-row
/// `onGeometryChange` у каждой строки.
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
    final class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: TranscriptCollectionFeed
        weak var controller: TranscriptCollectionController?
        private var heightCache = BubbleHeightCache()
        private var lastRequestToken: Int?
        private var scrollTask: Task<Void, Never>?
        private var geometrySampler = TranscriptGeometrySampler()
        private var userDragging = false

        init(_ parent: TranscriptCollectionFeed) {
            self.parent = parent
        }

        func apply(_ feed: TranscriptCollectionFeed) {
            guard let controller else { return }
            controller.loadViewIfNeeded()
            controller.collectionView?.delegate = self
            let animate = feed.animateInserts && !feed.isOpening && !feed.isRestoringHistory && !feed.reduceMotion
            controller.setRows(
                feed.rows,
                width: feed.width,
                feedInset: feed.feedInset,
                animate: animate,
                header: headerKind(feed),
                footerLoading: feed.isJumped
            )
            if let request = feed.scrollRequest, request.token != lastRequestToken {
                lastRequestToken = request.token
                runScroll(request)
            } else if feed.scrollRequest == nil {
                lastRequestToken = nil
            }
        }

        private func headerKind(_ feed: TranscriptCollectionFeed) -> TranscriptCollectionController.HeaderKind {
            if let hint = feed.emptyHint { return .hint(hint) }
            if feed.showsChannelReady { return .channelReady }
            if feed.showsEmpty { return .empty }
            if feed.canLoadOlder { return .olderLoader(loading: feed.isLoadingOlder) }
            return .none
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            sampleGeometry(force: false)
            if indexPath.section == TranscriptCollectionController.rowsSection {
                let prefix = indexPath.item
                parent.onNearTopPrefix(prefix)
            }
        }

        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            sampleGeometry(force: false)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportBottom(scrollView)
            sampleGeometry(force: false)
            updateTopVisible(scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            userDragging = true
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

        func estimatedHeight(for row: TranscriptRow, width: CGFloat, feedInset: CGFloat) -> CGFloat {
            let maxWidth = min(520, max(0, width - feedInset * 2) * MaxlyTheme.bubbleMax)
            return CGFloat(heightCache.estimated(for: row, maxWidth: Double(maxWidth)))
        }

        func storeMeasuredHeight(id: String, height: CGFloat) {
            heightCache.store(id: id, height: Double(height))
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
                    token: request.token,
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
            let visibleRows = collection.indexPathsForVisibleItems
                .filter { $0.section == TranscriptCollectionController.rowsSection }
            for indexPath in visibleRows {
                guard indexPath.item < parent.rows.count,
                      let cell = collection.cellForItem(at: indexPath) else { continue }
                let id = parent.rows[indexPath.item].id
                let frame = cell.convert(cell.bounds, to: nil)
                frames[id] = frame
                storeMeasuredHeight(id: id, height: cell.bounds.height)
            }
            parent.onFrames(frames, viewport, collection.adjustedContentInset.top)
            parent.onNearTopPrefix(visibleRows.map(\.item).min())
        }

        private func reportBottom(_ scrollView: UIScrollView) {
            let inset = scrollView.adjustedContentInset
            let distance = ScrollDownVisibility.distanceFromBottom(
                contentHeight: Double(scrollView.contentSize.height),
                offsetY: Double(scrollView.contentOffset.y),
                viewportHeight: Double(scrollView.bounds.height),
                insetTop: Double(inset.top),
                insetBottom: Double(inset.bottom)
            )
            parent.onBottomDistance(distance, Double(scrollView.bounds.height - inset.top - inset.bottom))
        }

        private func updateTopVisible(_ scrollView: UIScrollView) {
            guard let controller else { return }
            // Загрузку старого ведёт `ChatTranscript.task(id: shouldPrefetchOlder)`, не каждый scroll.
            parent.onTopVisible(controller.isOlderHeaderVisible)
        }
    }
}

// MARK: - Controller

@MainActor
final class TranscriptCollectionController: UIViewController {
    static let headerSection = 0
    static let rowsSection = 1
    static let footerSection = 2

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
    private var rows: [TranscriptRow] = []
    private var header: HeaderKind = .none
    private var footerLoading = false
    private var width: CGFloat = 0
    private var feedInset: CGFloat = 8

    enum Item: Hashable {
        case header
        case row(String)
        case footer
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let layout = makeLayout()
        let collection = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .interactive
        collection.scrollsToTop = false
        collection.contentInsetAdjustmentBehavior = .automatic
        view.addSubview(collection)
        collectionView = collection
        configureDataSource()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView?.frame = view.bounds
    }

    func setRows(
        _ rows: [TranscriptRow],
        width: CGFloat,
        feedInset: CGFloat,
        animate: Bool,
        header: HeaderKind,
        footerLoading: Bool
    ) {
        self.rows = rows
        self.width = width
        self.feedInset = feedInset
        self.header = header
        self.footerLoading = footerLoading
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([Self.headerSection, Self.rowsSection, Self.footerSection])
        if header != .none { snapshot.appendItems([.header], toSection: Self.headerSection) }
        snapshot.appendItems(rows.map { .row($0.id) }, toSection: Self.rowsSection)
        if footerLoading { snapshot.appendItems([.footer], toSection: Self.footerSection) }
        dataSource.apply(snapshot, animatingDifferences: animate)
        collectionView?.collectionViewLayout.invalidateLayout()
    }

    var isOlderHeaderVisible: Bool {
        guard header != .none,
              case .olderLoader = header,
              let collectionView,
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: Self.headerSection))
        else { return false }
        let frame = attributes.frame
        let visible = CGRect(
            x: collectionView.contentOffset.x,
            y: collectionView.contentOffset.y,
            width: collectionView.bounds.width,
            height: 100 + collectionView.adjustedContentInset.top
        )
        return frame.maxY >= collectionView.contentOffset.y && frame.minY < visible.maxY
    }

    func scrollTo(
        id: String,
        anchor: Double,
        latest: Bool,
        token: Int,
        stillCurrent: @escaping () -> Bool
    ) async -> Bool {
        guard let collectionView,
              let index = rows.firstIndex(where: { $0.id == id }) else { return false }
        let indexPath = IndexPath(item: index, section: Self.rowsSection)
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

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self else {
                return Self.fallbackSection()
            }
            let width = environment.container.effectiveContentSize.width
            switch sectionIndex {
            case Self.headerSection:
                return self.headerSectionLayout(width: width)
            case Self.footerSection:
                return self.footerSectionLayout()
            default:
                return self.rowsSectionLayout(width: width)
            }
        }
    }

    private func rowsSectionLayout(width: CGFloat) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(72)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 2
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: feedInset, bottom: 8, trailing: feedInset)
        return section
    }

    private func headerSectionLayout(width: CGFloat) -> NSCollectionLayoutSection {
        let height: CGFloat
        switch header {
        case .none: height = 1
        case .olderLoader: height = 32
        case .hint, .channelReady, .empty: height = 200
        }
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        return NSCollectionLayoutSection(group: group)
    }

    private func footerSectionLayout() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        return NSCollectionLayoutSection(group: group)
    }

    private static func fallbackSection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        return NSCollectionLayoutSection(group: group)
    }

    private func configureDataSource() {
        let rowRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
            guard let self, let row = self.rows.first(where: { $0.id == id }) else { return }
            self.coordinator?.configure(cell, row: row)
        }
        let chromeRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, _, item in
            guard let self else { return }
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
            case .header, .footer:
                return collectionView.dequeueConfiguredReusableCell(using: chromeRegistration, for: indexPath, item: item)
            }
        }
    }

    @ViewBuilder
    private func chromeView(for item: Item) -> some View {
        switch item {
        case .header:
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
        case .footer:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .onAppear { self.coordinator?.parent.onLoadNewer() }
        case .row:
            EmptyView()
        }
    }
}
