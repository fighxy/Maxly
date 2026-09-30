import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var title: String
    /// Комментарии канала: `true` включены, `false` выключены, `nil` сервер не сказал —
    /// тогда кнопка есть только у постов, к которым сервер прислал счётчик.
    var commentsEnabled: Bool?
    /// В группе у чужих сообщений видны имя и аватар автора, в личном чате и канале — нет.
    var chatType: ChatType = .private
    /// Чаты для пересылки (без текущего).
    var forwardTargets: () -> [ChatListItem] = { [] }
    /// Модель профиля чата для перехода по нажатию на заголовок.
    var makeProfile: (() -> ChatProfileViewModel?)?
    @State private var forwardList: [ChatListItem] = []
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var composerFocused: Bool
    /// Низ ленты виден. Пока он виден, новые сообщения прокручивают ленту сами.
    @State private var atBottom = true
    /// Сообщения, пришедшие, пока лента прокручена вверх: число на кнопке «вниз».
    @State private var unseen = 0
    private static let bottomId = "transcript-bottom"
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if let hint = viewModel.emptyHint {
                            VStack(spacing: 12) {
                                OrbitleMark(size: 56)
                                    .foregroundStyle(.tertiary)
                                Text(hint)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 80)
                        } else {
                            Button("Раньше") { Task { await viewModel.loadOlder() } }
                                .font(.footnote)
                                .padding(.top, 8)
                        }
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            if startsDay(at: index) {
                                DaySeparator(ChatContentFormat.dayTitle(message.timestamp))
                            }
                            TranscriptBubble(
                                message: message,
                                viewModel: viewModel,
                                maxWidth: geo.size.width * OrbitleTheme.bubbleMax,
                                allowsComments: allowsComments(message),
                                showsAuthorName: showsAuthors && authorName(at: index),
                                showsAuthorAvatar: showsAuthors && authorAvatar(at: index),
                                reservesAvatar: showsAuthors,
                                group: group(at: index)
                            )
                            .id(message.id)
                        }
                        // Метка низа ленты: видна — значит, пользователь внизу.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomId)
                            .onAppear {
                                atBottom = true
                                unseen = 0
                            }
                            .onDisappear { atBottom = false }
                    }
                    .padding(.horizontal, OrbitleTheme.pad)
                    .padding(.bottom, 8)
                }
                // Чат открывается сразу внизу, а не сверху до загрузки истории.
                .defaultScrollAnchor(.bottom)
                // Клавиатура уходит, когда ленту тянут вниз вслед за пальцем или просто касаются
                // её: касание не мешает кнопкам пузырей, жест срабатывает вместе с ними.
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
                .onChange(of: viewModel.messages.last?.id) { old, id in
                    guard let id else { return }
                    let last = viewModel.messages.last
                    if old == nil {
                        // Первая загрузка: сразу к последнему, без анимации.
                        proxy.scrollTo(Self.bottomId, anchor: .bottom)
                    } else if atBottom || (last.map(viewModel.isOutgoing) ?? false) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                    } else if id != old {
                        unseen += 1
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !atBottom, !viewModel.messages.isEmpty {
                        scrollDownButton {
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                            unseen = 0
                        }
                        .padding(.trailing, OrbitleTheme.pad)
                        .padding(.bottom, 10)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.25), value: atBottom)
                .onChange(of: viewModel.scrollToken) { _, _ in
                    guard let id = viewModel.scrollTarget else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let makeProfile {
                ToolbarItem(placement: .principal) {
                    NavigationLink {
                        ProfileDestination(make: makeProfile)
                    } label: {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("\(title), открыть профиль")
                }
            }
        }
        .sheet(item: $viewModel.openedComments, onDismiss: { viewModel.closeComments() }) { post in
            if let model = viewModel.commentsModel(for: post) {
                CommentsView(model: model) { viewModel.closeComments() }
                    .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(item: $viewModel.viewer) { request in
            MediaViewer(request: request) { viewModel.viewer = nil }
        }
        .fullScreenCover(item: $viewModel.openedFile) { file in
            FileQuickLook(url: file.url, title: file.name) { viewModel.openedFile = nil }
        }
        .task {
            viewModel.activate()
            await viewModel.loadLatest()
        }
        .onDisappear { viewModel.deactivate() }
        .animation(.default, value: viewModel.notice)
        .confirmationDialog(
            "Удалить сообщение?",
            isPresented: deletionShown,
            titleVisibility: .visible,
            presenting: viewModel.deletionCandidate
        ) { message in
            if viewModel.canDeleteForEveryone(message) {
                Button(chatType == .private ? "Удалить у меня и у собеседника" : "Удалить у всех", role: .destructive) {
                    Task { await viewModel.confirmDelete(forEveryone: true) }
                }
            }
            Button("Удалить у меня", role: .destructive) {
                Task { await viewModel.confirmDelete(forEveryone: false) }
            }
            Button("Отмена", role: .cancel) { viewModel.deletionCandidate = nil }
        }
        .sheet(isPresented: forwardShown) {
            ForwardPickerView(
                targets: forwardList,
                onPick: { id in Task { await viewModel.forward(to: id) } },
                onCancel: { viewModel.forwardCandidate = nil }
            )
        }
        .onChange(of: viewModel.forwardCandidate?.id) { _, id in
            if id != nil { forwardList = forwardTargets() }
        }
        .task(id: wantsCommentCounts ? viewModel.messages.count : -1) {
            guard wantsCommentCounts, !viewModel.messages.isEmpty else { return }
            // Пауза: лента догружается пачками, счётчики уходят одним запросом.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            viewModel.requestCommentCounts(for: viewModel.messages)
        }
        // Выбрали сообщение для ответа — клавиатура сразу открывается.
        .onChange(of: viewModel.replyTarget?.id) { _, id in
            if id != nil { composerFocused = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.flushDraft() }
        }
    }

    /// Плавающий пузырь ввода: капсула поля и кнопка отправки на стекле (iOS 26),
    /// на iOS 17–18 — на материале.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .orbitleGlassCapsule()
            }
            if let notice = viewModel.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .orbitleGlassCapsule()
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let reply = viewModel.replyTarget {
                replyBar(reply)
            }
            OrbitleGlassGroup(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Сообщение", text: $viewModel.draft, axis: .vertical)
                        .focused($composerFocused)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .orbitleGlassCapsule()
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .orbitleProminentButtonStyle()
                    .buttonBorderShape(.circle)
                    .tint(Color.orbitleAccent)
                    .disabled(!viewModel.canSend)
                    .accessibilityLabel("Отправить")
                }
            }
        }
        .padding(.horizontal, OrbitleTheme.pad)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var showsAuthors: Bool { chatType == .group }

    private var deletionShown: Binding<Bool> {
        Binding(
            get: { viewModel.deletionCandidate != nil },
            set: { if !$0 { viewModel.deletionCandidate = nil } }
        )
    }

    private var forwardShown: Binding<Bool> {
        Binding(
            get: { viewModel.forwardCandidate != nil },
            set: { if !$0 { viewModel.forwardCandidate = nil } }
        )
    }

    /// Круглая кнопка «вниз» на стекле; число непрочитанных, пришедших сверху, — бейджем.
    private func scrollDownButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .orbitleGlassCircle(size: 42)
                .overlay(alignment: .top) {
                    if unseen > 0 {
                        Text(unseen > 99 ? "99+" : "\(unseen)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.orbitleAccent, in: Capsule())
                            .offset(y: -10)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unseen > 0 ? "Вниз, новых сообщений: \(unseen)" : "Вниз")
    }

    /// Кнопка комментариев — только под постами канала с включёнными комментариями.
    private func allowsComments(_ message: Message) -> Bool {
        guard chatType == .channel else { return false }
        switch commentsEnabled {
        case true?: return true
        case false?: return false
        case nil: return message.content.comments != nil || viewModel.commentCounts[message.serverId ?? message.id] != nil
        }
    }

    /// В канале с комментариями счётчики постов спрашиваются у сервера, когда лента меняется.
    private var wantsCommentCounts: Bool {
        chatType == .channel && commentsEnabled != false
    }

    private func startsDay(at index: Int) -> Bool {
        let messages = viewModel.messages
        return ChatContentFormat.startsDay(messages[index].timestamp, after: index > 0 ? messages[index - 1].timestamp : nil)
    }

    private func group(at index: Int) -> BubbleGroup {
        let messages = viewModel.messages
        let message = messages[index]
        let previous = index > 0 ? messages[index - 1] : nil
        let next = index + 1 < messages.count ? messages[index + 1] : nil
        return ChatContentFormat.group(
            authorId: message.authorId,
            date: message.timestamp,
            previous: previous.map { (authorId: $0.authorId, date: $0.timestamp) },
            next: next.map { (authorId: $0.authorId, date: $0.timestamp) }
        )
    }

    private func authorName(at index: Int) -> Bool {
        let messages = viewModel.messages
        let message = messages[index]
        let previous = index > 0 ? messages[index - 1].authorId : nil
        return ChatContentFormat.showsAuthorName(
            outgoing: viewModel.isOutgoing(message),
            authorName: message.authorName,
            authorId: message.authorId,
            previousAuthorId: previous
        )
    }

    private func authorAvatar(at index: Int) -> Bool {
        let messages = viewModel.messages
        let message = messages[index]
        let next = index + 1 < messages.count ? messages[index + 1].authorId : nil
        return ChatContentFormat.showsAuthorAvatar(
            outgoing: viewModel.isOutgoing(message),
            authorId: message.authorId,
            nextAuthorId: next
        )
    }

    private func replyTitle(_ message: Message) -> String {
        if viewModel.isOutgoing(message) { return "Вы" }
        let name = message.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Ответ" : name
    }

    private func replyBar(_ message: Message) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.orbitleAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(replyTitle(message))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.orbitleAccent)
                    .lineLimit(1)
                Text(message.replySnippet)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 9)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.orbitleAccent)
                    .frame(width: 3)
            }
            Spacer(minLength: 8)
            Button {
                viewModel.cancelReply()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить ответ")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .orbitleGlassRounded(radius: 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Пузырь ленты. Отделён от `ChatView`, чтобы замыкания не раздували её тело.
private struct TranscriptBubble: View {
    let message: Message
    let viewModel: ChatViewModel
    let maxWidth: CGFloat
    let allowsComments: Bool
    let showsAuthorName: Bool
    let showsAuthorAvatar: Bool
    let reservesAvatar: Bool
    let group: BubbleGroup

    var body: some View {
        let voiceId = message.content.voices.first?.id
        MessageBubble(
            message: message,
            isOutgoing: viewModel.isOutgoing(message),
            maxWidth: maxWidth,
            phase: voiceId.map { viewModel.voicePhase(for: $0) } ?? .idle,
            allowsComments: allowsComments,
            highlighted: viewModel.highlightedId == message.id,
            showsAuthorName: showsAuthorName,
            showsAuthorAvatar: showsAuthorAvatar,
            reservesAvatar: reservesAvatar,
            group: group,
            loadingId: viewModel.loadingMediaId,
            commentCount: viewModel.commentCount(for: message),
            onRetry: { Task { await viewModel.retry(id: message.id) } },
            onReply: { viewModel.beginReply(to: message) },
            onReact: { emoji in Task { await viewModel.toggleReaction(messageId: message.id, emoji: emoji) } },
            onComments: { viewModel.openComments(message) },
            onOpen: { viewModel.presentMedia(message, startId: $0) },
            onVoice: { viewModel.toggleVoice(message) },
            onFile: { viewModel.openFile(message, attachmentId: $0) },
            onFocusReply: { viewModel.focusReply($0) },
            onForward: { viewModel.requestForward(message) },
            onDelete: { viewModel.requestDelete(message) }
        )
    }
}
