import SwiftUI
import MaxlyDomain

/// Служебная строка закрепления: текст ядра (`ServiceText.text(pin)`), нажатие открывает
/// закреплённое сообщение (`pinnedMessage.id`). Разделяет группы пузырей и не предлагает ответ
/// или реакцию.
struct ServiceMessageNotice: View {
    let pin: PinNotice
    let onOpen: (String) -> Void

    private var target: String? {
        guard !pin.isUnpin, let id = pin.messageId, !id.isEmpty else { return nil }
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
        Text(ServiceText.text(pin))
            .font(.app(.footnote))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Служебное событие чата: кто вступил, вышел, сменил название или фото. Серая плашка по
/// центру, без пузыря, аватара, меню и ответа свайпом.
struct ServiceEventNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.app(.footnote))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
    }
}
