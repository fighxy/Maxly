import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

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
        /// Тип чата для «Сведений»: в группе там «Кем прочитано», в личном — «Прочитано».
        var chatType: ChatType
        /// Пункт «Сведения»: сообщение принято сервером.
        var showsInfo: Bool
        /// Режим выбора нескольких сообщений: касание отмечает, меню нет.
        var isSelecting = false
        var isSelected = false
        /// Пункт «Выбрать» и отметка в режиме выбора.
        var selectable = false
        /// Автор цитаты: в канале — его название, иначе автор из ленты (`TranscriptRow.replyAuthor`).
        var replyAuthor: String?
    }

    let state: Snapshot
    let viewModel: ChatViewModel
    let reveal: PrivateModeReveal
    var onAuthor: (Message) -> Void = { _ in }
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
                    withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { reveal.reveal(id) }
                }
            ) {
                if state.isSelecting {
                    selectableBubble
                } else {
                    bubble
                }
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
                // У заглушки меню нет: оно показало бы сообщение.
                .environment(\.messageMenuPresenter, nil)
            }
        }
    }

    /// Пузырь в режиме выбора: слева отметка, касание по всей строке отмечает или снимает,
    /// кнопки и меню пузыря не срабатывают.
    private var selectableBubble: some View {
        let selection = viewModel.selection
        let message = message
        return HStack(spacing: 8) {
            Image(systemName: state.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.app(.title3))
                .foregroundStyle(state.isSelected ? Color.maxlyAccent : Color.secondary)
                .opacity(state.selectable ? 1 : 0)
                .accessibilityHidden(true)
            bubble
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { selection.toggle(message) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(state.isSelected ? "Снять выбор" : "Выбрать")
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
            onRetry: { Task { await viewModel.actions.retry(id: message.id) } },
            onReply: { viewModel.composer.beginReply(to: message) },
            onReact: { emoji in Task { await viewModel.reactions.toggle(messageId: message.id, emoji: emoji) } },
            onComments: { viewModel.comments.open(message) },
            onOpen: { viewModel.attachments.presentMedia(message, startId: $0) },
            onVoice: { viewModel.voices.toggle(message) },
            onFile: { viewModel.attachments.openFile(message, attachmentId: $0) },
            onFocusReply: { viewModel.focusReply($0, from: message.id) },
            onForward: { viewModel.actions.requestForward(message) },
            onDelete: { viewModel.actions.requestDelete(message) },
            onEdit: state.canEdit ? { viewModel.composer.beginEdit(message) } : nil,
            allowsReply: state.canWrite,
            allowsReactions: state.reacts,
            quickReactions: state.reacts ? state.quickReactions : ReactionPalette.fallback,
            onMoreReactions: state.reacts ? { viewModel.reactions.showMore(message) } : nil,
            onReactionUsers: state.reacts && state.showsReactionUsers ? { viewModel.reactions.showUsers(message) } : nil,
            uploadProgress: state.uploadProgress,
            onCancelUpload: { Task { await viewModel.cancelUpload(message) } },
            roundPlayer: roundPlayer,
            onSaveToPhotos: state.savesToPhotos ? { viewModel.attachments.save(message, to: .photos) } : nil,
            onSaveToFiles: state.savesToFiles ? { viewModel.attachments.save(message, to: .files) } : nil,
            transcript: state.transcript,
            // В одной анимации с лентой: пузырь растёт и сжимается, а соседние строки
            // сдвигаются плавно, а не скачком после него.
            onTranscribe: state.canTranscribe ? {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { viewModel.transcripts.toggle(message) }
            } : nil,
            onSeekVoice: { viewModel.voices.seek(message, to: $0) },
            onDoubleTap: state.reacts ? state.quickReaction.map { emoji in
                { Task { await viewModel.reactions.toggle(messageId: message.id, emoji: emoji) } }
            } : nil,
            onPin: message.status == .sent && Int64(message.id) != nil && !message.content.isService
                ? { viewModel.pins.request(message) }
                : nil,
            onMarkUnread: viewModel.canMarkUnread(message) ? { viewModel.requestMarkUnread(message) } : nil,
            onInfo: state.showsInfo ? { [chatType = state.chatType] in viewModel.showMessageInfo(message, chatType: chatType) } : nil,
            onVote: message.content.poll.map(viewModel.polls.canVote(in:)) ?? false
                ? { answerId in Task { await viewModel.polls.vote(message, answerId: answerId) } } : nil,
            onCast: message.content.poll.map(viewModel.polls.canVote(in:)) ?? false
                ? { ids in Task { await viewModel.polls.castVotes(message, answerIds: ids) } } : nil,
            onButton: { button in press(button) },
            onAuthor: state.chatType == .group ? { onAuthor(message) } : nil,
            onSelect: state.selectable ? { [reduceMotion] in
                withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { viewModel.selection.begin(with: message) }
            } : nil,
            replyMedia: state.row.replyMedia,
            replyAuthor: state.replyAuthor,
            showsKeyboard: state.row.showsKeyboard
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
            RoundVideoPlayer(url: playback.url) { viewModel.attachments.stopRound(id: id) }
                .id(playback)
        )
    }
}

/// Общее для всех строк ленты, от чего зависит высота пузыря.
struct TranscriptLayoutStyle: Equatable {
    /// Ширина колонки пузыря (`Snapshot.maxWidth`).
    var maxWidth: CGFloat
    /// Группа: имена и аватары авторов.
    var showsAuthors: Bool
    /// Пост канала: строка комментариев под ним.
    var allowsComments: Bool
    /// Режим выбора: слева от пузыря отметка, сам пузырь уже.
    var isSelecting: Bool
    var privateMode: PrivateModeDisplay
    var dynamicTypeSize: DynamicTypeSize
    var font: AppFont
    var fontWeight: Int
    var textSize: TextSizeStep
    /// Анимодзи чата пришли: крупное эмодзи рисуется анимацией своего размера.
    var animojiCount: Int
}

/// Отпечаток высоты строки ленты: строка с соседями и всё из `Snapshot`, что меняет раскладку.
/// Ход голосового, загрузка, подсветка и пункты меню сюда не входят — высоту они не меняют.
struct TranscriptRowLayoutKey: Equatable {
    var row: TranscriptRow
    var style: TranscriptLayoutStyle
    /// Открыт касанием в приватном режиме: вместо заглушки настоящее сообщение.
    var isRevealed: Bool
    /// Расшифровка голосового раскрыта.
    var transcript: TranscriptPhase
    /// Кружок играет и крупнее.
    var roundPlaying: Bool
}
