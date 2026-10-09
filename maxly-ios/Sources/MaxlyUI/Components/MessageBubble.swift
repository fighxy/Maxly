import SwiftUI
import MaxlyDomain
import MaxlyPresentation
#if canImport(UIKit)
import UIKit
#endif

/// Пузырь сообщения ленты.
///
/// Раскладка как в привычных мессенджерах: имя автора (в группах, цветом автора) и цитата
/// сверху, медиа во всю ширину пузыря, голосовые и файлы строками, текст с временем и
/// отметкой доставки в правом нижнем углу. Сообщение только из медиа рисуется без подложки,
/// время лежит на картинке. Пузыри одного автора подряд слипаются: у склеенной стороны
/// угол меньше.
public struct MessageBubble: View {
    private let message: Message
    private let layout: MessageBubbleLayout
    private let isOutgoing: Bool
    private let maxWidth: CGFloat
    private let phase: VoicePhase
    private let allowsComments: Bool
    private let highlighted: Bool
    private let showsAuthorName: Bool
    private let showsAuthorAvatar: Bool
    private let reservesAvatar: Bool
    private let group: BubbleGroup
    private let loadingId: String?
    private let commentCount: Int?
    private let onRetry: () -> Void
    private let onReply: () -> Void
    private let onReact: (String) -> Void
    private let onComments: () -> Void
    private let onOpen: (String) -> Void
    private let onVoice: () -> Void
    private let onFile: (String) -> Void
    private let onFocusReply: (String) -> Void
    private let onForward: (() -> Void)?
    private let onDelete: (() -> Void)?
    private let onEdit: (() -> Void)?
    /// «Сохранить в Фото» (фото и видео) и «Сохранить в Файлы» (любые вложения).
    private let onSaveToPhotos: (() -> Void)?
    /// Расшифровка голосового: состояние кнопки «→T» и действие (`nil` — кнопки нет).
    private let transcript: TranscriptPhase
    private let onTranscribe: (() -> Void)?
    /// Перемотка голосового по дорожке (доля 0…1).
    private let onSeekVoice: ((Double) -> Void)?
    private let onSaveToFiles: (() -> Void)?
    /// «Ответить» и свайп ответа есть, только если в чат можно писать.
    private let allowsReply: Bool
    /// Реакции можно ставить: сообщение принято сервером. Иначе плашки только видны.
    private let allowsReactions: Bool
    /// Быстрый ряд реакций в меню.
    private let quickReactions: [String]
    /// «Ещё реакции…»: полный выбор. `nil` — пункта нет.
    private let onMoreReactions: (() -> Void)?
    /// «Кто отреагировал». `nil` — пункта нет.
    private let onReactionUsers: (() -> Void)?
    /// Доля загрузки своих вложений; `nil` — не грузится.
    private let uploadProgress: Double?
    /// Крестик на кольце загрузки. `nil` — отменить нельзя.
    private let onCancelUpload: (() -> Void)?
    /// Плеер кружка, играющего в ленте.
    private let roundPlayer: AnyView?
    /// Двойное нажатие ставит выбранную быструю реакцию. `nil` — жест не вешается.
    private let onDoubleTap: (() -> Void)?
    /// Закрепить сообщение. `nil` — пункта нет.
    private let onPin: (() -> Void)?
    /// Пометить чат непрочитанным с этого сообщения. `nil` — пункта нет.
    private let onMarkUnread: (() -> Void)?
    /// «Сведения»: когда отправлено, изменено, кем прочитано. `nil` — пункта нет.
    private let onInfo: (() -> Void)?
    /// Голос в опросе: id ответа.
    private let onVote: ((String) -> Void)?
    private let onCast: (([String]) -> Void)?
    /// Нажатие inline-кнопки бота. `nil` — кнопки видны, но не нажимаются.
    private let onButton: ((InlineButton) -> Void)?
    /// «Выбрать»: режим выбора нескольких сообщений. `nil` — пункта нет.
    private let onSelect: (() -> Void)?

    /// Сдвиг пузыря при свайпе «ответить».
    @State private var swipe: CGFloat = 0
    /// Палец ведёт по дорожке голосового: горизонтальный жест — перемотка, не ответ.
    @State private var scrubbing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Обои за лентой: входящий пузырь светлой темы на них белый.
    @Environment(\.chatWallpaper) private var wallpaper
    private static let replyThreshold: CGFloat = 56

