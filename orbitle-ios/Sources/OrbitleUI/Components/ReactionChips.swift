import SwiftUI
import OrbitleDomain

struct ReactionChips: View {
    let reactions: [MessageReaction]
    let onToggle: (String) -> Void

    var body: some View {
        if !reactions.isEmpty {
            HStack(spacing: 6) {
                ForEach(reactions, id: \.emoji) { reaction in
                    Button {
                        onToggle(reaction.emoji)
                    } label: {
                        HStack(spacing: 4) {
                            Text(reaction.emoji)
                            if reaction.count > 1 {
                                Text("\(reaction.count)")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(reaction.mine ? Color.white : Color.primary)
                        .background(reaction.mine ? Color.orbitleAccent : Color.secondary.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
