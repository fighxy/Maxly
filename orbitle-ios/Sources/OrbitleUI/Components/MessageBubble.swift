import SwiftUI
import OrbitleDomain
import OrbitlePresentation

public struct MessageBubble: View {
    private let message: Message
    private let isOutgoing: Bool
    private let maxWidth: CGFloat
    private let phase: VoicePhase
    private let allowsComments: Bool
    private let highlighted: Bool
    private let onRetry: () -> Void
    private let onReply: () -> Void
    private let onReact: (String) -> Void
    private let onComments: () -> Void
    private let onOpen: (String) -> Void
    private let onVoice: () -> Void
    private let onFocusReply: (String) -> Void

    public init(
        message: Message,
        isOutgoing: Bool,
        maxWidth: CGFloat = 280,
        phase: VoicePhase = .idle,
        allowsComments: Bool = false,
        highlighted: Bool = false,
        onRetry: @escaping () -> Void = {},
        onReply: @escaping () -> Void = {},
        onReact: @escaping (String) -> Void = { _ in },
        onComments: @escaping () -> Void = {},
        onOpen: @escaping (String) -> Void = { _ in },
        onVoice: @escaping () -> Void = {},
        onFocusReply: @escaping (String) -> Void = { _ in }
    ) {
        self.message = message
        self.isOutgoing = isOutgoing
        self.maxWidth = maxWidth
        self.phase = phase
        self.allowsComments = allowsComments
        self.highlighted = highlighted
        self.onRetry = onRetry
        self.onReply = onReply
        self.onReact = onReact
        self.onComments = onComments
        self.onOpen = onOpen
        self.onVoice = onVoice
        self.onFocusReply = onFocusReply
    }

    public var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: 36) }
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                bubble
                status
                ReactionChips(reactions: message.content.reactions, onToggle: onReact)
                if showsComments {
                    Button(ChatContentFormat.comments(message.content.comments?.count ?? 0), action: onComments)
                        .font(.footnote)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.orbitleAccent)
                }
            }
            .frame(maxWidth: maxWidth, alignment: isOutgoing ? .trailing : .leading)
            if !isOutgoing { Spacer(minLength: 36) }
        }
        .padding(.vertical, highlighted ? 2 : 0)
        .background(highlighted ? Color.orbitleAccent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Ответить", action: onReply)
            Menu("Реакция") {
                ForEach(ReactionPalette.quick, id: \.self) { emoji in
                    Button(emoji) { onReact(emoji) }
                }
            }
            if allowsComments {
                Button("Комментарии", action: onComments)
            }
        }
    }

    private var showsComments: Bool {
        allowsComments || message.content.comments != nil
    }

    private var hasText: Bool {
        !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reply = message.content.reply {
                quote(reply)
            }
            if !message.content.visuals.isEmpty {
                MediaMosaic(
                    attachments: message.content.visuals,
                    maxWidth: maxWidth,
                    time: hasText ? nil : ChatContentFormat.time(message.timestamp),
                    onOpen: onOpen
                )
            }
            if !message.content.voices.isEmpty {
                ForEach(message.content.voices, id: \.id) { voice in
                    VoiceMessageView(voice: voice, phase: phase, outgoing: isOutgoing, onToggle: onVoice)
                }
            }
            if hasText || message.content.voices.isEmpty && message.content.visuals.isEmpty {
                HStack(alignment: .bottom, spacing: 8) {
                    Text(message.text)
                        .foregroundStyle(isOutgoing ? Color.white : Color.primary)
                    if hasText {
                        Text(ChatContentFormat.time(message.timestamp))
                            .font(.caption2)
                            .foregroundStyle(isOutgoing ? Color.white.opacity(0.75) : Color.secondary)
                    }
                }
            } else if !message.content.voices.isEmpty {
                Text(ChatContentFormat.time(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.75) : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, showsFill ? 12 : 0)
        .padding(.vertical, showsFill ? 8 : 0)
        .background(fill, in: RoundedRectangle(cornerRadius: OrbitleTheme.radius, style: .continuous))
    }

    private var showsFill: Bool {
        hasText || message.content.reply != nil || !message.content.voices.isEmpty
    }

    private var fill: Color {
        guard showsFill else { return .clear }
        return isOutgoing ? Color.orbitleOutgoing : Color.orbitleIncoming
    }

    private func quote(_ reply: MessageReply) -> some View {
        Button {
            onFocusReply(reply.messageId)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isOutgoing ? Color.white : Color.orbitleAccent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reply.authorName)
                        .font(.caption.weight(.semibold))
                    Text(reply.preview)
                        .font(.caption)
                        .lineLimit(2)
                }
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.92) : Color.primary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var status: some View {
        switch message.status {
        case .sending:
            Text("отправляется")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .sent:
            EmptyView()
        case .failed:
            Button("Не отправлено. Повторить", action: onRetry)
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}
