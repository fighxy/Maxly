import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Комментарии на той же ленте, что и чат (`FeedCollectionController`): пост сверху,
/// обсуждение под ним, старое сверху, новое снизу. Окно открывается на посте и первых
/// комментариях, более новые догружаются при прокрутке вниз. Те же правила высот, места и низа.
struct CommentsCollectionFeed: UIViewControllerRepresentable {
    @Bindable var model: CommentsViewModel
    let width: CGFloat
    let reveal: PrivateModeReveal
    let reduceMotion: Bool
    let atBottom: Binding<Bool>
    /// Верх поля ввода в координатах окна. `nil` — ещё не измерен, лента берёт safe area окна.
    let composerTop: CGFloat?
    let environment: FeedEnvironment
    var onBlockAuthor: ((Message) async throws -> Void)?
    var onBlockNotice: (String) -> Void

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

    /// Отпечаток высоты комментария или поста.
    private struct LayoutKey: Equatable {
        var message: Message
        var row: TranscriptRow?
        var width: CGFloat
        var isRevealed: Bool
        var privateMode: PrivateModeDisplay
        var dynamicTypeSize: DynamicTypeSize
        var font: AppFont
        var fontWeight: Int
        var textSize: TextSizeStep
    }

    /// Строка состояния под постом: загрузка, ошибка или «пока нет комментариев».
    private struct StatusKey: Equatable {
        var state: CommentsViewModel.State
        var emptyText: String?
        var width: CGFloat
    }

    @MainActor
    final class Coordinator: FeedCollectionSource {
        var parent: CommentsCollectionFeed
        weak var controller: FeedCollectionController?
        private var rowsByID: [String: TranscriptRow] = [:]
        private var shownRows: [String: TranscriptRow] = [:]
        private var shownPost: Message?
        private var lastPrefetchKey = ""
        /// Обновление SwiftUI идёт: состояние экрана меняется после него.
        private var applying = false
        private var pendingReport = false
        /// Страница новых уже запрошена для этого состава ленты.
        private var newerRequested = false

        static let postID = FeedItemID.top("post")
        static let newerID = FeedItemID.bottom("newer")
        static let statusID = FeedItemID.bottom("status")

        init(_ parent: CommentsCollectionFeed) { self.parent = parent }

        func apply(_ feed: CommentsCollectionFeed) {
            guard let controller else { return }
            applying = true
            defer {
                applying = false
                if pendingReport {
                    pendingReport = false
                    Task { @MainActor [weak self] in self?.report() }
                }
            }
            controller.loadViewIfNeeded()
            controller.animatesAppend = !feed.reduceMotion
            controller.rowSpacing = 2
            let typography = Typography.shared
            func key(_ message: Message, row: TranscriptRow?) -> FeedLayoutKey {
                FeedLayoutKey(LayoutKey(
                    message: message,
                    row: row,
                    width: feed.width,
                    isRevealed: feed.reveal.isRevealed(message.id),
                    privateMode: feed.environment.privateMode,
                    dynamicTypeSize: feed.environment.dynamicTypeSize,
                    font: typography.font,
                    fontWeight: typography.weight,
                    textSize: typography.textSize
                ))
            }
            var byID: [String: TranscriptRow] = [:]
            var rows: [FeedEntry] = []
            if case .loaded = feed.model.state {
                for row in TranscriptLayout.rows(feed.model.comments, currentUserId: feed.model.currentUserId) where byID[row.id] == nil {
                    byID[row.id] = row
                    rows.append(FeedEntry(id: .row(row.id), key: key(row.message, row: row)))
                }
            }
            if Set(byID.keys) != Set(rowsByID.keys) { newerRequested = false }
            rowsByID = byID
            var content = FeedContent(rows: rows)
            content.top = [FeedEntry(id: Self.postID, key: key(feed.model.post, row: nil))]
            if case .loaded = feed.model.state, feed.model.hasNewer {
                content.bottom.append(FeedEntry(id: Self.newerID, key: FeedLayoutKey(feed.model.isLoadingNewer)))
            }
            let showsStatus: Bool
            switch feed.model.state {
            case .loading, .failed: showsStatus = true
            case .loaded: showsStatus = rows.isEmpty && feed.model.emptyText != nil
            }
            if showsStatus {
                content.bottom.append(FeedEntry(
                    id: Self.statusID,
                    key: FeedLayoutKey(StatusKey(state: feed.model.state, emptyText: feed.model.emptyText, width: feed.width))
                ))
            }
            controller.setChrome(headerBottom: nil, composerTop: feed.composerTop)
            controller.update(content, follow: feed.atBottom.wrappedValue ? .bottom : .anchor)
            refreshVisible(post: feed.model.post)
            prefetchImages(force: true)
        }

        /// Видимые комментарии и пост с новыми значениями (реакции на месте, статус отправки).
        private func refreshVisible(post: Message) {
            shownRows = shownRows.filter { rowsByID[$0.key] != nil }
            let postChanged = shownPost != post
            shownPost = post
            controller?.refreshVisible { [self] id in
                switch id {
                case .row(let rowID):
                    guard let row = rowsByID[rowID], shownRows[rowID] != row else { return false }
                    shownRows[rowID] = row
                    return true
                case .top("post"):
                    return postChanged
                default:
                    return false
                }
            }
        }

