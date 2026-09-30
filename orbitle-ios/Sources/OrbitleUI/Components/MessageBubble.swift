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
    private let onRetry: () -> Void
    private let onReply: () -> Void
    private let onReact: (String) -> Void
    private let onComments: () -> Void
    private let onOpen: (String) -> Void
    private let onVoice: () -> Void
    private let onFile: (String) -> Void
    private let onFocusReply: (String) -> Void

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
        onRetry: @escaping () -> Void = {},
        onReply: @escaping () -> Void = {},
        onReact: @escaping (String) -> Void = { _ in },
        onComments: @escaping () -> Void = {},
        onOpen: @escaping (String) -> Void = { _ in },
        onVoice: @escaping () -> Void = {},
        onFile: @escaping (String) -> Void = { _ in },
        onFocusReply: @escaping (String) -> Void = { _ in }
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
        self.onRetry = onRetry
        self.onReply = onReply
        self.onReact = onReact
        self.onComments = onComments
        self.onOpen = onOpen
        self.onVoice = onVoice
        self.onFile = onFile
        self.onFocusReply = onFocusReply
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
                ReactionChips(reactions: message.content.reactions, onToggle: onReact)
                if showsComments {
                    commentsButton
                }
            }
            .frame(maxWidth: bubbleWidth, alignment: isOutgoing ? .trailing : .leading)
            if !isOutgoing { Spacer(minLength: 40) }
        }
        .offset(x: swipe)
        .background(alignment: .trailing) { replyHint }
        .simultaneousGesture(replySwipe)
        .padding(.top, group.joinsPrevious ? 0 : 4)
        .background(highlighted ? Color.orbitleAccent.opacity(0.12) : Color.clear)
        .animation(.easeInOut(duration: 0.25), value: highlighted)
        .contextMenu {
            Button("Ответить", systemImage: "arrowshape.turn.up.left", action: onReply)
            if hasText {
                Button("Копировать", systemImage: "doc.on.doc") { copyText() }
            }
            Menu("Реакция") {
                ForEach(ReactionPalette.quick, id: \.self) { emoji in
                    Button(emoji) { onReact(emoji) }
                }
            }
            if allowsComments {
                Button("Комментарии", systemImage: "bubble.left.and.bubble.right", action: onComments)
            }
        }
    }

    // MARK: Ответ свайпом

    /// Свайп влево по пузырю — ответить. Вертикальная прокрутка ленты не мешает: жест
    /// срабатывает, только когда палец идёт в основном по горизонтали.
    private var replySwipe: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                guard dx < 0, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                let pulled = min(-dx, Self.replyThreshold * 1.4)
                if swipe > -Self.replyThreshold, pulled >= Self.replyThreshold {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
                swipe = -pulled
            }
            .onEnded { _ in
                let reply = swipe <= -Self.replyThreshold
                withAnimation(.spring(duration: 0.3)) { swipe = 0 }
                if reply { onReply() }
            }
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

    /// Плашка под постом канала: число комментариев (или «Комментировать») и стрелка.
    private var commentsButton: some View {
        Button(action: onComments) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(ChatContentFormat.comments(message.content.comments?.count ?? 0))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color.orbitleAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: bubbleWidth)
            .background(Color.orbitleIncoming, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Открыть комментарии")
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
            if hasText {
                textBody
            } else if visuals.isEmpty, message.content.voices.isEmpty {
                // Пустое сообщение или только файл: время отдельной строкой.
                if message.content.files.isEmpty {
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
        }
        .frame(minWidth: 64, alignment: .leading)
        .background(fill, in: shape)
        .clipShape(shape)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var header: some View {
        let name = showsAuthorName && !authorTitle.isEmpty
        if name || message.content.reply != nil {
            VStack(alignment: .leading, spacing: 4) {
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
            (Text(message.text) + Text(verbatim: "\u{2007}\u{2007}" + metaPlaceholder).font(.caption2).foregroundStyle(.clear))
                .foregroundStyle(textColor)
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
        let time = ChatContentFormat.time(message.timestamp)
        return isOutgoing ? time + "\u{2007}\u{2007}\u{2007}" : time
    }

    private var meta: some View {
        HStack(spacing: 3) {
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

    // MARK: Цитата

    private func quote(_ reply: MessageReply) -> some View {
        Button {
            onFocusReply(reply.messageId)
        } label: {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(quoteTint)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(reply.authorName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOutgoing ? Color.white : quoteTint)
                        .lineLimit(1)
                    Text(reply.preview)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(textColor.opacity(0.9))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                Spacer(minLength: 0)
            }
            .background(quoteTint.opacity(isOutgoing ? 0.25 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Цвета

    private var hasText: Bool {
        !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var stretchesText: Bool {
        !visuals.isEmpty || !message.content.voices.isEmpty || !message.content.files.isEmpty
    }

    private var hasHeader: Bool {
        (showsAuthorName && !authorTitle.isEmpty) || message.content.reply != nil
    }

    private var authorTitle: String {
        message.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Подложка есть у всего, кроме сообщения только из фото и видео.
    private var hasFill: Bool {
        hasText || hasHeader || !message.content.voices.isEmpty || !message.content.files.isEmpty || visuals.isEmpty
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
        UIPasteboard.general.string = message.text
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
