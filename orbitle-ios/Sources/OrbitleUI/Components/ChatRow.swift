import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Трёхстрочная строка списка чатов. Тексты и признаки уже готовы (`ChatListItem`),
/// компонент только раскладывает их.
///
/// Первая строка: заголовок, значки типа, «без звука», галочки и время.
/// Вторая и третья: в группах автор и текст, в остальных чатах текст в две строки.
/// Справа внизу бейдж непрочитанных, упоминание или булавка закреплённого.
///
/// В приватном режиме строка с заглушками берётся из `PrivateModeMask.item`, с размытием —
/// настоящая, но заголовок, автор, текст, миниатюра и аватар размыты.
public struct ChatRow: View {
    private let original: ChatListItem
    /// Кольцо историй собеседника; касание аватара открывает истории (`onStoryTap`).
    private let storyRing: StoryRing?
    private let onStoryTap: (() -> Void)?
    @ScaledMetric(relativeTo: .body) private var avatarSize = OrbitleTheme.avatar
    @Environment(\.privateMode) private var privateMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(item: ChatListItem, storyRing: StoryRing? = nil, onStoryTap: (() -> Void)? = nil) {
        self.original = item
        self.storyRing = storyRing
        self.onStoryTap = onStoryTap
    }

    /// Что рисуется: при заглушках — строка без имён и текста.
    private var item: ChatListItem {
        privateMode == .placeholder ? PrivateModeMask.item(original) : original
    }

    /// VoiceOver при любом виде режима читает строку без имён и текста.
    private var spokenLabel: String {
        privateMode.isMasked ? PrivateModeMask.item(original).accessibilityLabel : original.accessibilityLabel
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            avatarView
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
        .frame(minHeight: OrbitleTheme.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// Аватар; с историями — в кольце, и касание по нему открывает истории, а не чат.
    /// Заглушки приватного режима колец не показывают.
    @ViewBuilder
    private var avatarView: some View {
        let ring = privateMode == .placeholder ? nil : storyRing
        let avatar = StoryRingAvatar(avatar: item.avatar, ring: ring, size: min(avatarSize, 76), isOnline: item.isOnline)
        if ring != nil, let onStoryTap {
            Button(action: onStoryTap) { avatar }
                .buttonStyle(.borderless)
                .accessibilityLabel("Истории")
        } else {
            avatar
        }
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
                .privateModeBlur(privateMode)
            if item.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orbitleAccent)
            }
            if item.isBot {
                Text("бот")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.orbitleAccent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orbitleAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            }
            if item.isMuted {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            DeliveryMark(state: item.delivery)
                .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: item.delivery)
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
            if privateMode == .blur {
                HStack(spacing: 0) {
                    Text("Черновик: ").foregroundStyle(.red)
                    Text(item.preview).foregroundStyle(.secondary).privateModeBlur(privateMode)
                }
                .font(.subheadline)
                .lineLimit(1)
            } else {
                (Text("Черновик: ").foregroundColor(.red) + Text(item.preview).foregroundColor(.secondary))
                    .font(.subheadline)
                    .lineLimit(2)
            }
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
                        .privateModeBlur(privateMode)
                    messageText(lines: 1)
                } else {
                    messageText(lines: 2)
                }
            }
        }
    }

    private func messageText(lines: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if item.isForwarded {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Переслано")
            }
            if let url = item.thumbnailURL {
                RemoteImage(url: url, maxPixel: 64) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.orbitleField)
                }
                .frame(width: 18, height: 18)
                .privateModeBlur(privateMode, radius: 4)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            }
            Text(item.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(lines)
                .privateModeBlur(privateMode)
        }
    }

    // MARK: Правый маркер

    @ViewBuilder
    private var trailingMarker: some View {
        HStack(spacing: 4) {
            if item.hasMention {
                UnreadBadge(text: "@", muted: false)
                    .transition(.orbitlePop(reduceMotion: reduceMotion))
            }
            if let badge = item.badge {
                Group {
                    switch badge {
                    case .count(let text):
                        UnreadBadge(text: text, muted: item.badgeMuted)
                    case .dot:
                        UnreadBadge(text: nil, muted: item.badgeMuted)
                    }
                }
                .transition(.orbitlePop(reduceMotion: reduceMotion))
            } else if item.showsPin {
                Image(systemName: "pin.fill")
                    .font(.footnote)
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(.tertiary)
                    .transition(.orbitlePop(reduceMotion: reduceMotion))
            }
        }
        // Бейдж появляется, растёт числом и гаснет плавно — и когда строка не двигается.
        .animation(OrbitleMotion.pop(reduceMotion: reduceMotion), value: item.badge)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: item.hasMention)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: item.showsPin)
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
                    .foregroundStyle(Color.orbitleOnAccent)
                    .padding(.horizontal, 6)
                    .frame(minWidth: height, minHeight: height)
                    .background(muted ? Color.orbitleMutedBadge : Color.orbitleAccent, in: Capsule())
                    .contentTransition(.numericText())
            } else {
                Circle()
                    .fill(muted ? Color.orbitleMutedBadge : Color.orbitleAccent)
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
        case .sent, .read:
            DeliveryChecks(read: state == .read, lineWidth: 1.6)
                .foregroundStyle(Color.orbitleAccent)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    /// Имя символа для состояния. Для тестов и мест без SwiftUI.
    public nonisolated static func symbol(for state: DeliveryState) -> String {
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
        .foregroundStyle(Color.orbitleAccent)
    }
}

/// Строка «Архив чатов»: иконка архива, свежий чат архива и его превью.
public struct ArchiveRow: View {
    private let original: ChatArchiveSummary
    @ScaledMetric(relativeTo: .body) private var avatarSize = OrbitleTheme.avatar
    @Environment(\.privateMode) private var privateMode

    public init(summary: ChatArchiveSummary) {
        self.original = summary
    }

    private var summary: ChatArchiveSummary {
        privateMode == .placeholder ? PrivateModeMask.archive(original) : original
    }

    public var body: some View {
        let summary = self.summary
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
                            .privateModeBlur(privateMode)
                        Text(summary.preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privateModeBlur(privateMode)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if summary.unreadCount > 0 {
                        UnreadBadge(text: ChatListFormatter.compactCount(summary.unreadCount), muted: true)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: OrbitleTheme.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(archiveLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var archiveLabel: String {
        let shown = privateMode.isMasked ? PrivateModeMask.archive(original) : original
        return "Архив чатов, \(shown.count) \(shown.count == 1 ? "чат" : "чатов"), \(shown.title): \(shown.preview)"
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
                .fill(Color.orbitleField)
                .frame(width: OrbitleTheme.avatar, height: OrbitleTheme.avatar)
            VStack(alignment: .leading, spacing: 8) {
                bar(width: 110 + CGFloat(seed * 37 % 80), height: 14)
                bar(width: 180 + CGFloat(seed * 53 % 70), height: 11)
                bar(width: 120 + CGFloat(seed * 29 % 90), height: 11)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(minHeight: OrbitleTheme.row)
        .opacity(dim ? 0.45 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color.orbitleField)
            .frame(width: width, height: height)
    }
}
