import SwiftUI
import OrbitlDomain

public struct ChatRow: View {
    private let chat: Chat

    public init(chat: Chat) {
        self.chat = chat
    }

    public var body: some View {
        HStack(spacing: 12) {
            AvatarView(title: chat.title.isEmpty ? "Чат" : chat.title)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.title.isEmpty ? "Чат" : chat.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(ChatTime.label(for: chat.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(chat.preview ?? "Нет сообщений")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
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
        .accessibilityElement(children: .combine)
    }
}