    private static let radius: CGFloat = 18
    private static let joined: CGFloat = 6
    private static let avatarSize: CGFloat = 34
    /// Отступ медиа от края пузыря с подложкой.
    private static let mediaInset: CGFloat = 3

    public init(
        message: Message,
        isOutgoing: Bool,
        maxWidth: CGFloat = 280,
        phase: VoicePhase = .idle,
        allowsComments: Bool = false,
        highlighted: Bool = false,
        showsAuthorName: Bool = false,
        showsAuthorAvatar: Bool = false,
        reservesAvatar: Bool? = nil,
        group: BubbleGroup = .single,
        loadingId: String? = nil,
        commentCount: Int? = nil,
        onRetry: @escaping () -> Void = {},
        onReply: @escaping () -> Void = {},
        onReact: @escaping (String) -> Void = { _ in },
        onComments: @escaping () -> Void = {},
        onOpen: @escaping (String) -> Void = { _ in },
        onVoice: @escaping () -> Void = {},
        onFile: @escaping (String) -> Void = { _ in },
        onFocusReply: @escaping (String) -> Void = { _ in },
        onForward: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        allowsReply: Bool = true,
        allowsReactions: Bool = true,
        quickReactions: [String] = ReactionPalette.fallback,
        onMoreReactions: (() -> Void)? = nil,
        onReactionUsers: (() -> Void)? = nil,
        uploadProgress: Double? = nil,
        onCancelUpload: (() -> Void)? = nil,
        roundPlayer: AnyView? = nil,
        onSaveToPhotos: (() -> Void)? = nil,
        onSaveToFiles: (() -> Void)? = nil,
        transcript: TranscriptPhase = .collapsed,
        onTranscribe: (() -> Void)? = nil,
        onSeekVoice: ((Double) -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil,
        onPin: (() -> Void)? = nil,
        onMarkUnread: (() -> Void)? = nil,
        onInfo: (() -> Void)? = nil,
        onVote: ((String) -> Void)? = nil,
        onCast: (([String]) -> Void)? = nil,
        onButton: ((InlineButton) -> Void)? = nil,
        onSelect: (() -> Void)? = nil
    ) {
        self.onSelect = onSelect
        self.message = message
        self.layout = MessageBubbleLayout(message: message, showsAuthorName: showsAuthorName, showsComments: allowsComments)
        self.isOutgoing = isOutgoing
        self.maxWidth = maxWidth
        self.phase = phase
        self.allowsComments = allowsComments
        self.highlighted = highlighted
        self.showsAuthorName = showsAuthorName
        self.showsAuthorAvatar = showsAuthorAvatar
        self.reservesAvatar = reservesAvatar ?? showsAuthorAvatar
        self.group = group
        self.loadingId = loadingId
        self.commentCount = commentCount
        self.onRetry = onRetry
        self.onReply = onReply
        self.onReact = onReact
        self.onComments = onComments
        self.onOpen = onOpen
        self.onVoice = onVoice
        self.onFile = onFile
        self.onFocusReply = onFocusReply
        self.onForward = onForward
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.onSaveToPhotos = onSaveToPhotos
        self.transcript = transcript
        self.onTranscribe = onTranscribe
        self.onSeekVoice = onSeekVoice
        self.onSaveToFiles = onSaveToFiles
        self.allowsReply = allowsReply
        self.allowsReactions = allowsReactions
        self.quickReactions = quickReactions
        self.onMoreReactions = onMoreReactions
        self.onReactionUsers = onReactionUsers
        self.uploadProgress = uploadProgress
        self.onCancelUpload = onCancelUpload
        self.roundPlayer = roundPlayer
        self.onDoubleTap = onDoubleTap
        self.onPin = onPin
        self.onMarkUnread = onMarkUnread
        self.onInfo = onInfo
        self.onVote = onVote
        self.onCast = onCast
        self.onButton = onButton
    }

    public var body: some View {
        if let pin = message.content.pin {
            ServiceMessageNotice(pin: pin, onOpen: onFocusReply)
                .background(highlighted ? Color.maxlyAccent.opacity(0.12) : Color.clear)
        } else {
            messageRow
        }
    }

    private var messageRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isOutgoing { Spacer(minLength: 40) }
            if !isOutgoing, reservesAvatar {
                authorMark
            }
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                if let standalone {
                    standaloneBody(standalone)
                } else {
                    bubble
                }
                if message.status == .failed {
                    Button("Не отправлено. Повторить", action: onRetry)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if !reactionsInside {
                    ReactionChips(
                        reactions: message.content.reactions,
                        trailing: isOutgoing,
                        interactive: allowsReactions,
                        onToggle: onReact
                    )
                }
                if let keyboard = message.content.keyboard {
                    InlineKeyboardView(keyboard: keyboard) { button in onButton?(button) }
                        .disabled(onButton == nil)
                }
            }
            .frame(maxWidth: bubbleWidth, alignment: isOutgoing ? .trailing : .leading)
            if !isOutgoing { Spacer(minLength: 40) }
        }
        .offset(x: swipe)
        .background(alignment: .trailing) { replyHint }
        .replySwipe(enabled: allowsReply, onChange: swipeChanged, onEnd: swipeEnded)
        .padding(.top, group.joinsPrevious ? 0 : 4)
        .background(highlighted ? Color.maxlyAccent.opacity(0.12) : Color.clear)
        .animation(MaxlyMotion.fade, value: highlighted)
        .contextMenu {
            if allowsReactions {
                reactionMenu
            }
            if allowsReply {
                Button("Ответить", systemImage: "arrowshape.turn.up.left", action: onReply)
            }
            if hasText {
                Button("Копировать", systemImage: "doc.on.doc") { copyText() }
            }
            if allowsComments {
                Button("Комментарии", systemImage: "bubble.left.and.bubble.right", action: onComments)
            }
            if let onSaveToPhotos {
                Button("Сохранить в Фото", systemImage: "square.and.arrow.down", action: onSaveToPhotos)
            }
            if let onSaveToFiles {
                Button("Сохранить в Файлы", systemImage: "folder", action: onSaveToFiles)
            }
            if let onEdit {
                Button("Изменить", systemImage: "pencil", action: onEdit)
            }
            if let onForward, message.status == .sent {
                Button("Переслать", systemImage: "arrowshape.turn.up.right", action: onForward)
            }
            if let onPin, message.status == .sent {
                Button("Закрепить", systemImage: "pin", action: onPin)
            }
            if let onMarkUnread {
                Button("Пометить непрочитанным", systemImage: "envelope.badge", action: onMarkUnread)
            }
            if let onInfo, message.status == .sent {
                Button("Сведения", systemImage: "info.circle", action: onInfo)
            }
            if let onSelect {
                Button("Выбрать", systemImage: "checkmark.circle", action: onSelect)
            }
            if let onDelete {
                Divider()
                Button("Удалить", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .modifier(QuickDoubleTap(action: onDoubleTap))
    }

    // MARK: Реакции

    /// Верх меню сообщения: ряд быстрых реакций (своя отмечена), затем «Убрать»,
    /// «Ещё реакции…» и «Кто отреагировал».
    @ViewBuilder
    private var reactionMenu: some View {
        let mine = message.content.reactions.mine
        Picker("Реакция", selection: Binding(
            get: { mine ?? "" },
            set: { emoji in if !emoji.isEmpty { onReact(emoji) } }
        )) {
            ForEach(quickReactions, id: \.self) { emoji in
                Text(emoji)
                    .tag(emoji)
                    .accessibilityLabel(emoji == mine ? "\(emoji), ваша реакция" : emoji)
            }
        }
        .pickerStyle(.palette)
        if let mine {
            Button("Убрать реакцию", systemImage: "heart.slash") { onReact(mine) }
        }
        if let onMoreReactions {
            Button("Ещё реакции…", systemImage: "face.smiling", action: onMoreReactions)
        }
        if let onReactionUsers, !message.content.reactions.isEmpty {
            Button("Кто отреагировал", systemImage: "person.2", action: onReactionUsers)
        }
        Divider()
    }

    // MARK: Ответ свайпом

    /// Свайп влево по пузырю — ответить (`ReplySwipe`: вертикальную прокрутку не трогает).
    private func swipeChanged(_ dx: CGFloat) {
        guard !scrubbing else { return }
        let pulled = min(max(-dx, 0), Self.replyThreshold * 1.4)
        if swipe > -Self.replyThreshold, pulled >= Self.replyThreshold {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
        swipe = -pulled
    }

    private func swipeEnded() {
        let reply = !scrubbing && swipe <= -Self.replyThreshold
        withAnimation(.spring(duration: 0.3)) { swipe = 0 }
        if reply { onReply() }
    }

    @ViewBuilder
    private var replyHint: some View {
        if swipe < 0 {
            let progress = min(1, -swipe / Self.replyThreshold)
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.maxlyAccent.opacity(0.4 + 0.6 * progress), in: Circle())
                .scaleEffect(0.6 + 0.4 * progress)
                .opacity(progress)
                .padding(.trailing, 4)
                .accessibilityHidden(true)
        }
    }

    // MARK: Комментарии

    /// Нижняя строка пузыря поста канала: число комментариев (или «Комментировать») и стрелка.
    private var commentsFooter: some View {
        let count = commentCount ?? message.content.comments?.count ?? 0
        return Button(action: onComments) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill((isOutgoing ? Color.maxlyOutgoingText : Color.primary).opacity(0.12))
                    .frame(height: 0.5)
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(ChatContentFormat.comments(count))
                        .font(.subheadline.weight(.medium))
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.6)
                }
                .foregroundStyle(isOutgoing ? Color.maxlyOutgoingAccent : Color.maxlyAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: count)
        .accessibilityLabel("\(ChatContentFormat.comments(count)), открыть")
    }

