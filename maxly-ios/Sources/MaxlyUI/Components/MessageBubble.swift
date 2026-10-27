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
    /// Профиль автора: отдельное действие имени и аватара.
    private let onAuthor: (() -> Void)?
    /// «Выбрать»: режим выбора нескольких сообщений. `nil` — пункта нет.
    private let onSelect: (() -> Void)?
    /// Фото или видео сообщения, на которое этот ответ: миниатюра в цитате. `nil` — без неё.
    private let replyMedia: ChatAttachment?

    /// Копия пузыря в меню долгого нажатия: только сам пузырь, без жестов.
    private var isMenuPreview = false
    /// Меню экрана чата; `nil` — системное контекстное меню.
    @Environment(\.messageMenuPresenter) private var menuPresenter
    /// Место пузыря на экране для меню. Ссылка, а не состояние: прокрутка его меняет каждый
    /// кадр, и пузырь не должен из-за этого перерисовываться.
    @State private var menuFrame = MenuFrame()
    /// Сдвиг пузыря при свайпе «ответить».
    @State private var swipe: CGFloat = 0
    /// Палец ведёт по дорожке голосового: горизонтальный жест — перемотка, не ответ.
    @State private var scrubbing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Обои за лентой: входящий пузырь светлой темы на них белый.
    @Environment(\.chatWallpaperHasImage) private var wallpaperHasImage
    /// Анимодзи чата: крупные эмодзи играют и без отметки сервера.
    @Environment(\.animojiCatalog) private var animojiCatalog
    @Environment(\.displayScale) private var displayScale
    @Environment(\.imageURLSizing) private var imageURLSizing
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
        onAuthor: (() -> Void)? = nil,
        onSelect: (() -> Void)? = nil,
        replyMedia: ChatAttachment? = nil
    ) {
        self.onAuthor = onAuthor
        self.onSelect = onSelect
        self.replyMedia = replyMedia
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
        if isMenuPreview {
            bubbleContent
        } else if let pin = message.content.pin {
            ServiceMessageNotice(pin: pin, onOpen: onFocusReply)
                .background(highlighted ? Color.maxlyAccent.opacity(0.12) : Color.clear)
        } else if let service = message.content.service {
            ServiceEventNotice(text: ServiceText.text(
                service, actorId: message.authorId, actorName: message.authorName, outgoing: isOutgoing
            ))
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
                if let keyboard = message.content.keyboard {
                    // Кнопки бота ровно по ширине пузыря.
                    KeyboardAttached(trailing: isOutgoing, spacing: InlineKeyboardView.spacing) {
                        pressableBubble
                        InlineKeyboardView(keyboard: keyboard) { button in onButton?(button) }
                            .disabled(onButton == nil)
                    }
                } else {
                    pressableBubble
                }
                if message.status == .failed {
                    Button("Не отправлено. Повторить", action: onRetry)
                        .font(.app(.caption2))
                        .foregroundStyle(.red)
                }
                if !reactionsInside {
                    ReactionChips(
                        messageId: message.id,
                        reactions: message.content.reactions,
                        trailing: isOutgoing,
                        interactive: allowsReactions,
                        onToggle: onReact
                    )
                }
            }
            .frame(maxWidth: bubbleWidth, alignment: isOutgoing ? .trailing : .leading)
            if !isOutgoing { Spacer(minLength: 40) }
        }
        .offset(x: swipe)
        .background(alignment: .trailing) { replyHint }
        .replySwipe(enabled: allowsReply, onChange: swipeChanged, onEnd: swipeEnded)
        // Между пузырями серии 2 pt (`rowSpacing` ленты), между сериями — 8.
        .padding(.top, group.joinsPrevious ? 0 : 6)
        // Пузырь с подложкой вспыхивает сам (`BubbleFlash`); стикер и крупные эмодзи без
        // подложки подсвечиваются полосой строки.
        .background(highlighted && standalone != nil ? Color.maxlyAccent.opacity(0.12) : Color.clear)
        .animation(MaxlyMotion.fade, value: highlighted)
        .messageMenu(enabled: menuPresenter != nil, onOpen: openMenu) {
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

    /// Пузырь с откликом на удержание. Сжатие — внутри рамки, по которой меню ставит копию
    /// пузыря: копия встаёт в настоящий размер.
    private var pressableBubble: some View {
        bubbleContent
            .modifier(PressFeedback(anchor: isOutgoing ? .trailing : .leading, enabled: menuPresenter != nil))
            .modifier(MenuFrameReader(frame: menuFrame, enabled: menuPresenter != nil))
    }

    /// Сам пузырь: стикер или эмодзи без подложки либо пузырь с подложкой.
    @ViewBuilder
    private var bubbleContent: some View {
        if let standalone {
            standaloneBody(standalone)
        } else {
            bubble
        }
    }

    /// Открыть фото или видео. Палец, открывший меню долгим нажатием, отпускается над тем же
    /// кадром — просмотр тогда не открывается.
    private func openMedia(_ id: String) {
        guard menuPresenter?.request == nil, Date().timeIntervalSince(menuFrame.openedAt) > 0.6 else { return }
        onOpen(id)
    }

    // MARK: Меню долгого нажатия

    /// Открыть меню: копия пузыря на его месте, реакции и пункты.
    private func openMenu() {
        guard let menuPresenter, menuFrame.rect.width > 0 else { return }
        menuFrame.openedAt = Date()
        var preview = self
        preview.isMenuPreview = true
        menuPresenter.present(MessageMenuRequest(
            id: message.id,
            frame: menuFrame.rect,
            isOutgoing: isOutgoing,
            reactions: allowsReactions ? quickReactions : nil,
            mine: message.content.reactions.mine,
            onReact: onReact,
            onMoreReactions: allowsReactions ? onMoreReactions : nil,
            primary: primaryMenuActions,
            more: moreMenuActions,
            preview: AnyView(preview)
        ))
    }

    /// Главные пункты в привычном порядке.
    private var primaryMenuActions: [MessageMenuAction] {
        var actions: [MessageMenuAction] = []
        if allowsReply { actions.append(MessageMenuAction("Ответить", systemImage: "arrowshape.turn.up.left", action: onReply)) }
        if let onEdit { actions.append(MessageMenuAction("Изменить", systemImage: "pencil", action: onEdit)) }
        if let onForward, message.status == .sent {
            actions.append(MessageMenuAction("Переслать", systemImage: "arrowshape.turn.up.right", action: onForward))
        }
        if hasText { actions.append(MessageMenuAction("Копировать", systemImage: "doc.on.doc") { copyText() }) }
        if let onInfo, message.status == .sent { actions.append(MessageMenuAction("Сведения", systemImage: "info.circle", action: onInfo)) }
        if let onDelete { actions.append(MessageMenuAction("Удалить", systemImage: "trash", destructive: true, action: onDelete)) }
        return actions
    }

    /// Остальное — под «Ещё…».
    private var moreMenuActions: [MessageMenuAction] {
        var actions: [MessageMenuAction] = []
        if allowsComments { actions.append(MessageMenuAction("Комментарии", systemImage: "bubble.left.and.bubble.right", action: onComments)) }
        if let onPin, message.status == .sent { actions.append(MessageMenuAction("Закрепить", systemImage: "pin", action: onPin)) }
        if let onSaveToPhotos { actions.append(MessageMenuAction("Сохранить в Фото", systemImage: "square.and.arrow.down", action: onSaveToPhotos)) }
        if let onSaveToFiles { actions.append(MessageMenuAction("Сохранить в Файлы", systemImage: "folder", action: onSaveToFiles)) }
        if let onMarkUnread { actions.append(MessageMenuAction("Пометить непрочитанным", systemImage: "envelope.badge", action: onMarkUnread)) }
        if allowsReactions, let onReactionUsers, !message.content.reactions.isEmpty {
            actions.append(MessageMenuAction("Кто отреагировал", systemImage: "person.2", action: onReactionUsers))
        }
        if let onSelect { actions.append(MessageMenuAction("Выбрать", systemImage: "checkmark.circle", action: onSelect)) }
        return actions
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
                        .font(.app(.subheadline, .medium))
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
                authorAction { Text(authorTitle) }
                    .font(.app(.subheadline, .semibold))
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
                case .emoji(let emoji, _):
                    let font = ChatContentFormat.bigEmojiSize(count: emoji.count)
                    // Каждое эмодзи со своей анимацией играет (по отметке или каталогу), остальные — буквой.
                    let lotties = AnimojiText.bigEmoji(
                        text: message.text, emoji: emoji, spans: message.content.formatting ?? [], catalog: animojiCatalog
                    )
                    if lotties.contains(where: { $0 != nil }) {
                        let side: CGFloat = emoji.count == 1 ? 120 : emoji.count == 2 ? 88 : 72
                        HStack(spacing: 0) {
                            ForEach(Array(emoji.enumerated()), id: \.offset) { index, item in
                                if let url = lotties[index] {
                                    AnimatedSticker(lottieURL: url, stillURL: nil, size: side) {
                                        Text(item).font(.system(size: font))
                                    }
                                } else {
                                    Text(item).font(.system(size: font))
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
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
                .font(.app(.caption2).monospacedDigit())
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
            authorAction { AvatarView(
                title: authorTitle.isEmpty ? message.authorId : authorTitle,
                id: message.authorId,
                url: message.authorAvatarURL,
                size: Self.avatarSize
            ) }
        } else {
            Color.clear.frame(width: Self.avatarSize, height: Self.avatarSize)
        }
    }

    @ViewBuilder
    private func authorAction<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onAuthor {
            Button(action: onAuthor, label: content)
                .buttonStyle(.plain)
                .accessibilityLabel("Профиль: \(authorTitle)")
        } else {
            content()
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
                if layout.metadata == .text {
                    textMeta
                }
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
        // С кнопками бота пузырь берёт ширину, которую даёт `KeyboardAttached`: она не уже кнопок.
        .frame(minWidth: 64, maxWidth: message.content.keyboard == nil ? nil : .infinity, alignment: .leading)
        .background(fill, in: shape)
        .clipShape(shape)
        // Тень — под обрезанным пузырём, иначе форма срезала бы её.
        .background { wallpaperShadow }
        .overlay {
            BubbleFlash(active: highlighted, shape: shape, tint: quoteTint)
        }
        .overlay {
            if let uploadProgress {
                UploadRing(progress: uploadProgress, onCancel: onCancelUpload)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// На фото-обоях пузырь с подложкой отделён от пёстрого фона лёгкой тенью. На встроенных
    /// обоях тени нет.
    @ViewBuilder
    private var wallpaperShadow: some View {
        if wallpaperHasImage, hasFill {
            shape
                .fill(fill)
                .shadow(color: .black.opacity(0.14), radius: 1.5, x: 0, y: 0.5)
        }
    }

    @ViewBuilder
    private var header: some View {
        let name = showsAuthorName && !authorTitle.isEmpty
        if name || message.content.reply != nil || message.content.forward != nil {
            VStack(alignment: .leading, spacing: 4) {
                // Сначала кто прислал в группу, под ним — от кого переслано.
                if name {
                    authorAction { Text(authorTitle) }
                        .font(.app(.subheadline, .semibold))
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
            onOpen: openMedia,
            onDoubleTap: onDoubleTap
        )
        .padding(.horizontal, inset)
        .padding(.top, hasHeader ? 0 : inset)
        .padding(.bottom, hasText ? 0 : inset)
    }

    // MARK: Текст

    /// Текст: под время в конце текста оставлено невидимое место, чтобы короткая строка не
    /// переносила его на отдельную строку. Само время — `textMeta` в углу колонки.
    private var textBody: some View {
        // Без системного выделения: долгое нажатие открывает меню сообщения, а системная
        // плашка «Скопировать / Поделиться» проскакивала поверх него. Копирование — в меню.
        MessageTextView(
            text: message.displayText,
            spans: message.content.formatting ?? [],
            outgoing: isOutgoing,
            trailingSpace: layout.metadata == .text ? metaReserve : nil
        )
        .padding(.horizontal, 12)
        .padding(.top, hasHeader || !visuals.isEmpty ? 5 : 7)
        .padding(.bottom, textBottomPadding)
    }

    /// Время в правом нижнем углу текста, у правого края пузыря: на последней строке, в
    /// оставленном под него месте. Ширину пузыря не задаёт — текст меряется по своей ширине,
    /// и пузырь с цитатой или голосовым не растягивается на всю ленту из-за текста.
    private var textMeta: some View {
        meta
            .padding(.trailing, 12)
            .padding(.bottom, textBottomPadding)
            .bubbleCorner()
    }

    private var textBottomPadding: CGFloat {
        reactionsInside ? 4 : 6
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

    /// Реакции и время в одной раскладке: время в правом нижнем углу последнего ряда или
    /// своей строкой, а высота ряда — все ряды плашек. Строка комментариев всегда ниже.
    private var reactionsRow: some View {
        ReactionChips(
            messageId: message.id,
            reactions: message.content.reactions,
            interactive: allowsReactions,
            onOutgoing: isOutgoing,
            meta: timeInReactions ? AnyView(meta.padding(.bottom, 2)) : nil,
            onToggle: onReact
        )
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
        return reserve.font(.app(.caption2))
    }

    private var meta: some View {
        HStack(spacing: 3) {
            if isEdited {
                Text("изм.")
                    .font(.app(.caption2))
                    .lineLimit(1)
            }
            Text(ChatContentFormat.time(message.timestamp))
                .font(.app(.caption2).monospacedDigit())
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
                .transition(.opacity)
                .accessibilityLabel("Отправляется")
        case .sent:
            // Часы сменяются галочкой, которая прорисовывается; вторая галочка «прочитано» — тоже.
            DeliveryChecks(read: message.isRead)
                .transition(.maxlyCheckDraw(reduceMotion: reduceMotion))
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
                        .font(.app(.subheadline, .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(textColor)
                    Text(ChatContentFormat.fileSize(file.size))
                        .font(.app(.caption))
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
                .font(.app(.caption))
                .foregroundStyle(isOutgoing ? Color.maxlyOutgoingAccent : Color.maxlyAccent)
            Text(forward.authorName)
                .font(.app(.subheadline, .semibold))
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
            HStack(spacing: 8) {
                if let url = replyMedia.flatMap(replyThumbnailURL) {
                    RemoteImage(url: url, maxPixel: Int(Self.replyThumbnail * 3)) {
                        quoteTint.opacity(0.2)
                    }
                    .frame(width: Self.replyThumbnail, height: Self.replyThumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(reply.authorName)
                        .font(.app(.subheadline, .semibold))
                        .foregroundStyle(quoteTint)
                        .lineLimit(1)
                    quotePreview(reply)
                        .font(.app(.subheadline))
                        .lineLimit(1)
                        .foregroundStyle(textColor.opacity(0.85))
                }
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

    private static let replyThumbnail: CGFloat = 34

    /// Текст цитаты; перед ним значок вида исходного сообщения, кроме текста.
    private func quotePreview(_ reply: MessageReply) -> Text {
        let symbol: String? = switch reply.kind {
        case .voice: "mic.fill"
        case .photo: "photo.fill"
        case .video: "video.fill"
        case .file: "doc.fill"
        case .text: nil
        }
        guard let symbol else { return Text(reply.preview) }
        return Text(Image(systemName: symbol)) + Text(verbatim: " ") + Text(reply.preview)
    }

    /// Миниатюра цитаты: фото — уменьшенным адресом ядра, видео — его обложкой.
    private func replyThumbnailURL(_ item: ChatAttachment) -> URL? {
        if let photo = item.photo, photo.localPath == nil {
            return ImageURLRequests.url(
                photo.url, shape: .square, pointSize: Self.replyThumbnail, scale: displayScale,
                fullScreen: false, sizing: imageURLSizing
            )
        }
        return item.photo?.displayURL ?? item.video?.displayURL
    }

    // MARK: Цвета

    private var isEdited: Bool {
        message.content.edited == true
    }

    private var hasText: Bool {
        layout.hasText
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
        return wallpaperHasImage ? Color.maxlyIncomingOnWallpaper : Color.maxlyIncoming
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
            .font(.app(.footnote, .semibold))
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

/// Ответы опроса. Нажатие отправляет голос, если экран передал `onVote` и голосовать можно.
/// После голоса — проценты, полоса доли и галочка у своих ответов.
struct PollChoices: View {
    let poll: PollContent
    let outgoing: Bool
    let onVote: ((String) -> Void)?
    var onCast: (([String]) -> Void)? = nil
    @State private var picked: Set<String> = []
    /// Голос отправлен, ответ сервера ещё не пришёл: второе нажатие ничего не шлёт.
    @State private var sent = false

    /// Ответы можно нажимать.
    var interactive: Bool {
        guard poll.canVote, !sent else { return false }
        return poll.multiple ? onCast != nil : onVote != nil
    }

    private var primary: Color { outgoing ? Color.maxlyOutgoingText : Color.primary }
    private var secondary: Color { outgoing ? Color.maxlyOutgoingSecondary : Color.secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(poll.title)
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(primary)
            ForEach(poll.answers, id: \.id) { answer in
                Button {
                    guard interactive else { return }
                    if poll.multiple {
                        if picked.contains(answer.id) { picked.remove(answer.id) } else { picked.insert(answer.id) }
                    } else {
                        sent = true
                        onVote?(answer.id)
                    }
                } label: {
                    row(answer)
                }
                .buttonStyle(.plain)
                .disabled(!interactive)
                .accessibilityAddTraits(poll.isMine(answer.id) ? .isSelected : [])
            }
            if poll.multiple, interactive {
                Button("Голосовать") {
                    sent = true
                    onCast?(Array(picked))
                }
                .font(.app(.subheadline, .semibold))
                .frame(minHeight: 44)
                .disabled(picked.isEmpty)
            }
            Text(poll.total == 1 ? "1 голос" : "\(poll.total) голосов")
                .font(.app(.caption))
                .foregroundStyle(secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Опрос, \(poll.title)")
        .onChange(of: poll) { _, _ in
            sent = false
            if !poll.canVote { picked = [] }
        }
    }

    @ViewBuilder
    private func row(_ answer: PollAnswer) -> some View {
        let mine = poll.isMine(answer.id)
        let results = poll.showsResults
        let share = Double(poll.percent(of: answer)) / 100
        HStack(spacing: 8) {
            if mine {
                Image(systemName: "checkmark.circle.fill")
                    .font(.app(.subheadline))
                    .foregroundStyle(primary)
                    .accessibilityLabel("Ваш ответ")
            } else if poll.multiple, interactive {
                Image(systemName: picked.contains(answer.id) ? "checkmark.circle.fill" : "circle")
                    .font(.app(.subheadline))
                    .foregroundStyle(secondary)
            }
            Text(answer.text)
                .font(.app(.subheadline, mine ? .semibold : .regular))
                .foregroundStyle(primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(results ? "\(poll.percent(of: answer))%" : "\(answer.votes)")
                .font(.app(.caption).monospacedDigit())
                .foregroundStyle(secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(primary.opacity(picked.contains(answer.id) ? 0.28 : 0.12))
                if results {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(primary.opacity(mine ? 0.22 : 0.12))
                            .frame(width: proxy.size.width * share)
                    }
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityValue(results ? "\(poll.percent(of: answer)) процентов, \(answer.votes)" : "")
    }
}

/// Место пузыря на экране для меню долгого нажатия.
final class MenuFrame {
    var rect: CGRect = .zero
    /// Когда это меню открылось: отпущенный после долгого нажатия палец ничего не открывает.
    var openedAt: Date = .distantPast
}

/// Запоминает место пузыря, только когда меню экрана чата есть.
private struct MenuFrameReader: ViewModifier {
    let frame: MenuFrame
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.rect = $0 }
        } else {
            content
        }
    }
}

extension View {
    /// Долгое нажатие: меню (`MessageMenuPresenter`) или системное меню.
    @ViewBuilder
    func messageMenu<Items: View>(enabled: Bool, onOpen: @escaping () -> Void, @ViewBuilder items: () -> Items) -> some View {
        if enabled {
            simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in onOpen() })
                .accessibilityAction(named: Text("Действия"), onOpen)
        } else {
            contextMenu { items() }
        }
    }
}

/// Пока палец держит пузырь, тот чуть сжимается к своему краю; меню открывает долгое нажатие
/// (`messageMenu`). Касание отслеживает распознаватель UIKit, который распознаётся вместе с
/// прокруткой ленты и ничего не задерживает. Жест SwiftUI с состоянием нажатия
/// (`LongPressGesture.updating`) забирал касание с первого же прикосновения, и лента не
/// прокручивалась, если палец начинал жест на пузыре. На iOS 17 и с «Уменьшением движения»
/// пузырь не сжимается.
private struct PressFeedback: ViewModifier {
    let anchor: UnitPoint
    let enabled: Bool
    @State private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        if #available(iOS 18.0, *) {
            if enabled, !reduceMotion {
                content
                    .scaleEffect(pressing ? 0.96 : 1, anchor: anchor)
                    .animation(pressing ? .easeOut(duration: 0.25) : MaxlyMotion.quick(reduceMotion: false), value: pressing)
                    .gesture(PressRecognizer { pressing = $0 })
            } else {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if canImport(UIKit)
/// Удержание пальца на пузыре для `PressFeedback`: начинается через 0,1 с без движения, пускает
/// касания дальше без задержки и распознаётся вместе с любыми другими жестами — прокруткой
/// ленты, меню, двойным нажатием, свайпом ответа и кнопками внутри пузыря.
@available(iOS 18.0, *)
private struct PressRecognizer: UIGestureRecognizerRepresentable {
    /// `true` — палец держит пузырь, `false` — отпустил или повёл ленту.
    let onPressing: (Bool) -> Void

    /// Сдвиг пальца, после которого это уже прокрутка, а не удержание.
    private static let slop: CGFloat = 10

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = 0.1
        press.allowableMovement = Self.slop
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delaysTouchesEnded = false
        press.delegate = context.coordinator
        return press
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = recognizer.location(in: recognizer.view)
        switch recognizer.state {
        case .began:
            context.coordinator.start = point
            onPressing(true)
        case .changed:
            let start = context.coordinator.start
            if hypot(point.x - start.x, point.y - start.y) > Self.slop { onPressing(false) }
        default:
            onPressing(false)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var start: CGPoint = .zero

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif

/// Вспышка пузыря при переходе к нему (цитата, упоминание, закреп): заливка его формы дважды
/// проявляется и гаснет за 1,2 с — столько держится подсветка (`ChatViewModel.focus`). Вспышка
/// идёт и у ячейки, которая появилась уже подсвеченной. С «Уменьшением движения» — одно мягкое
/// проявление без второго импульса.
private struct BubbleFlash<S: Shape>: View {
    let active: Bool
    let shape: S
    let tint: Color
    @State private var pulses = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var peak: Double { reduceMotion ? 0.25 : 0.3 }
    private var dip: Double { reduceMotion ? 0.25 : 0.1 }

    var body: some View {
        let peak = peak
        let dip = dip
        return shape
            .fill(tint)
            .keyframeAnimator(initialValue: 0.0, trigger: pulses) { content, opacity in
                content.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(peak, duration: 0.15)
                    LinearKeyframe(dip, duration: 0.3)
                    LinearKeyframe(peak, duration: 0.2)
                    LinearKeyframe(0, duration: 0.55)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { if active { pulses += 1 } }
            .onChange(of: active) { _, now in if now { pulses += 1 } }
    }
}
