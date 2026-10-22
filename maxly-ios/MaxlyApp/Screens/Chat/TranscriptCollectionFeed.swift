import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Лента на UICollectionView: recycling, кэш высот, перевёрнутая ось (новое у низа как index 0).
///
/// `transform = scaleY(-1)` на коллекции и ячейках: в data source новее сообщения первыми,
/// визуально они у низа; вставка нового не сдвигает offset старых. Геометрию и «вниз»
/// считаем в экранных координатах после transform.
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
    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
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

        init(_ parent: TranscriptCollectionFeed) {
            self.parent = parent
        }

        func apply(_ feed: TranscriptCollectionFeed) {
            guard let controller else { return }
            controller.loadViewIfNeeded()
            controller.collectionView?.delegate = self
            controller.collectionView?.prefetchDataSource = self
            let animate = feed.animateInserts && !feed.isOpening && !feed.isRestoringHistory && !feed.reduceMotion
            prewarmHeights(feed.rows, width: feed.width, feedInset: feed.feedInset)
            controller.setRows(
                feed.rows,
                width: feed.width,
                feedInset: feed.feedInset,
                heightCache: heightCache,
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
            Task.detached(priority: .utility) {
                for row in rows {
                    if cache[row.id] != nil { continue }
                    let height = BubbleHeightCache.estimate(row: row, maxWidth: maxWidth)
                    cache.store(id: row.id, height: height)
                }
            }
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            cell.transform = TranscriptCollectionController.invertTransform
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
            // После scaleY(-1) рост offset ведёт к визуальному верху (старое).
            if abs(y - lastOffsetY) > 1 {
                scrollingTowardOlder = y > lastOffsetY
                lastOffsetY = y
            }
            reportBottom(scrollView)
            sampleGeometry(force: false)
            updateTopVisible()
            scheduleImagePrefetch(force: false)
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
            cell.transform = TranscriptCollectionController.invertTransform
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
            let inset = scrollView.adjustedContentInset
            // Inverted: «низ» ≈ маленький offset.
            let distance = max(0, Double(scrollView.contentOffset.y + inset.top))
            parent.onBottomDistance(distance, Double(scrollView.bounds.height - inset.top - inset.bottom))
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
    }
}

// MARK: - Controller

@MainActor
final class TranscriptCollectionController: UIViewController {
    /// После `scaleY(-1)` первая секция — у визуального низа, последняя — у верха.
    static let newerSection = 0
    static let rowsSection = 1
    static let olderSection = 2
    static let invertTransform = CGAffineTransform(scaleX: 1, y: -1)

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
    private var width: CGFloat = 0
    private var feedInset: CGFloat = 8
    private weak var heightCache: BubbleHeightCache?

    enum Item: Hashable {
        case newer
        case row(String)
        case older
        case chromeEmpty
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
        collection.transform = Self.invertTransform
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
        heightCache: BubbleHeightCache,
        animate: Bool,
        header: HeaderKind,
        footerLoading: Bool
    ) {
        self.rows = rows
        self.width = width
        self.feedInset = feedInset
        self.heightCache = heightCache
        self.header = header
        self.footerLoading = footerLoading
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([Self.newerSection, Self.rowsSection, Self.olderSection])
        // newerSection → визуальный низ: jump-loader или пустой слот.
        if footerLoading {
            snapshot.appendItems([.newer], toSection: Self.newerSection)
        } else {
            snapshot.appendItems([.chromeEmpty], toSection: Self.newerSection)
        }
        // В data source новее первыми (index 0 у визуального низа после invert).
        snapshot.appendItems(rows.reversed().map { .row($0.id) }, toSection: Self.rowsSection)
        // olderSection → визуальный верх.
        if header != .none {
            snapshot.appendItems([.older], toSection: Self.olderSection)
        } else {
            snapshot.appendItems([.chromeEmpty], toSection: Self.olderSection)
        }
        dataSource.apply(snapshot, animatingDifferences: animate)
        collectionView?.collectionViewLayout.invalidateLayout()
    }

    func displayIndex(for id: String) -> Int? {
        guard let chrono = rows.firstIndex(where: { $0.id == id }) else { return nil }
        return rows.count - 1 - chrono
    }

    func chronologicalIndex(display: Int) -> Int? {
        guard rows.indices.contains(display) else { return nil }
        return rows.count - 1 - display
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
        // После invert .top в координатах коллекции ≈ визуальный низ.
        let position: UICollectionView.ScrollPosition
        if latest || anchor >= 0.85 {
            position = .top
        } else if anchor <= 0.15 {
            position = .bottom
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
            guard let self else { return Self.fallbackSection() }
            switch sectionIndex {
            case Self.newerSection:
                return self.fixedSection(height: self.footerLoading ? 40 : 1)
            case Self.olderSection:
                return self.olderSectionLayout()
            default:
                return self.rowsSectionLayout(width: environment.container.effectiveContentSize.width)
            }
        }
    }

    private func rowsSectionLayout(width: CGFloat) -> NSCollectionLayoutSection {
        let estimated: CGFloat = {
            guard let first = rows.last, let cache = heightCache else { return 72 }
            return max(36, coordinator?.estimatedHeight(for: first, width: width, feedInset: feedInset) ?? 72)
        }()
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(estimated)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 2
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: feedInset, bottom: 0, trailing: feedInset)
        return section
    }

    private func olderSectionLayout() -> NSCollectionLayoutSection {
        let height: CGFloat
        switch header {
        case .none: height = 1
        case .olderLoader: height = 32
        case .hint, .channelReady, .empty: height = 200
        }
        return fixedSection(height: height, estimated: true)
    }

    private func fixedSection(height: CGFloat, estimated: Bool = false) -> NSCollectionLayoutSection {
        let dim: NSCollectionLayoutDimension = estimated ? .estimated(height) : .absolute(max(1, height))
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: dim)
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
            cell.transform = Self.invertTransform
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
