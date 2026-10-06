import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Комментарии поста канала в модальном окне: сверху пост, под ним обсуждение с авторами,
/// внизу поле ввода. Кнопка «Закрыть» в навигационной панели.
/// В приватном режиме пост и комментарии закрыты, как пузыри чата, и открываются касанием.
struct CommentsView: View {
    @Bindable var model: CommentsViewModel
    let onClose: () -> Void
    /// Блок автора комментария. Ошибку показывает этот экран.
    var onBlockAuthor: ((Message) async throws(OrbitleError) -> Void)? = nil
    @State private var blockNotice: String?
    @State private var reveal = PrivateModeReveal()
    @State private var atBottom = true
    @State private var visibleCommentId: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.privateMode) private var privateMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            post(width: geo.size.width)
                            content(width: geo.size.width)
                            Color.clear.frame(height: 1).background {
                                GeometryReader { marker in
                                    Color.clear.preference(key: CommentsBottomPreference.self,
                                        value: marker.frame(in: .named("comments-viewport")).maxY)
                                }
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, OrbitleTheme.pad)
                        .padding(.vertical, 8)
                        // Как в ленте чата: новые и удалённые — плавно, первая страница и
                        // подгрузка старых сверху — сразу.
                        .animation(atBottom ? OrbitleMotion.transcript(model.commentsChange, reduceMotion: reduceMotion) : nil, value: model.comments.map(\.id))
                        .animation(OrbitleMotion.fade, value: model.state)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollPosition(id: $visibleCommentId, anchor: .top)
                    .coordinateSpace(name: "comments-viewport")
                    .onPreferenceChange(CommentsBottomPreference.self) { y in
                        atBottom = y.isFinite && y >= 0 && y <= geo.size.height + (atBottom ? 64 : 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable { await model.reload() }
                    .onChange(of: model.comments.last?.id) { old, id in
                        guard let id else { return }
                        // Первая загрузка — сразу вниз, без прокрутки на глазах.
                        guard old != nil else {
                            proxy.scrollTo(id, anchor: .bottom)
                            return
                        }
                        // Чужое новое и удаление последнего не уводят читателя из истории.
                        guard case .appended = model.commentsChange,
                              let last = model.comments.last, atBottom || model.isOutgoing(last) else { return }
                        withAnimation(OrbitleMotion.standard(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
            .background(Color.orbitleChatBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть", action: onClose)
                }
            }
            .task { await model.load() }
            .onDisappear { reveal.hideAll() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { reveal.hideAll() }
            }
            .onChange(of: privateMode) { _, _ in reveal.hideAll() }
            .alert("Комментарий", isPresented: Binding(get: { blockNotice != nil }, set: { if !$0 { blockNotice = nil } })) {
                Button("OK", role: .cancel) { blockNotice = nil }
            } message: {
                Text(blockNotice ?? "")
            }
        }
    }

    /// Пузырь за шторкой приватного режима: заглушка без имени, медиа и реакций.
    private func gated<Real: View>(
        _ message: Message,
        outgoing: Bool,
        width: CGFloat,
        showsAuthorAvatar: Bool = false,
        reservesAvatar: Bool = false,
        group: BubbleGroup = .single,
        @ViewBuilder real: () -> Real
    ) -> some View {
        PrivateBubbleGate(
            isRevealed: reveal.isRevealed(message.id),
            accessibilityText: PrivateModeMask.messageText(for: message, outgoing: outgoing),
            onReveal: { withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { reveal.reveal(message.id) } },
            real: real,
            masked: {
                MessageBubble(
                    message: PrivateModeMask.message(message, outgoing: outgoing),
                    isOutgoing: outgoing,
                    maxWidth: width * OrbitleTheme.bubbleMax,
                    showsAuthorAvatar: showsAuthorAvatar,
                    reservesAvatar: reservesAvatar,
                    group: group,
                    allowsReactions: false
                )
            }
        )
    }

    // MARK: Пост

    private func post(width: CGFloat) -> some View {
        VStack(spacing: 6) {
            gated(model.post, outgoing: false, width: width) {
                MessageBubble(
                    message: model.post,
                    isOutgoing: false,
                    maxWidth: width * OrbitleTheme.bubbleMax,
                    allowsReactions: false
                )
            }
            DaySeparator("Начало обсуждения")
        }
        .padding(.bottom, 4)
    }

    // MARK: Комментарии

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Повторить") { Task { await model.reload() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        case .loaded:
            if model.hasMore {
                // Верх загруженного: следующая страница подгружается, когда до него долистали.
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .opacity(model.isLoadingOlder ? 1 : 0.4)
                    .onAppear { Task { await model.loadOlder() } }
            }
            if let empty = model.emptyText {
                Text(empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
            ForEach(Array(model.comments.enumerated()), id: \.element.id) { index, comment in
                bubble(comment, index: index, width: width)
                    .id(comment.id)
                    .transition(.orbitleBubble(outgoing: model.isOutgoing(comment), reduceMotion: reduceMotion))
            }
        }
    }

    private func bubble(_ comment: Message, index: Int, width: CGFloat) -> some View {
        let comments = model.comments
        let outgoing = model.isOutgoing(comment)
        let previous = index > 0 ? comments[index - 1] : nil
        let next = index + 1 < comments.count ? comments[index + 1] : nil
        let group = ChatContentFormat.group(
            authorId: comment.authorId,
            date: comment.timestamp,
            previous: previous.map { (authorId: $0.authorId, date: $0.timestamp) },
            next: next.map { (authorId: $0.authorId, date: $0.timestamp) }
        )
        return gated(
            comment,
            outgoing: outgoing,
            width: width,
            showsAuthorAvatar: !outgoing && !group.joinsNext,
            reservesAvatar: !outgoing,
            group: group
        ) {
            MessageBubble(
                message: comment,
                isOutgoing: outgoing,
                maxWidth: width * OrbitleTheme.bubbleMax,
                showsAuthorName: !outgoing && !group.joinsPrevious,
                showsAuthorAvatar: !outgoing && !group.joinsNext,
                reservesAvatar: !outgoing,
                group: group,
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
                                blockNotice = "Автор комментария заблокирован"
                            } catch let error as OrbitleError {
                                blockNotice = error.userMessage ?? "Не удалось заблокировать"
                            } catch is CancellationError {
                                return
                            } catch {
                                blockNotice = "Не удалось заблокировать"
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Ввод

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .orbitleGlassCapsule()
            }
            OrbitleGlassGroup(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Комментарий", text: $model.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .orbitleGlassRounded(radius: 22)
                    Button {
                        Task { await model.send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .orbitleProminentButtonStyle()
                    .buttonBorderShape(.circle)
                    .tint(Color.orbitleAccent)
                    .disabled(!model.canSend)
                    .accessibilityLabel("Отправить комментарий")
                }
            }
        }
        .padding(.horizontal, OrbitleTheme.pad)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

private struct CommentsBottomPreference: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
