import SwiftUI
import OrbitlPresentation

/// Аватар строки: фото, буквы на градиенте по id, «Избранное», архив. Точка «в сети» справа снизу.
public struct ChatAvatarView: View {
    private let avatar: ChatAvatar
    private let size: CGFloat
    private let isOnline: Bool

    public init(avatar: ChatAvatar, size: CGFloat = OrbitlTheme.avatar, isOnline: Bool = false) {
        self.avatar = avatar
        self.size = size
        self.isOnline = isOnline
    }

    public var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                if isOnline {
                    Circle()
                        .fill(Color.orbitlOnline)
                        .frame(width: size * 0.26, height: size * 0.26)
                        .overlay(Circle().stroke(Color.orbitlBackground, lineWidth: max(2, size * 0.045)))
                        .offset(x: -size * 0.02, y: -size * 0.02)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.25), value: isOnline)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch avatar.kind {
        case .initials(let text):
            initials(text)
        case .photo(let url, let text):
            RemoteImage(url: url) { initials(text) }
        case .savedMessages:
            special("bookmark.fill")
        case .archive:
            special("archivebox.fill")
        }
    }

    private func initials(_ text: String) -> some View {
        ZStack {
            AvatarPalette.gradient(avatar.colorIndex)
            Text(text)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(size * 0.08)
        }
    }

    private func special(_ symbol: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.orbitlSpecialAvatar.opacity(0.85), Color.orbitlSpecialAvatar],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

/// Буквы имени на градиенте. Для мест, где нет `ChatAvatar` (профиль, контакты).
public struct AvatarView: View {
    private let title: String
    private let id: String
    private let url: URL?
    private let size: CGFloat
    private let isOnline: Bool

    public init(title: String, id: String? = nil, url: URL? = nil, size: CGFloat = OrbitlTheme.avatar, isOnline: Bool = false) {
        self.title = title
        self.id = id ?? title
        self.url = url
        self.size = size
        self.isOnline = isOnline
    }

    public var body: some View {
        let initials = ChatAvatar.initials(for: title)
        let kind: ChatAvatar.Kind = url.map { .photo($0, initials: initials) } ?? .initials(initials)
        ChatAvatarView(avatar: ChatAvatar(kind: kind, colorIndex: ChatAvatar.colorIndex(for: id)), size: size, isOnline: isOnline)
            .accessibilityLabel(title)
    }
}
