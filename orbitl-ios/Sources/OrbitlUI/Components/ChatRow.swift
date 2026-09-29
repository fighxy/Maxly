import SwiftUI

/// Строка списка чатов. Тексты уже готовы (`ChatListFormatter` в OrbitlPresentation),
/// компонент только раскладывает их.
public struct ChatRow: View {
    private let title: String
    private let preview: String
    private let time: String
    private let badge: String?
    private let accessibilityText: String

    public init(title: String, preview: String, time: String, badge: String?, accessibilityLabel: String) {
        self.title = title
        self.preview = preview
        self.time = time
        self.badge = badge
        self.accessibilityText = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: 12) {
            AvatarView(title: title)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(badge == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orbitlAccent))
                        .monospacedDigit()
                }
                HStack {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.orbitlAccent, in: Capsule())
                    }
                }
            }
        }
        .frame(minHeight: OrbitlTheme.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
