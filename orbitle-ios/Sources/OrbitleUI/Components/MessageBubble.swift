import SwiftUI
import OrbitleDomain
import OrbitlePresentation
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

    /// Сдвиг пузыря при свайпе «ответить».
    @State private var swipe: CGFloat = 0
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
        onCancelUpload: (() -> Void)? = nil
    ) {
        self.message = message
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
        self.allowsReply = allowsReply
        self.allowsReactions = allowsReactions
        self.quickReactions = quickReactions
        self.onMoreReactions = onMoreReactions
        self.onReactionUsers = onReactionUsers
        self.uploadProgress = uploadProgress
        self.onCancelUpload = onCancelUpload
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isOutgoing { Spacer(minLength: 40) }
            if !isOutgoing, reservesAvatar {
                authorMark
            }
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                bubble
                if message.status == .failed {
                    Button("Не отправлено. Повторить", action: onRetry)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                ReactionChips(
                    reactions: message.content.reactions,
                    trailing: isOutgoing,
                    interactive: allowsReactions,
                    onToggle: onReact
                )
            }
            .frame(maxWidth: bubbleWidth, alignment: isOutgoing ? .trailing : .leading)
            if !isOutgoing { Spacer(minLength: 40) }
        }
        .offset(x: swipe)
        .background(alignment: .trailing) { replyHint }
        .replySwipe(enabled: allowsReply, onChange: swipeChanged, onEnd: swipeEnded)
        .padding(.top, group.joinsPrevious ? 0 : 4)
        .background(highlighted ? Color.orbitleAccent.opacity(0.12) : Color.clear)
        .animation(.easeInOut(duration: 0.25), value: highlighted)
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
            if let onEdit {
                Button("Изменить", systemImage: "pencil", action: onEdit)
            }
            if let onForward, message.status == .sent {
                Button("Переслать", systemImage: "arrowshape.turn.up.right", action: onForward)
            }
            if let onDelete {
                Divider()
                Button("Удалить", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
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
        let pulled = min(max(-dx, 0), Self.replyThreshold * 1.4)
        if swipe > -Self.replyThreshold, pulled >= Self.replyThreshold {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
        swipe = -pulled
    }

    private func swipeEnded() {
        let reply = swipe <= -Self.replyThreshold
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
                .background(Color.orbitleAccent.opacity(0.4 + 0.6 * progress), in: Circle())
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
                    .fill((isOutgoing ? Color.white : Color.primary).opacity(0.12))
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
                .foregroundStyle(isOutgoing ? Color.white : Color.orbitleAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.default, value: count)
        .accessibilityLabel("\(ChatContentFormat.comments(count)), открыть")
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
        // Сторона хвоста (у своих справа, у чужих слева): низ всегда острее, верх — если
        // пузырь продолжает серию.
        let topTail = group.joinsPrevious ? small : big
        let bottomTail = small
        if isOutgoing {
            return UnevenRoundedRectangle(
                topLeadingRadius: big,
                bottomLeadingRadius: big,
                bottomTrailingRadius: bottomTail,
                topTrailingRadius: topTail,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: topTail,
            bottomLeadingRadius: bottomTail,
            bottomTrailingRadius: big,
            topTrailingRadius: big,
            style: .continuous
        )
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !visuals.isEmpty {
                media
            }
            ForEach(message.content.voices, id: \.id) { voice in
                VoiceMessageView(
                    voice: voice,
                    phase: phase,
                    outgoing: isOutgoing,
                    time: hasText ? nil : AnyView(meta),
                    onToggle: onVoice
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
            if hasText {
                textBody
            } else if visuals.isEmpty, message.content.voices.isEmpty {
                // Пустое сообщение, только файл или контакт: время отдельной строкой.
                if message.content.files.isEmpty, message.content.contacts.isEmpty {
                    Text(message.text.isEmpty ? " " : message.text)
                        .padding(.horizontal, 12)
                        .padding(.top, 7)
                }
                HStack {
                    Spacer(minLength: 0)
                    meta
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
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
                if let forward = message.content.forward {
                    forwardLabel(forward)
                }
                if name {
                    Text(authorTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(authorColor)
                        .lineLimit(1)
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
            time: hasText ? nil : ChatContentFormat.time(message.timestamp),
            status: isOutgoing ? message.status : nil,
            cornerRadius: hasFill ? Self.radius - inset : Self.radius,
            loadingId: loadingId,
            fillsWidth: hasFill,
            onOpen: onOpen
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
                trailingSpace: "\u{2007}\u{2007}" + metaPlaceholder
            )
            .textSelection(.enabled)
            meta
        }
        // Рядом с медиа, голосовым или файлом пузырь уже широкий: время уходит к его правому краю.
        .frame(maxWidth: stretchesText ? .infinity : nil, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, hasHeader || !visuals.isEmpty ? 5 : 7)
        .padding(.bottom, 6)
    }

    private var metaPlaceholder: String {
        let time = (isEdited ? "изм. " : "") + ChatContentFormat.time(message.timestamp)
        return isOutgoing ? time + "\u{2007}\u{2007}\u{2007}" : time
    }

    private var meta: some View {
        HStack(spacing: 3) {
            if isEdited {
                Text("изм.")
                    .font(.caption2)
            }
            Text(ChatContentFormat.time(message.timestamp))
                .font(.caption2.monospacedDigit())
            if isOutgoing {
                statusIcon
            }
        }
        .foregroundStyle(metaColor)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch message.status {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityLabel("Отправляется")
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .accessibilityLabel("Отправлено")
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
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
                    Circle().fill(isOutgoing ? Color.white.opacity(0.22) : Color.orbitleAccent)
                    if loading {
                        ProgressView().tint(.white)
                    } else if downloaded {
                        Text(Self.fileBadge(file.name))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(4)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
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
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.8) : Color.orbitleAccent.opacity(0.8))
            Text(forward.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOutgoing ? Color.white : Color.orbitleAccent)
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
                    .foregroundStyle(isOutgoing ? Color.white : quoteTint)
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
        !message.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var stretchesText: Bool {
        !visuals.isEmpty || !message.content.voices.isEmpty || !message.content.files.isEmpty
            || !message.content.contacts.isEmpty || showsComments
    }

    private var hasHeader: Bool {
        (showsAuthorName && !authorTitle.isEmpty) || message.content.reply != nil || message.content.forward != nil
    }

    private var authorTitle: String {
        message.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Подложка есть у всего, кроме сообщения только из фото и видео.
    private var hasFill: Bool {
        hasText || hasHeader || !message.content.voices.isEmpty || !message.content.files.isEmpty
            || !message.content.contacts.isEmpty || visuals.isEmpty
            || showsComments
    }

    private var fill: Color {
        guard hasFill else { return .clear }
        return isOutgoing ? Color.orbitleOutgoing : Color.orbitleIncoming
    }

    private var textColor: Color {
        isOutgoing ? .white : .primary
    }

    private var metaColor: Color {
        isOutgoing ? Color.white.opacity(0.75) : Color.secondary
    }

    private var authorColor: Color {
        AvatarPalette.nameColor(ChatAvatar.colorIndex(for: message.authorId))
    }

    private var quoteTint: Color {
        isOutgoing ? Color.white : Color.orbitleAccent
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
