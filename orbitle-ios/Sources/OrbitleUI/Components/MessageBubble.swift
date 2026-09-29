import SwiftUI
import OrbitleDomain

public struct MessageBubble: View {
    private let message: Message
    private let isOutgoing: Bool
    private let onRetry: () -> Void

    public init(message: Message, isOutgoing: Bool, onRetry: @escaping () -> Void = {}) {
        self.message = message
        self.isOutgoing = isOutgoing
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: 48) }
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .foregroundStyle(isOutgoing ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isOutgoing ? Color.orbitleOutgoing : Color.orbitleIncoming, in: RoundedRectangle(cornerRadius: OrbitleTheme.radius))
                status
            }
            .frame(maxWidth: 280, alignment: isOutgoing ? .trailing : .leading)
            if !isOutgoing { Spacer(minLength: 48) }
        }
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
