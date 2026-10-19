import SwiftUI
import MaxlyDomain
import MaxlyPresentation

/// Плашки реакций: эмодзи и число, своя — цветом акцента. Нажатие ставит реакцию или
/// снимает свою. Обычно они внутри пузыря, под текстом; у фото без подписи — под ним.
struct ReactionChips: View {
    /// Сообщение плашек: по нему значок узнаёт только что поставленную реакцию (`ReactionGlyph`).
    var messageId = ""
    let reactions: [MessageReaction]
    /// Ряды прижаты к краю пузыря: у исходящих — к правому.
    var trailing = false
    /// `false`: только показать (сообщение ещё не на сервере или реакции недоступны).
    var interactive = true
    /// Плашки лежат на своём (цветном) пузыре: светлые на цветном фоне.
    var onOutgoing = false
    /// Время со статусом: встаёт в правый нижний угол последнего ряда, если влезает,
    /// иначе — отдельной строкой под реакциями. `nil` — время в другом месте пузыря.
    var meta: AnyView?
    let onToggle: (String) -> Void

    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reactions.isEmpty {
            ReactionFlow(spacing: 6, trailing: trailing, hasMeta: meta != nil) {
                ForEach(reactions, id: \.emoji) { reaction in
                    chip(reaction)
                        .transition(.maxlyPop(reduceMotion: reduceMotion))
                }
                if let meta {
                    // Время не сжимается и не переносится: плашки переносятся в оставшейся ширине.
                    meta.fixedSize()
                }
            }
            // Первая реакция «выпрыгивает» вместе с рядом; лента раздвигается по `contentVersion`.
            .transition(.maxlyPop(reduceMotion: reduceMotion))
            .animation(MaxlyMotion.pop(reduceMotion: reduceMotion), value: reactions)
            .sensoryFeedback(.selection, trigger: taps)
        }
    }

    private func chip(_ reaction: MessageReaction) -> some View {
        Button {
            taps += 1
            onToggle(reaction.emoji)
        } label: {
            HStack(spacing: 4) {
                ReactionGlyph(messageId: messageId, emoji: reaction.emoji)
                Text(ReactionPalette.countText(reaction.count))
                    .font(.app(.caption, .semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(reaction.count)))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
            .foregroundStyle(foreground(reaction))
            .background(background(reaction), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!interactive)
        .accessibilityLabel("\(reaction.emoji), \(reaction.count)")
        .accessibilityValue(reaction.mine ? "Ваша реакция" : "")
        .accessibilityHint(interactive ? (reaction.mine ? "Убрать реакцию" : "Поставить эту реакцию") : "")
    }
}

extension ReactionChips {
    fileprivate func foreground(_ reaction: MessageReaction) -> Color {
        if onOutgoing { return reaction.mine ? Color.maxlyOnOutgoingAccent : Color.maxlyOutgoingAccent }
        return reaction.mine ? Color.maxlyOnAccent : Color.primary
    }

    fileprivate func background(_ reaction: MessageReaction) -> Color {
        if onOutgoing { return reaction.mine ? Color.maxlyOutgoingAccent : Color.maxlyOutgoingAccent.opacity(0.12) }
        return reaction.mine ? Color.maxlyAccent : Color.secondary.opacity(0.15)
    }
}

/// Раскладка «в строку с переносом»: плашки идут подряд и переносятся на новый ряд,
/// когда не влезают в ширину пузыря. С `hasMeta` последний элемент — время: оно в правом
/// нижнем углу последнего ряда или своей строкой. Ряды и высоту считает `ReactionRowsLayout`,
/// одинаково при замере и раскладке: всё, что ниже реакций, не наезжает на последний ряд.
struct ReactionFlow: Layout {
    var spacing: CGFloat
    var trailing: Bool
    var hasMeta = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = rows(for: subviews, width: proposal.width ?? .infinity)
        // Со временем ряд занимает всю ширину пузыря, как раньше со `Spacer`: время у его
        // правого края. Ширину пузыря задаёт естественная (в один ряд) ширина плашек.
        if hasMeta, let width = proposal.width, width.isFinite {
            return CGSize(width: max(layout.width, width), height: layout.height)
        }
        return CGSize(width: layout.width, height: layout.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Ширина раскладки не шире замера: ряды те же (допуск на округление — в `ReactionRowsLayout`).
        let layout = rows(for: subviews, width: bounds.width)
        for row in layout.rows {
            var x = trailing && !hasMeta ? bounds.maxX - row.width : bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
        if hasMeta, let meta = subviews.last, let frame = layout.metaFrame(width: bounds.width) {
            meta.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> ReactionRowsLayout {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let meta = hasMeta ? sizes.last : nil
        return ReactionRowsLayout(
            chips: hasMeta ? Array(sizes.dropLast()) : sizes,
            meta: meta,
            maxWidth: width,
            spacing: spacing,
            lineSpacing: spacing,
            metaSpacing: 8
        )
    }
}
