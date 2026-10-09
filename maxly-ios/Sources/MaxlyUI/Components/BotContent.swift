import SwiftUI
import MaxlyDomain

/// «Непрочитанные сообщения» над первым непрочитанным при открытии чата: полоса во всю ширину
/// ленты, как в популярных мессенджерах.
public struct UnreadSeparator: View {
    public init() {}

    public var body: some View {
        Text("Непрочитанные сообщения")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .padding(.horizontal, -MaxlyTheme.pad)
            .padding(.vertical, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Превью ссылки (`SHARE`) внутри пузыря: полоска акцента слева, сайт, заголовок, описание и
/// картинка. Нажатие открывает адрес.
struct LinkPreviewCard: View {
    let preview: LinkPreview
    let outgoing: Bool
    let textColor: Color
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: preview.url) { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(outgoing ? textColor.opacity(0.7) : Color.orbitleAccent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    if let site = preview.site {
                        Text(site)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(outgoing ? textColor : Color.orbitleAccent)
                            .lineLimit(1)
                    }
                    if let title = preview.title {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textColor)
                            .lineLimit(2)
                    }
                    if let summary = preview.summary {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(textColor.opacity(0.85))
                            .lineLimit(3)
                    }
                    if let image = preview.imageURL {
                        Color.clear
                            .aspectRatio(aspect, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 180)
                            .overlay {
                                RemoteImage(url: image, maxPixel: 800) {
                                    Color.secondary.opacity(0.15)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть ссылку")
    }

    private var aspect: CGFloat {
        guard let w = preview.imageWidth, let h = preview.imageHeight, w > 0, h > 0 else { return 16.0 / 9.0 }
        return max(1, CGFloat(w) / CGFloat(h))
    }
}

/// Inline-кнопки бота под пузырём: ряды кнопок цвета пузыря во всю его ширину. Значок справа
/// подсказывает, что будет: ссылка, приложение или копирование.
struct InlineKeyboardView: View {
    let keyboard: InlineKeyboard
    let onPress: (InlineButton) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(keyboard.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, button in
                        Button {
                            onPress(button)
                        } label: {
                            HStack(spacing: 4) {
                                Text(button.text)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                if let icon = Self.icon(button) {
                                    Image(systemName: icon)
                                        .font(.caption2.weight(.semibold))
                                }
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .padding(.horizontal, 8)
                            // Цвет входящего пузыря: на обоях кнопка читается так же, как пост над ней.
                            .background(Color.orbitleIncomingOnWallpaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    static func icon(_ button: InlineButton) -> String? {
        switch button.action {
        case .link: "arrow.up.right"
        case .openApp: "square.grid.2x2"
        case .copy: "doc.on.doc"
        case .callback: nil
        }
    }
}
