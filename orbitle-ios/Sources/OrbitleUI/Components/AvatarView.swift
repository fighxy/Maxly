import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Аватар строки: фото, буквы на градиенте по id, «Избранное», архив. Точка «в сети» справа снизу.
public struct ChatAvatarView: View {
    private let avatar: ChatAvatar
    private let size: CGFloat
    private let isOnline: Bool
    @Environment(\.privateMode) private var privateMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.imageURLSizing) private var imageURLSizing

    public init(avatar: ChatAvatar, size: CGFloat = OrbitleTheme.avatar, isOnline: Bool = false) {
        self.avatar = avatar
        self.size = size
        self.isOnline = isOnline
    }

    public var body: some View {
        content
            .frame(width: size, height: size)
            // Размытие до обрезки: край круга остаётся ровным.
            .blur(radius: blursPhoto ? size * PrivateModeBlur.avatar : 0)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                // Точка «в сети» выдаёт, что чат личный и собеседник рядом.
                if isOnline, !privateMode.isMasked {
                    Circle()
                        .fill(Color.orbitleOnline)
                        .frame(width: size * 0.26, height: size * 0.26)
                        .overlay(Circle().stroke(Color.orbitleBackground, lineWidth: max(2, size * 0.045)))
                        .offset(x: -size * 0.02, y: -size * 0.02)
                        .transition(.orbitlePop(reduceMotion: reduceMotion))
                }
            }
            .animation(OrbitleMotion.pop(reduceMotion: reduceMotion), value: isOnline)
            .accessibilityHidden(true)
    }

    /// В приватном режиме с заглушками — однотонный круг того же цвета.
    private var shown: ChatAvatar {
        privateMode == .placeholder ? PrivateModeMask.avatar(avatar) : avatar
    }

    /// Размываются фото и буквы; значки «Избранного» и архива ничего не выдают.
    private var blursPhoto: Bool {
        guard privateMode == .blur else { return false }
        switch avatar.kind {
        case .initials, .photo: return true
        case .savedMessages, .archive: return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch shown.kind {
        case .initials(let text):
            initials(text)
        case .photo(let url, let text):
            RemoteImage(
                url: ImageURLRequests.url(url, shape: .square, pointSize: size, scale: displayScale, fullScreen: false, sizing: imageURLSizing),
                maxPixel: Int(size * 3)
            ) { initials(text) }
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
                colors: [Color.orbitleSpecialAvatar.opacity(0.85), Color.orbitleSpecialAvatar],
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
    @Environment(\.privateMode) private var privateMode

    public init(title: String, id: String? = nil, url: URL? = nil, size: CGFloat = OrbitleTheme.avatar, isOnline: Bool = false) {
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
            .accessibilityLabel(privateMode.isMasked ? "" : title)
    }
}
