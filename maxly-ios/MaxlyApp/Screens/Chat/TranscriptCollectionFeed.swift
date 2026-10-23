import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Лента чата на `FeedCollectionController`: старое сверху, новое снизу, без переворота слоя.
///
/// Экран отдаёт строки, отпечаток высоты каждой строки (`layoutKey`), снимок значений пузыря и
/// куда встать (низ, цель перехода или текущее место). Высоты, зазоры шапки и поля ввода и
/// смещение — дело ленты (`FeedCollectionController`).
struct TranscriptCollectionFeed: UIViewControllerRepresentable {
    /// Куда встать: строка `id` в доле `anchor` видимой области, `latest` — к последнему сообщению.
    struct Reveal: Equatable {
        var id: String
        var anchor: Double
        var latest: Bool
    }

    /// Служебная строка над сообщениями.
    enum HeaderKind: Equatable {
        case none
        case hint(String)
        case channelReady
        case empty
        case olderLoader(loading: Bool)
    }

    @Bindable var viewModel: ChatViewModel
    let rows: [TranscriptRow]
    let revealMode: PrivateModeReveal
    let feedInset: CGFloat
    let reduceMotion: Bool
    let scrollRequest: TranscriptScrollController.Request?
    let stickToBottom: Bool
    let reveal: Reveal?
    let header: HeaderKind
    let isJumped: Bool
    /// Низ шапки в координатах окна. `nil` — ещё не измерен, лента берёт safe area окна.
    let headerBottom: CGFloat?
    /// Верх поля ввода или клавиатуры в координатах окна. `nil` — ещё не измерен.
    let composerTop: CGFloat?
    let environment: FeedEnvironment

    var snapshot: (TranscriptRow) -> TranscriptBubble.Snapshot
    var layoutKey: (TranscriptRow) -> FeedLayoutKey
    /// Оценка высоты строки далеко от экрана при ширине строки.
    var estimate: (TranscriptRow, CGFloat) -> CGFloat
    var onAuthor: (Message) -> Void
    var onFrames: (_ rows: [String: CGRect], _ viewport: CGRect) -> Void
    var onBottomDistance: (Double, Double) -> Void
    var onUserScroll: (_ moving: Bool, _ takeover: Bool) -> Void
    var onTopVisible: (Bool) -> Void
    var onNearTopPrefix: (Int?) -> Void
    var onLoadOlder: () -> Void
    var onLoadNewer: () -> Void
    var onScrollFinished: (_ token: Int, _ confirmed: Bool) -> Void
    var onPrefetchURLs: ([URL]) -> Void