        // MARK: FeedCollectionSource

        func feedView(for id: FeedItemID) -> AnyView {
            switch id {
            case .row(let rowID):
                guard let row = rowsByID[rowID] else { return AnyView(EmptyView()) }
                return AnyView(CommentsCollectionCell(
                    row: row,
                    model: parent.model,
                    reveal: parent.reveal,
                    reduceMotion: parent.reduceMotion,
                    width: parent.width,
                    onBlockAuthor: parent.onBlockAuthor,
                    onBlockNotice: parent.onBlockNotice
                ))
            case .top:
                return AnyView(postView)
            case .bottom("newer"):
                return AnyView(
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .opacity(parent.model.isLoadingNewer ? 1 : 0.4)
                )
            case .bottom:
                return AnyView(statusView)
            }
        }

        func feedEstimate(for id: FeedItemID, width: CGFloat) -> CGFloat {
            switch id {
            case .row(let rowID):
                guard let row = rowsByID[rowID] else { return 44 }
                return CGFloat(BubbleHeightCache.estimate(row: row, maxWidth: Double(parent.width * MaxlyTheme.bubbleMax)))
            case .top:
                guard let row = TranscriptLayout.rows([parent.model.post], currentUserId: "").first else { return 180 }
                return CGFloat(BubbleHeightCache.estimate(row: row, maxWidth: Double(parent.width * MaxlyTheme.bubbleMax))) + 10
            case .bottom("newer"):
                return 36
            case .bottom:
                return 96
            }
        }

        var feedEnvironment: FeedEnvironment { parent.environment }

        func feedSectionInsets(_ section: Int) -> UIEdgeInsets {
            // Нижняя секция без полей: под последним комментарием нет лишней щели.
            guard section != FeedCollectionController.bottomSection else { return .zero }
            return UIEdgeInsets(top: 4, left: MaxlyTheme.pad, bottom: 4, right: MaxlyTheme.pad)
        }

        func feedDidMove() {
            if applying {
                pendingReport = true
            } else {
                report()
            }
            prefetchImages(force: false)
        }

        func feedUserScrolling(_ moving: Bool, takeover: Bool) {
            if !moving { report() }
        }

        func feedWillDisplay(_ id: FeedItemID) {
            guard id == Self.newerID else { return }
            loadNewerIfNeeded()
        }

        /// Низ ленты для прилипания и страница новых, когда загрузчик на экране.
        private func report() {
            guard let controller else { return }
            let distance = controller.bottomDistance.distance
            let next = distance < (parent.atBottom.wrappedValue ? 64 : 24)
            if next != parent.atBottom.wrappedValue {
                parent.atBottom.wrappedValue = next
            }
            if controller.visibleFrame(of: Self.newerID) != nil { loadNewerIfNeeded() }
        }

        /// Пока лента не встала на место, загрузчик страницы не тянет: иначе первая же раскладка
        /// с коротким обсуждением сразу просила бы следующие.
        private func loadNewerIfNeeded() {
            guard let controller, controller.hasSettled, !newerRequested,
                  parent.model.hasNewer, !parent.model.isLoadingNewer else { return }
            newerRequested = true
            let model = parent.model
            Task { await model.loadNewer() }
        }

        private func prefetchImages(force: Bool) {
            guard let controller else { return }
            let messages = parent.model.comments
            let indices = controller.visibleRowFrames().map(\.index)
            let range: Range<Int>? = indices.min().flatMap { first in indices.max().map { first..<($0 + 1) } }
            let plan = TranscriptImagePrefetch.plan(
                messages: messages,
                visibleRange: range,
                scrollingTowardOlder: controller.scrollingTowardOlder
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

        // MARK: Служебные строки

        private var postView: some View {
            let post = parent.model.post
            let reveal = parent.reveal
            let reduceMotion = parent.reduceMotion
            let maxWidth = parent.width * MaxlyTheme.bubbleMax
            return VStack(spacing: 6) {
                PrivateBubbleGate(
                    isRevealed: reveal.isRevealed(post.id),
                    accessibilityText: PrivateModeMask.messageText(for: post, outgoing: false),
                    onReveal: {
                        withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { reveal.reveal(post.id) }
                    },
                    real: {
                        MessageBubble(message: post, isOutgoing: false, maxWidth: maxWidth, allowsReactions: false)
                    },
                    masked: {
                        MessageBubble(
                            message: PrivateModeMask.message(post, outgoing: false),
                            isOutgoing: false,
                            maxWidth: maxWidth,
                            allowsReactions: false
                        )
                    }
                )
                DaySeparator("Начало обсуждения")
            }
            .padding(.bottom, 4)
        }

        @ViewBuilder
        private var statusView: some View {
            let model = parent.model
            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Повторить") { Task { await model.reload() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            case .loaded:
                if let emptyText = model.emptyText {
                    Text(emptyText)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
            }
        }
    }
}

// MARK: - Строка комментария

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
