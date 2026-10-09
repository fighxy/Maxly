import SwiftUI
import MaxlyDomain

/// Служебная строка разделяет группы пузырей и не предлагает ответ или реакцию.
struct ServiceMessageNotice: View {
    let pin: PinNotice
    let onOpen: (String) -> Void

    private var target: String? {
        guard let id = pin.messageId, !id.isEmpty else { return nil }
        return id
    }

    var body: some View {
        Group {
            if let target {
                Button { onOpen(target) } label: { label }
                    .buttonStyle(.plain)
                    .accessibilityHint("Перейти к закреплённому сообщению")
            } else {
                label
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var label: some View {
        Text(target == nil ? "Закрепление снято" : (pin.preview.isEmpty ? "Сообщение закреплено" : "Закреплено: \(pin.preview)"))
            .font(.footnote)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