    // MARK: Стикеры и крупные эмодзи

    /// Сообщение без подложки: стикер или от одного до трёх эмодзи (одно анимодзи — Lottie).
    private var standalone: MessageBubbleLayout.Standalone? { layout.standalone }

    private static let stickerSize: CGFloat = 168

    @ViewBuilder
    private func standaloneBody(_ standalone: MessageBubbleLayout.Standalone) -> some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            if showsAuthorName, !authorTitle.isEmpty {
                Text(authorTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(authorColor)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            if let forward = message.content.forward {
                forwardLabel(forward)
                    .padding(8)
                    .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let reply = message.content.reply {
                quote(reply)
                    .padding(8)
                    .frame(maxWidth: 220, alignment: .leading)
                    .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Group {
                switch standalone {
                case .sticker(let sticker):
                    AnimatedSticker(lottieURL: sticker.lottieURL, stillURL: sticker.url, size: Self.stickerSize) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    }
                    .accessibilityLabel("Стикер")
                case .emoji(let emoji, let lottie):
                    let font = ChatContentFormat.bigEmojiSize(count: emoji.count)
                    if let lottie {
                        AnimatedSticker(lottieURL: lottie, stillURL: nil, size: 120) {
                            Text(emoji.joined()).font(.system(size: font))
                        }
                        .accessibilityLabel(emoji.joined())
                    } else {
                        Text(emoji.joined())
                            .font(.system(size: font))
                            .padding(.horizontal, 2)
                    }
                }
            }
            .padding(.bottom, 18)
            .overlay(alignment: .bottomTrailing) { chipMeta }
        }
        .overlay {
            if let uploadProgress {
                UploadRing(progress: uploadProgress, onCancel: onCancelUpload)
            }
        }
    }

    /// Время на полупрозрачной плашке под стикером.
    private var chipMeta: some View {
        HStack(spacing: 3) {
            Text(ChatContentFormat.time(message.timestamp))
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
            if isOutgoing {
                statusIcon
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.35), in: Capsule())
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: message.status)
        .accessibilityElement(children: .combine)
    }

