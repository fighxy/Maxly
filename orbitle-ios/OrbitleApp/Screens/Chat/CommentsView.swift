import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Комментарии поста канала в модальном окне: сверху пост, под ним обсуждение с авторами,
/// внизу поле ввода. Кнопка «Закрыть» в навигационной панели.
struct CommentsView: View {
    @Bindable var model: CommentsViewModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            post(width: geo.size.width)
                            content(width: geo.size.width)
                        }
                        .padding(.horizontal, OrbitleTheme.pad)
                        .padding(.vertical, 8)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable { await model.reload() }
                    .onChange(of: model.comments.last?.id) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть", action: onClose)
                }
            }
            .task { await model.load() }
        }
    }

    // MARK: Пост

    private func post(width: CGFloat) -> some View {
        VStack(spacing: 6) {
            MessageBubble(
                message: model.post,
                isOutgoing: false,
                maxWidth: width * OrbitleTheme.bubbleMax
            )
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
        return MessageBubble(
            message: comment,
            isOutgoing: outgoing,
            maxWidth: width * OrbitleTheme.bubbleMax,
            showsAuthorName: !outgoing && !group.joinsPrevious,
            showsAuthorAvatar: !outgoing && !group.joinsNext,
            reservesAvatar: !outgoing,
            group: group,
            onRetry: { Task { await model.retry(comment.id) } }
        )
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
                        .orbitleGlassCapsule()
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
