import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var title: String
    var allowsComments = false
    /// Модель профиля чата для перехода по нажатию на заголовок.
    var makeProfile: (() -> ChatProfileViewModel?)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(spacing: 8) {
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
                        ForEach(viewModel.messages) { message in
                            TranscriptBubble(
                                message: message,
                                viewModel: viewModel,
                                maxWidth: geo.size.width * OrbitleTheme.bubbleMax,
                                allowsComments: allowsComments
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, OrbitleTheme.pad)
                    .padding(.bottom, 8)
                }
                .onChange(of: viewModel.messages.last?.id) { _, id in
                    guard viewModel.stickToBottom, let id else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                }
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
        .navigationDestination(item: $viewModel.openedCommentId) { postId in
            CommentsView(
                model: viewModel.commentsModel(for: postId),
                currentUserId: viewModel.currentUserId
            )
        }
        .fullScreenCover(item: $viewModel.viewer) { request in
            MediaViewer(request: request) { viewModel.viewer = nil }
        }
        .task {
            viewModel.activate()
            await viewModel.loadLatest()
        }
        .onDisappear { viewModel.deactivate() }
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
            if let reply = viewModel.replyTarget {
                replyBar(reply)
            }
            OrbitleGlassGroup(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Сообщение", text: $viewModel.draft, axis: .vertical)
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

    private func replyBar(_ message: Message) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orbitleAccent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ответ")
                    .font(.caption.weight(.semibold))
                Text(message.replySnippet)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .orbitleGlassCapsule()
    }
}

/// Пузырь ленты. Отделён от `ChatView`, чтобы замыкания не раздували её тело.
private struct TranscriptBubble: View {
    let message: Message
    let viewModel: ChatViewModel
    let maxWidth: CGFloat
    let allowsComments: Bool

    var body: some View {
        let voiceId = message.content.voices.first?.id
        MessageBubble(
            message: message,
            isOutgoing: viewModel.isOutgoing(message),
            maxWidth: maxWidth,
            phase: voiceId.map { viewModel.voicePhase(for: $0) } ?? .idle,
            allowsComments: allowsComments,
            highlighted: viewModel.highlightedId == message.id,
            onRetry: { Task { await viewModel.retry(id: message.id) } },
            onReply: { viewModel.beginReply(to: message) },
            onReact: { emoji in Task { await viewModel.toggleReaction(messageId: message.id, emoji: emoji) } },
            onComments: { viewModel.openComments(message) },
            onOpen: { viewModel.presentMedia(message, startId: $0) },
            onVoice: { viewModel.toggleVoice(message) },
            onFocusReply: { viewModel.focusReply($0) }
        )
    }
}
