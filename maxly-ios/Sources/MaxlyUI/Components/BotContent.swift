import SwiftUI
import MaxlyDomain

/// «Непрочитанные сообщения» над первым непрочитанным при открытии чата: полоса во всю ширину
/// ленты, как в популярных мессенджерах.
public struct UnreadSeparator: View {
    public init() {}

    public var body: some View {
        Text("Непрочитанные сообщения")
            .font(.app(.footnote, .semibold))
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
                    .fill(outgoing ? textColor.opacity(0.7) : Color.maxlyAccent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    if let site = preview.site {
                        Text(site)
                            .font(.app(.footnote, .semibold))
                            .foregroundStyle(outgoing ? textColor : Color.maxlyAccent)
                            .lineLimit(1)
                    }
                    if let title = preview.title {
                        Text(title)
                            .font(.app(.subheadline, .semibold))
                            .foregroundStyle(textColor)
                            .lineLimit(2)
                    }
                    if let summary = preview.summary {
                        Text(summary)
                            .font(.app(.footnote))
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

/// Inline-кнопки бота под пузырём: ряды стеклянных кнопок ровно по ширине пузыря
/// (`KeyboardAttached`). Значок справа подсказывает, что будет: ссылка, приложение или
/// копирование.
struct InlineKeyboardView: View {
    let keyboard: InlineKeyboard
    let onPress: (InlineButton) -> Void

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(Array(keyboard.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, button in
                        Button {
                            onPress(button)
                        } label: {
                            HStack(spacing: 4) {
                                Text(button.text)
                                    .font(.app(.subheadline, .medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                if let icon = Self.icon(button) {
                                    Image(systemName: icon)
                                        .font(.app(.caption2, .semibold))
                                }
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, minHeight: Self.height)
                            // Стекло на обоях: кнопки не спорят с пузырём, а лежат под ним.
                            .maxlyGlassRounded(radius: Self.radius)
                            .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                        }
                        .buttonStyle(InlineKeyboardButtonStyle())
                    }
                }
            }
        }
    }

    /// Высота строки, зазор между кнопками и скругление. Высота ряда для оценки ленты —
    /// `BubbleHeightCache.keyboardRow`.
    static let height: CGFloat = 36
    static let spacing: CGFloat = 4
    static let radius: CGFloat = 12

    /// Отклик на касание: кнопка слегка гаснет, пока палец на ней.
    private struct InlineKeyboardButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.55 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

/// Пузырь бота и его кнопки одной ширины: шире из двух — текста одной строкой или ряда кнопок
/// без переносов, но не шире колонки. Пузырь растягивается до ширины кнопок, кнопки — до
/// ширины пузыря, и меню не торчит из-под сообщения.
struct KeyboardAttached: Layout {
    var trailing = false
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(proposal: proposal, subviews: subviews)
        let height = subviews.reduce(CGFloat(0)) { sum, subview in
            sum + subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        return CGSize(width: width, height: height + spacing * CGFloat(max(subviews.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = width(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        let x = trailing ? bounds.maxX - width : bounds.minX
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: size.height))
            y += size.height + spacing
        }
    }

    private func width(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        let limit = proposal.width ?? .infinity
        let widest = subviews.reduce(CGFloat(0)) { max($0, $1.sizeThatFits(.unspecified).width) }
        return limit.isFinite ? min(widest, limit) : widest
    }
}
