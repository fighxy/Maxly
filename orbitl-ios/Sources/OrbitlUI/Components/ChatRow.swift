import SwiftUI
import OrbitlDomain
import OrbitlPresentation

/// Трёхстрочная строка списка чатов. Тексты и признаки уже готовы (`ChatListItem`),
/// компонент только раскладывает их.
///
/// Первая строка: заголовок, значки типа, «без звука», галочки и время.
/// Вторая и третья: в группах автор и текст, в остальных чатах текст в две строки.
/// Справа внизу бейдж непрочитанных, упоминание или булавка закреплённого.
public struct ChatRow: View {
    private let item: ChatListItem
    @ScaledMetric(relativeTo: .body) private var avatarSize = OrbitlTheme.avatar

    public init(item: ChatListItem) {
        self.item = item
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ChatAvatarView(avatar: item.avatar, size: min(avatarSize, 76), isOnline: item.isOnline)
            VStack(alignment: .leading, spacing: 2) {
                titleLine
                HStack(alignment: .top, spacing: 6) {
                    previewLines
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailingMarker
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: OrbitlTheme.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Первая строка

    private var titleLine: some View {
        HStack(spacing: 4) {
            if item.type == .channel {
                Image(systemName: "megaphone.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if item.type == .group {
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(item.title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            if item.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orbitlAccent)
            }
            if item.isBot {
                Text("бот")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.orbitlAccent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orbitlAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            }
            if item.isMuted {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            DeliveryMark(state: item.delivery)
            Text(item.time)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    // MARK: Вторая и третья строки

    @ViewBuilder
    private var previewLines: some View {
        switch item.previewStyle {
        case .typing:
            TypingText(text: item.preview)
                .lineLimit(2)
        case .draft:
            (Text("Черновик: ").foregroundColor(.red) + Text(item.preview).foregroundColor(.secondary))
                .font(.subheadline)
                .lineLimit(2)
        case .empty:
            Text(item.preview)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        case .message:
            VStack(alignment: .leading, spacing: 1) {
                if let sender = item.sender {
                    Text(sender)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    messageText(lines: 1)
                } else {
                    messageText(lines: 2)
                }
            }
        }
    }

    private func messageText(lines: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let url = item.thumbnailURL {
                RemoteImage(url: url) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.orbitlField)
                }
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            }
            Text(item.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(lines)
        }
    }

    // MARK: Правый маркер

    @ViewBuilder
    private var trailingMarker: some View {
        HStack(spacing: 4) {
            if item.hasMention {
                UnreadBadge(text: "@", muted: false)
            }
            if let badge = item.badge {
                switch badge {
                case .count(let text):
                    UnreadBadge(text: text, muted: item.badgeMuted)
                case .dot:
                    UnreadBadge(text: nil, muted: item.badgeMuted)
                }
            } else if item.showsPin {
                Image(systemName: "pin.fill")
                    .font(.footnote)
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Бейдж непрочитанных: капсула с числом или точка. Серый у чатов без звука.
public struct UnreadBadge: View {
    private let text: String?
    private let muted: Bool
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 20

    public init(text: String?, muted: Bool) {
        self.text = text
        self.muted = muted
    }

    public var body: some View {
        Group {
            if let text {
                Text(text)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: height, minHeight: height)
                    .background(muted ? Color.orbitlMutedBadge : Color.orbitlAccent, in: Capsule())
                    .contentTransition(.numericText())
            } else {
                Circle()
                    .fill(muted ? Color.orbitlMutedBadge : Color.orbitlAccent)
                    .frame(width: height * 0.6, height: height * 0.6)
                    .frame(width: height, height: height)
            }
        }
        .fixedSize()
    }
}

/// Галочки своего последнего сообщения.
public struct DeliveryMark: View {
    private let state: DeliveryState?

    public init(state: DeliveryState?) {
        self.state = state
    }

    public var body: some View {
        switch state {
        case .sending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orbitlAccent)
        case .read:
            ZStack(alignment: .leading) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark").offset(x: 5)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.orbitlAccent)
            .padding(.trailing, 5)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    /// Имя символа для состояния. Для тестов и мест без SwiftUI.
    public static func symbol(for state: DeliveryState) -> String {
        switch state {
        case .sending: "clock"
        case .sent, .read: "checkmark"
        case .failed: "exclamationmark.circle.fill"
        }
    }
}

/// «печатает…» цветом акцента с мягко мигающими точками. Без анимации, если она выключена в системе.
struct TypingText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            if !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.35)) { context in
                    let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .frame(width: 4, height: 4)
                                .opacity(index == phase ? 1 : 0.35)
                        }
                    }
                }
            }
            Text(text)
                .font(.subheadline)
        }
        .foregroundStyle(Color.orbitlAccent)
    }
}

/// Строка «Архив чатов»: иконка архива, свежий чат архива и его превью.
public struct ArchiveRow: View {
    private let summary: ChatArchiveSummary
    @ScaledMetric(relativeTo: .body) private var avatarSize = OrbitlTheme.avatar

    public init(summary: ChatArchiveSummary) {
        self.summary = summary
    }

    public var body: some View {
        HStack(spacing: 12) {
            ChatAvatarView(avatar: ChatAvatar(kind: .archive, colorIndex: 0), size: min(avatarSize, 76))
            VStack(alignment: .leading, spacing: 2) {
                Text("Архив чатов")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(summary.preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if summary.unreadCount > 0 {
                        UnreadBadge(text: ChatListFormatter.compactCount(summary.unreadCount), muted: true)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: OrbitlTheme.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Архив чатов, \(summary.count) \(summary.count == 1 ? "чат" : "чатов"), \(summary.title): \(summary.preview)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Заглушка строки, пока список грузится впервые.
public struct ChatRowSkeleton: View {
    private let seed: Int
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(seed: Int) {
        self.seed = seed
    }

    public var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.orbitlField)
                .frame(width: OrbitlTheme.avatar, height: OrbitlTheme.avatar)
            VStack(alignment: .leading, spacing: 8) {
                bar(width: 110 + CGFloat(seed * 37 % 80), height: 14)
                bar(width: 180 + CGFloat(seed * 53 % 70), height: 11)
                bar(width: 120 + CGFloat(seed * 29 % 90), height: 11)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(minHeight: OrbitlTheme.row)
        .opacity(dim ? 0.45 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color.orbitlField)
            .frame(width: width, height: height)
    }
}