    // MARK: Каркас

    private var bubbleWidth: CGFloat {
        let avatar = !isOutgoing && reservesAvatar ? Self.avatarSize + 6 : 0
        return max(140, maxWidth - avatar)
    }

    @ViewBuilder
    private var authorMark: some View {
        if showsAuthorAvatar {
            AvatarView(
                title: authorTitle.isEmpty ? message.authorId : authorTitle,
                id: message.authorId,
                url: message.authorAvatarURL,
                size: Self.avatarSize
            )
        } else {
            Color.clear.frame(width: Self.avatarSize, height: Self.avatarSize)
        }
    }

    private var shape: UnevenRoundedRectangle {
        let big = Self.radius
        let small = Self.joined
        // Сторона автора сужается на стыках; свободный край завершает серию.
        let topAuthor = group.joinsPrevious ? small : big
        let bottomAuthor: CGFloat = group.joinsNext ? small : 10
        if isOutgoing {
            return UnevenRoundedRectangle(
                topLeadingRadius: big,
                bottomLeadingRadius: big,
                bottomTrailingRadius: bottomAuthor,
                topTrailingRadius: topAuthor,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: topAuthor,
            bottomLeadingRadius: bottomAuthor,
            bottomTrailingRadius: big,
            topTrailingRadius: big,
            style: .continuous
        )
    }

    private var bubble: some View {
        BubbleColumn {
            header
            if !visuals.isEmpty {
                media
            }
            ForEach(message.content.voices, id: \.id) { voice in
                VoiceMessageView(
                    voice: voice,
                    phase: phase,
                    outgoing: isOutgoing,
                    time: layout.metadata == .voice(voice.id) ? AnyView(meta) : nil,
                    transcript: transcript,
                    onTranscribe: onTranscribe,
                    onToggle: onVoice,
                    onSeek: onSeekVoice,
                    onScrubbing: { active in
                        scrubbing = active
                        // Свайп ответа мог начаться в том же касании: пузырь возвращается на место.
                        if active, swipe != 0 { withAnimation(.spring(duration: 0.3)) { swipe = 0 } }
                    }
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            ForEach(message.content.files, id: \.id) { file in
                fileRow(file)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            ForEach(message.content.contacts, id: \.id) { contact in
                ContactCardRow(contact: contact, outgoing: isOutgoing)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            if let poll = message.content.poll {
                PollChoices(poll: poll, outgoing: isOutgoing, onVote: onVote, onCast: onCast)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            ForEach(message.content.calls, id: \.id) { call in
                // Время звонка — в его строке, как у голосового; при тексте или реакциях
                // оно уходит туда.
                CallBubble(
                    call: call,
                    outgoing: isOutgoing,
                    time: layout.metadata == .call(call.id) ? AnyView(meta) : nil,
                    timeText: ChatContentFormat.time(message.timestamp)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            if hasText {
                textBody
            }
            if let preview = message.content.linkPreview {
                LinkPreviewCard(preview: preview, outgoing: isOutgoing, textColor: textColor)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
            if layout.metadata == .footer {
                HStack {
                    Spacer(minLength: 0)
                    meta
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
            if reactionsInside {
                reactionsRow
            }
            if showsComments {
                commentsFooter
            }
        }
        .frame(minWidth: 64, alignment: .leading)
        .background(fill, in: shape)
        .clipShape(shape)
        .overlay {
            if let uploadProgress {
                UploadRing(progress: uploadProgress, onCancel: onCancelUpload)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var header: some View {
        let name = showsAuthorName && !authorTitle.isEmpty
        if name || message.content.reply != nil || message.content.forward != nil {
            VStack(alignment: .leading, spacing: 4) {
                // Сначала кто прислал в группу, под ним — от кого переслано.
                if name {
                    Text(authorTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(authorColor)
                        .lineLimit(1)
                }
                if let forward = message.content.forward {
                    forwardLabel(forward)
                }
                if let reply = message.content.reply {
                    quote(reply)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, visuals.isEmpty ? 0 : 6)
        }
    }

    // MARK: Медиа

    private var visuals: [ChatAttachment] { message.content.visuals }

    private var media: some View {
        let inset = hasFill ? Self.mediaInset : 0
        return MediaMosaic(
            attachments: visuals,
            maxWidth: bubbleWidth - inset * 2,
            time: layout.metadata == .media ? ChatContentFormat.time(message.timestamp) : nil,
            status: isOutgoing ? message.status : nil,
            isRead: message.isRead,
            cornerRadius: hasFill ? Self.radius - inset : Self.radius,
            loadingId: loadingId,
            fillsWidth: hasFill,
            roundPlayer: roundPlayer,
            onOpen: onOpen,
            onDoubleTap: onDoubleTap
        )
        .padding(.horizontal, inset)
        .padding(.top, hasHeader ? 0 : inset)
        .padding(.bottom, hasText ? 0 : inset)
    }

    // MARK: Текст

    /// Текст с временем в правом нижнем углу: под время в конце текста оставлено невидимое место,
    /// чтобы короткая строка не переносила его на отдельную строку.
    private var textBody: some View {
        ZStack(alignment: .bottomTrailing) {
            MessageTextView(
                text: message.displayText,
                spans: message.content.formatting ?? [],
                outgoing: isOutgoing,
                trailingSpace: layout.metadata == .text ? metaReserve : nil
            )
            .textSelection(.enabled)
            if layout.metadata == .text {
                meta
            }
        }
        // Рядом с медиа, голосовым или файлом пузырь уже широкий: время уходит к его правому краю.
        .frame(maxWidth: stretchesText ? .infinity : nil, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, hasHeader || !visuals.isEmpty ? 5 : 7)
        .padding(.bottom, reactionsInside ? 4 : 6)
    }

    // MARK: Реакции в пузыре

    /// Реакции лежат внутри пузыря, если у него есть подложка (фото без подписи — под ним).
    private var reactionsInside: Bool {
        layout.reactionsInside
    }

    /// Время переезжает из текста в ряд реакций, как в привычных мессенджерах, — и у
    /// голосового тоже: правый нижний угол пузыря один для всех сообщений.
    private var timeInReactions: Bool {
        layout.metadata == .reactions
    }

    private var reactionsRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ReactionChips(
                reactions: message.content.reactions,
                interactive: allowsReactions,
                onOutgoing: isOutgoing,
                onToggle: onReact
            )
            if timeInReactions {
                Spacer(minLength: 0)
                // Время не сжимается и не переносится: плашки переносятся в оставшейся ширине.
                meta
                    .fixedSize()
                    .layoutPriority(1)
                    .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, hasText ? 0 : 6)
        .padding(.bottom, 8)
    }

    /// Невидимое место под время в конце текста. Те же шрифт и цифры, что у `meta`, и
    /// место под галочки шире их самих: строка не заходит под время. Раньше место считалось
    /// пробелами без моноширинных цифр и было уже галочек — конец строки наезжал на время.
    private var metaReserve: Text {
        var reserve = Text(verbatim: "\u{2007}\u{2007}")
        if isEdited { reserve = reserve + Text(verbatim: "изм.\u{2007}") }
        reserve = reserve + Text(verbatim: ChatContentFormat.time(message.timestamp)).monospacedDigit()
        // Под галочки — видимые знаки (их прячет прозрачный цвет), а не пробелы: пробелы в конце
        // строки «висят» за её краем и не занимают места, и последнее слово заезжало под время.
        if isOutgoing { reserve = reserve + Text(verbatim: "\u{2007}000").monospacedDigit() }
        return reserve.font(.caption2)
    }

    private var meta: some View {
        HStack(spacing: 3) {
            if isEdited {
                Text("изм.")
                    .font(.caption2)
                    .lineLimit(1)
            }
            Text(ChatContentFormat.time(message.timestamp))
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
            if isOutgoing {
                statusIcon
            }
        }
        .foregroundStyle(metaColor)
        // Часы сменяются галочкой растворением, а не скачком.
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: message.status)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch message.status {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: DeliveryChecks.size.width)
                .accessibilityLabel("Отправляется")
        case .sent:
            DeliveryChecks(read: message.isRead)
                .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: message.isRead)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: DeliveryChecks.size.width)
                .accessibilityLabel("Не отправлено")
        }
    }

    // MARK: Файлы

    private func fileRow(_ file: FileContent) -> some View {
        let downloaded = file.fileURL != nil
        let loading = loadingId == file.id
        return Button { onFile(file.id) } label: {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().fill(isOutgoing ? Color.maxlyOutgoingAccent.opacity(0.15) : Color.maxlyAccent)
                    if loading {
                        ProgressView().tint(isOutgoing ? Color.maxlyOutgoingAccent : Color.maxlyOnAccent)
                    } else if downloaded {
                        Text(Self.fileBadge(file.name))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isOutgoing ? Color.maxlyOutgoingAccent : Color.maxlyOnAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(4)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(isOutgoing ? Color.maxlyOutgoingAccent : Color.maxlyOnAccent)
                    }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(textColor)
                    Text(ChatContentFormat.fileSize(file.size))
                        .font(.caption)
                        .foregroundStyle(metaColor)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Файл \(file.name), \(ChatContentFormat.fileSize(file.size))")
    }

    /// Расширение файла на значке: «PDF», «ZIP». Без расширения — «FILE».
    static func fileBadge(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.uppercased()
        return ext.isEmpty || ext.count > 5 ? "FILE" : ext
    }

    // MARK: Пересылка

    /// «Переслано от Имя» над содержимым, как в привычных мессенджерах.
    private func forwardLabel(_ forward: MessageForward) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Переслано от")
                .font(.caption)
                .foregroundStyle(isOutgoing ? Color.maxlyOutgoingAccent : Color.maxlyAccent)
            Text(forward.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOutgoing ? Color.maxlyOutgoingAccent : Color.maxlyAccent)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Цитата

    private func quote(_ reply: MessageReply) -> some View {
        Button {
            onFocusReply(reply.messageId)
        } label: {
            // Полоса — в overlay, чтобы её высота бралась из текста, а не растягивала цитату.
            VStack(alignment: .leading, spacing: 1) {
                Text(reply.authorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(quoteTint)
                    .lineLimit(1)
                Text(reply.preview)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(textColor.opacity(0.85))
            }
            .padding(.leading, 11)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(minWidth: 120, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(quoteTint)
                    .frame(width: 3)
            }
            .background(quoteTint.opacity(isOutgoing ? 0.22 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: Цвета

    private var isEdited: Bool {
        message.content.edited == true
    }

    private var hasText: Bool {
        layout.hasText
    }

    private var stretchesText: Bool {
        !visuals.isEmpty || !message.content.voices.isEmpty || !message.content.files.isEmpty
            || !message.content.contacts.isEmpty || !message.content.calls.isEmpty || showsComments
    }

    private var hasHeader: Bool {
        layout.hasHeader
    }

    private var authorTitle: String {
        message.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Медиа без подписи остаются без подложки; смешанное содержимое собирается в карточку.
    private var hasFill: Bool {
        layout.hasFill
    }

    private var fill: Color {
        guard hasFill else { return .clear }
        if isOutgoing { return Color.maxlyOutgoing }
        return wallpaper.hasImage ? Color.maxlyIncomingOnWallpaper : Color.maxlyIncoming
    }

    private var textColor: Color {
        isOutgoing ? .maxlyOutgoingText : .primary
    }

    private var metaColor: Color {
        isOutgoing ? Color.maxlyOutgoingSecondary : Color.secondary
    }

    private var authorColor: Color {
        AvatarPalette.nameColor(ChatAvatar.colorIndex(for: message.authorId))
    }

    private var quoteTint: Color {
        isOutgoing ? Color.maxlyOutgoingAccent : Color.maxlyAccent
    }

    private var showsComments: Bool {
        allowsComments
    }

    private func copyText() {
        #if canImport(UIKit)
        UIPasteboard.general.string = message.displayText
        #endif
    }
}

/// Заголовок дня между сообщениями: капсула на стекле по центру ленты.
public struct DaySeparator: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Двойное нажатие рядом с одиночным: фото по-прежнему открывается с первого касания.
struct QuickDoubleTap: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.simultaneousGesture(TapGesture(count: 2).onEnded(action))
        } else {
            content
        }
    }
}

/// Ответы опроса. Нажатие отправляет голос, если экран передал `onVote`.
private struct PollChoices: View {
    let poll: PollContent
    let outgoing: Bool
    let onVote: ((String) -> Void)?
    var onCast: (([String]) -> Void)? = nil
    @State private var picked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(poll.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(outgoing ? Color.maxlyOutgoingText : Color.primary)
            ForEach(poll.answers, id: \.id) { answer in
                Button {
                    if poll.multiple {
                        if picked.contains(answer.id) { picked.remove(answer.id) } else { picked.insert(answer.id) }
                    } else {
                        onVote?(answer.id)
                    }
                } label: {
                    HStack {
                        Text(answer.text)
                            .font(.subheadline)
                            .foregroundStyle(outgoing ? Color.maxlyOutgoingText : Color.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text("\(answer.votes)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(outgoing ? Color.maxlyOutgoingSecondary : Color.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background((outgoing ? Color.maxlyOutgoingText : Color.primary).opacity(picked.contains(answer.id) ? 0.28 : 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(poll.multiple ? onCast == nil : onVote == nil)
            }
            if poll.multiple, onCast != nil {
                Button("Голосовать") { onCast?(Array(picked)) }
                    .font(.subheadline.weight(.semibold))
                    .disabled(picked.isEmpty)
            }
            Text(poll.total == 1 ? "1 голос" : "\(poll.total) голосов")
                .font(.caption)
                .foregroundStyle(outgoing ? Color.maxlyOutgoingSecondary : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Опрос, \(poll.title)")
    }
}
