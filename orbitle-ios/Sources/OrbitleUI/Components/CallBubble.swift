import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Звонок в пузыре: круг со значком, заголовок и длительность, время сообщения справа.
/// Пропущенный входящий выделен красным, как во вкладке «Звонки». В своём (синем) пузыре
/// всё белое.
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
        if outgoing { return .white }
        return alert ? .red : .primary
    }

    private var iconColor: Color {
        if outgoing { return .white }
        return alert ? .red : Color.orbitleAccent
    }

    private var iconBackground: Color {
        if outgoing { return Color.white.opacity(0.22) }
        return (alert ? Color.red : Color.orbitleAccent).opacity(0.14)
    }

    private var secondary: Color {
        outgoing ? Color.white.opacity(0.75) : Color.secondary
    }
}