    func makeUIViewController(context: Context) -> FeedCollectionController {
        let controller = FeedCollectionController()
        controller.source = context.coordinator
        context.coordinator.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: FeedCollectionController, context: Context) {
        context.coordinator.parent = self
        controller.source = context.coordinator
        context.coordinator.apply(self)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: FeedCollectionSource {
        var parent: TranscriptCollectionFeed
        weak var controller: FeedCollectionController?
        private var rowsByID: [String: TranscriptRow] = [:]
        private var shownSnapshots: [String: TranscriptBubble.Snapshot] = [:]
        private var lastRequestToken: Int?
        /// Команда прокрутки выполнена до того, как лента получила размер: сообщается, когда встанет.
        private var pendingFinish: (token: Int, confirmed: Bool)?
        private var geometrySampler = TranscriptGeometrySampler()
        private var lastPrefetchKey = ""

        static let olderID = FeedItemID.top("older")
        static let newerID = FeedItemID.bottom("newer")

        init(_ parent: TranscriptCollectionFeed) {
            self.parent = parent
        }

        func apply(_ feed: TranscriptCollectionFeed) {
            guard let controller else { return }
            controller.loadViewIfNeeded()
            controller.animatesAppend = !feed.reduceMotion
            controller.rowSpacing = 2
            var byID: [String: TranscriptRow] = [:]
            var rows: [FeedEntry] = []
            rows.reserveCapacity(feed.rows.count)
            for row in feed.rows where byID[row.id] == nil {
                byID[row.id] = row
                rows.append(FeedEntry(id: .row(row.id), key: feed.layoutKey(row)))
            }
            rowsByID = byID
            shownSnapshots = shownSnapshots.filter { byID[$0.key] != nil }
            var content = FeedContent(rows: rows)
            if let id = Self.headerID(feed.header) {
                content.top = [FeedEntry(id: id, key: FeedLayoutKey(feed.header))]
            }
            if feed.isJumped {
                content.bottom = [FeedEntry(id: Self.newerID, key: FeedLayoutKey("newer"))]
            }
            var newToken: Int?
            if let request = feed.scrollRequest {
                if request.token != lastRequestToken {
                    lastRequestToken = request.token
                    newToken = request.token
                }
            } else {
                lastRequestToken = nil
            }
            controller.setChrome(headerBottom: feed.headerBottom, composerTop: feed.composerTop)
            controller.update(content, follow: Self.follow(feed), forcePosition: newToken != nil)
            refreshVisible()
            if let token = newToken, let request = feed.scrollRequest {
                // Лента ставит строку сразу, в этом же ходе: подтверждать нечего ждать.
                let confirmed = request.latest ? !feed.rows.isEmpty : byID[request.id] != nil
                if controller.hasSettled {
                    finish(token, confirmed: confirmed)
                } else {
                    pendingFinish = (token, confirmed)
                }
            }
            prefetchImages(force: true)
        }

        private static func follow(_ feed: TranscriptCollectionFeed) -> FeedFollow {
            if let reveal = feed.reveal {
                return reveal.latest ? .bottom : .reveal(id: reveal.id, anchor: reveal.anchor)
            }
            return feed.stickToBottom ? .bottom : .anchor
        }

        private static func headerID(_ header: HeaderKind) -> FeedItemID? {
            switch header {
            case .none: nil
            case .hint: .top("hint")
            case .channelReady: .top("channel")
            case .empty: .top("empty")
            case .olderLoader: olderID
            }
        }

        private func finish(_ token: Int, confirmed: Bool) {
            // Состояние экрана меняется после хода обновления SwiftUI, а не внутри него.
            Task { @MainActor [weak self] in
                self?.parent.onScrollFinished(token, confirmed)
            }
        }

        /// Видимые пузыри получают новый снимок, если его значения сменились (ход голосового,
        /// загрузка, подсветка). Ячейка не пересоздаётся: идентификатор строки — id сообщения.
        private func refreshVisible() {
            controller?.refreshVisible { [self] id in
                guard case .row(let rowID) = id, let row = rowsByID[rowID] else { return false }
                let snap = parent.snapshot(row)
                guard shownSnapshots[rowID] != snap else { return false }
                shownSnapshots[rowID] = snap
                return true
            }
        }

        // MARK: FeedCollectionSource

        func feedView(for id: FeedItemID) -> AnyView {
            switch id {
            case .row(let rowID):
                guard let row = rowsByID[rowID] else { return AnyView(EmptyView()) }
                let state = parent.snapshot(row)
                return AnyView(
                    TranscriptBubble(
                        state: state,
                        viewModel: parent.viewModel,
                        reveal: parent.revealMode,
                        onAuthor: parent.onAuthor
                    )
                    .equatable()
                )
            case .top:
                return AnyView(headerView(parent.header))
            case .bottom:
                return AnyView(
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                )
            }
        }

        func feedEstimate(for id: FeedItemID, width: CGFloat) -> CGFloat {
            switch id {
            case .row(let rowID):
                guard let row = rowsByID[rowID] else { return 44 }
                return parent.estimate(row, width)
            case .top:
                if case .olderLoader = parent.header { return 44 }
                return 220
            case .bottom:
                return 40
            }
        }

        var feedEnvironment: FeedEnvironment { parent.environment }

        func feedSectionInsets(_ section: Int) -> UIEdgeInsets {
            guard section == FeedCollectionController.rowsSection else { return .zero }
            return UIEdgeInsets(top: 8, left: parent.feedInset, bottom: 0, right: parent.feedInset)
        }

        func feedDidMove() {
            guard let controller else { return }
            if let pending = pendingFinish, controller.hasSettled {
                pendingFinish = nil
                finish(pending.token, confirmed: pending.confirmed)
            }
            let distance = controller.bottomDistance
            parent.onBottomDistance(distance.distance, distance.visible)
            sampleGeometry(force: false)
            prefetchImages(force: false)
        }

        func feedUserScrolling(_ moving: Bool, takeover: Bool) {
            parent.onUserScroll(moving, takeover)
            if !moving { sampleGeometry(force: true) }
        }

        func feedWillDisplay(_ id: FeedItemID) {
            if id == Self.newerID { parent.onLoadNewer() }
        }

        // MARK: Геометрия для экрана

        /// Рамки видимых строк для отметки прочтения, верх ленты для истории, первая видимая строка.
        private func sampleGeometry(force: Bool) {
            let now = DispatchTime.now().uptimeNanoseconds
            guard geometrySampler.shouldFire(nowNs: now, force: force) else { return }
            guard let controller, let collection = controller.collectionView,
                  let viewport = FeedScroll.windowFrame(collection) else { return }
            let visible = controller.visibleRowFrames()
            var frames: [String: CGRect] = [:]
            for item in visible { frames[item.id] = item.frame }
            parent.onFrames(frames, viewport)
            parent.onNearTopPrefix(visible.map(\.index).min())
            parent.onTopVisible(olderLoaderVisible(controller))
        }

        /// Загрузчик истории в верхних 120 точках видимой части.
        private func olderLoaderVisible(_ controller: FeedCollectionController) -> Bool {
            guard case .olderLoader = parent.header,
                  let frame = controller.visibleFrame(of: Self.olderID),
                  let readable = controller.readableFrame else { return false }
            return frame.intersects(CGRect(x: readable.minX, y: readable.minY, width: readable.width, height: 120))
        }

        private func prefetchImages(force: Bool) {
            guard let controller else { return }
            let indices = controller.visibleRowFrames().map(\.index)
            let range: Range<Int>? = indices.min().flatMap { first in indices.max().map { first..<($0 + 1) } }
            let plan = TranscriptImagePrefetch.plan(
                messages: parent.viewModel.messages,
                visibleRange: range,
                scrollingTowardOlder: controller.scrollingTowardOlder
            )
            let key = plan.urls.map(\.absoluteString).joined(separator: "|")
            guard force || key != lastPrefetchKey else { return }
            lastPrefetchKey = key
            guard !plan.urls.isEmpty else { return }
            parent.onPrefetchURLs(plan.urls)
        }

        // MARK: Служебные строки

        @ViewBuilder
        private func headerView(_ header: HeaderKind) -> some View {
            switch header {
            case .none:
                EmptyView()
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
                .frame(maxWidth: .infinity)
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
                .frame(maxWidth: .infinity)
            case .empty:
                Text("Здесь пока нет сообщений")
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            case .olderLoader(let loading):
                let onLoadOlder = parent.onLoadOlder
                ZStack {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Загрузить предыдущие сообщения", action: onLoadOlder)
                            .font(.app(.caption))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
        }
    }
}
