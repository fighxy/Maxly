import SwiftUI
import UIKit
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Пузырь ленты: все изменчивые значения приходят готовыми в `Snapshot`, поэтому пузырь
/// сравнивается целиком и не перерисовывается, если его значения не поменялись. Модель и
/// приватный режим нужны только для действий: тело пузыря их свойства не читает.
struct TranscriptBubble: View, Equatable {
    struct Snapshot: Equatable {
        var row: TranscriptRow
        var maxWidth: CGFloat
        var showsAuthorName: Bool
        var showsAuthorAvatar: Bool
        var reservesAvatar: Bool
        var allowsComments: Bool
        var canWrite: Bool
        /// «Кто отреагировал» — в группах. В личном чате и так видно, в канале — только числа.
        var showsReactionUsers: Bool
        /// Открыт касанием в приватном режиме.
        var isRevealed: Bool
        var highlighted: Bool
        var phase: VoicePhase
        /// Вложение этого сообщения, которое сейчас грузится; чужие сюда не попадают.
        var loadingId: String?
        var commentCount: Int?
        var uploadProgress: Double?
        var reacts: Bool
        var quickReactions: [String]
        var canEdit: Bool
        var savesToPhotos: Bool
        var savesToFiles: Bool
        /// Кружок этого сообщения, играющий в ленте.
        var roundPlayback: RoundPlayback?
        /// Расшифровка голосового: «→T», загрузка или раскрытый текст.
        var transcript: TranscriptPhase
        var canTranscribe: Bool
        /// Эмодзи двойного нажатия. В сравнении снимка, иначе смена реакции не перерисует пузырь.
        var quickReaction: String?
    }

    let state: Snapshot
    let viewModel: ChatViewModel
    let reveal: PrivateModeReveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (lhs: TranscriptBubble, rhs: TranscriptBubble) -> Bool {
        lhs.state == rhs.state
    }

    private var message: Message { state.row.message }

    var body: some View {
        VStack(spacing: 2) {
            if let day = state.row.dayTitle {
                DaySeparator(day)
                    .transition(.opacity)
            }
            if state.row.startsUnread {
                UnreadSeparator()
                    .transition(.opacity)
            }
            PrivateBubbleGate(
                isRevealed: state.isRevealed,
                accessibilityText: PrivateModeMask.messageText(for: message, outgoing: state.row.isOutgoing),
                onReveal: { [reveal, id = message.id] in
                    withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { reveal.reveal(id) }
                }
            ) {
                bubble
            } masked: {
                // Заглушка: «Вы получили сообщение», время и галочки; без имени, медиа и реакций.
                MessageBubble(
                    message: PrivateModeMask.message(message, outgoing: state.row.isOutgoing),
                    isOutgoing: state.row.isOutgoing,
                    maxWidth: state.maxWidth,
                    highlighted: state.highlighted,
                    showsAuthorAvatar: state.showsAuthorAvatar,
                    reservesAvatar: state.reservesAvatar,
                    group: state.row.group
                )
            }
        }
    }

    private var bubble: some View {
        let viewModel = viewModel
        let message = message
        return MessageBubble(
            message: message,
            isOutgoing: state.row.isOutgoing,
            maxWidth: state.maxWidth,
            phase: state.phase,
            allowsComments: state.allowsComments,
            highlighted: state.highlighted,
            showsAuthorName: state.showsAuthorName,
            showsAuthorAvatar: state.showsAuthorAvatar,
            reservesAvatar: state.reservesAvatar,
            group: state.row.group,
            loadingId: state.loadingId,
            commentCount: state.commentCount,
            onRetry: { Task { await viewModel.retry(id: message.id) } },
            onReply: { viewModel.beginReply(to: message) },
            onReact: { emoji in Task { await viewModel.toggleReaction(messageId: message.id, emoji: emoji) } },
            onComments: { viewModel.openComments(message) },
            onOpen: { viewModel.presentMedia(message, startId: $0) },
            onVoice: { viewModel.toggleVoice(message) },
            onFile: { viewModel.openFile(message, attachmentId: $0) },
            onFocusReply: { viewModel.focusReply($0) },
            onForward: { viewModel.requestForward(message) },
            onDelete: { viewModel.requestDelete(message) },
            onEdit: state.canEdit ? { viewModel.beginEdit(message) } : nil,
            allowsReply: state.canWrite,
            allowsReactions: state.reacts,
            quickReactions: state.reacts ? state.quickReactions : ReactionPalette.fallback,
            onMoreReactions: state.reacts ? { viewModel.showMoreReactions(message) } : nil,
            onReactionUsers: state.reacts && state.showsReactionUsers ? { viewModel.showReactionUsers(message) } : nil,
            uploadProgress: state.uploadProgress,
            onCancelUpload: { Task { await viewModel.cancelUpload(message) } },
            roundPlayer: roundPlayer,
            onSaveToPhotos: state.savesToPhotos ? { viewModel.save(message, to: .photos) } : nil,
            onSaveToFiles: state.savesToFiles ? { viewModel.save(message, to: .files) } : nil,
            transcript: state.transcript,
            // В одной анимации с лентой: пузырь растёт и сжимается, а соседние строки
            // сдвигаются плавно, а не скачком после него.
            onTranscribe: state.canTranscribe ? {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { viewModel.toggleTranscript(message) }
            } : nil,
            onSeekVoice: { viewModel.seekVoice(message, to: $0) },
            onDoubleTap: state.reacts ? state.quickReaction.map { emoji in
                { Task { await viewModel.toggleReaction(messageId: message.id, emoji: emoji) } }
            } : nil,
            onPin: message.status == .sent && Int64(message.id) != nil && message.content.pin == nil
                ? { Task { await viewModel.pin(message) } }
                : nil,
            onMarkUnread: viewModel.canMarkUnread(message) ? { viewModel.requestMarkUnread(message) } : nil,
            onVote: { answerId in Task { await viewModel.vote(message, answerId: answerId) } },
            onButton: { button in press(button) }
        )
    }

    /// Кнопка бота: ссылка и копирование — здесь, нажатие боту и приложение — в модели.
    private func press(_ button: InlineButton) {
        let viewModel = viewModel
        let message = message
        if case .copy(let text) = button.action {
            guard !text.isEmpty else { return }
            UIPasteboard.general.string = text
            viewModel.announce("Скопировано")
            return
        }
        Task { await viewModel.press(button, in: message) }
    }

    /// Плеер, если в этом сообщении играет кружок.
    private var roundPlayer: AnyView? {
        guard let playback = state.roundPlayback else { return nil }
        let viewModel = viewModel
        let id = playback.id
        return AnyView(
            RoundVideoPlayer(url: playback.url) { viewModel.stopRound(id: id) }
                .id(playback)
        )
    }
}
