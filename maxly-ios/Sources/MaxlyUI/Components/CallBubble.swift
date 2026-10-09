import SwiftUI
import MaxlyDomain
import MaxlyPresentation

/// Звонок в пузыре: круг со значком, заголовок и длительность, время сообщения справа.
/// Пропущенный входящий выделен красным, как во вкладке «Звонки». Исходящие используют
/// контрастные цвета текущей темы.
struct CallBubble: View {
    let call: CallContent
    let outgoing: Bool
    /// Время и галочки сообщения. `nil` — время показано в другом месте пузыря.
    var time: AnyView?
    /// Время для VoiceOver.
    var timeText: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: CallBubbleText.symbol(call, outgoing: outgoing))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconBackground, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(CallBubbleText.title(call, outgoing: outgoing))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let duration = CallBubbleText.duration(call) {
                        Text(duration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                    }
                    // Без распорки: пузырь звонка по ширине содержимого, а не во всю ленту.
                    if let time { time }
                }
            }
            .frame(minWidth: 120, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CallBubbleText.accessibility(call, outgoing: outgoing, time: timeText))
    }

    private var alert: Bool { CallBubbleText.isAlert(call, outgoing: outgoing) }

    private var titleColor: Color {
        if outgoing { return .maxlyOutgoingText }
        return alert ? .red : .primary
    }

    private var iconColor: Color {
        if outgoing { return .maxlyOutgoingAccent }
        return alert ? .red : Color.maxlyAccent
    }

    private var iconBackground: Color {
        if outgoing { return Color.maxlyOutgoingAccent.opacity(0.15) }
        return (alert ? Color.red : Color.maxlyAccent).opacity(0.14)
    }

    private var secondary: Color {
        outgoing ? Color.maxlyOutgoingSecondary : Color.secondary
    }
}
