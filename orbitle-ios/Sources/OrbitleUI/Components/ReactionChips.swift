import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Плашки реакций под пузырём: эмодзи и число, своя — цветом акцента. Нажатие ставит
/// реакцию или снимает свою. Плашки плоские: это содержимое ленты, а не плавающие кнопки.
struct ReactionChips: View {
    let reactions: [MessageReaction]
    /// Ряды прижаты к краю пузыря: у исходящих — к правому.
    var trailing = false
    /// `false`: только показать (сообщение ещё не на сервере или реакции недоступны).
    var interactive = true
    let onToggle: (String) -> Void

    @State private var taps = 0

    var body: some View {
        if !reactions.isEmpty {
            ReactionFlow(spacing: 6, trailing: trailing) {
                ForEach(reactions, id: \.emoji) { reaction in
                    chip(reaction)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: reactions)
            .sensoryFeedback(.selection, trigger: taps)
        }
    }

    private func chip(_ reaction: MessageReaction) -> some View {
        Button {
            taps += 1
            onToggle(reaction.emoji)
        } label: {
            HStack(spacing: 4) {
                Text(reaction.emoji)
                    .font(.system(size: 15))
                Text(ReactionPalette.countText(reaction.count))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(reaction.count)))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
            .foregroundStyle(reaction.mine ? Color.white : Color.primary)
            .background(reaction.mine ? Color.orbitleAccent : Color.secondary.opacity(0.15), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!interactive)
        .accessibilityLabel("\(reaction.emoji), \(reaction.count)")
        .accessibilityValue(reaction.mine ? "Ваша реакция" : "")
        .accessibilityHint(interactive ? (reaction.mine ? "Убрать реакцию" : "Поставить эту реакцию") : "")
    }
}

/// Раскладка «в строку с переносом»: плашки идут подряд и переносятся на новый ряд,
/// когда не влезают в ширину пузыря.
struct ReactionFlow: Layout {
    var spacing: CGFloat
    var trailing: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = trailing ? bounds.maxX - row.width : bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let added = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, added > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(index)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
