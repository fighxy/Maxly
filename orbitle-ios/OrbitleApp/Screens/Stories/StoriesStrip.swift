import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Полоса историй над списком чатов: «Ваша история» с кнопкой новой и кольца остальных —
/// сначала непросмотренные, затем свежие.
struct StoriesStrip: View {
    let stories: StoriesViewModel
    let selfAvatar: ChatAvatar
    let onAdd: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 2) {
                selfTile
                ForEach(stories.rings, id: \.owner.id) { ring in
                    tile(title: StoryText.title(ring, own: false), dim: !ring.hasUnread, action: { stories.open(ring.owner.id) }) {
                        StoryRingAvatar(avatar: StoryText.avatar(ring), ring: ring, size: 62)
                    }
                }
            }
            .padding(.horizontal, OrbitleTheme.pad - 8)
            .padding(.vertical, 6)
        }
    }

    private var selfTile: some View {
        tile(title: StoryText.yourStory, dim: false, action: {
            if let own = stories.own { stories.open(own.owner.id) } else { onAdd() }
        }) {
            StoryRingAvatar(avatar: selfAvatar, ring: stories.own, size: 62, progress: stories.publishProgress)
                .overlay(alignment: .bottomTrailing) {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.orbitleOnAccent)
                            .frame(width: 22, height: 22)
                            .background(Color.orbitleAccent, in: Circle())
                            .overlay(Circle().stroke(Color.orbitleBackground, lineWidth: 2))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Новая история")
                }
        }
    }

    private func tile<Avatar: View>(title: String, dim: Bool, action: @escaping () -> Void, @ViewBuilder avatar: () -> Avatar) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                avatar()
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(dim ? Color.secondary : Color.primary)
            }
            .frame(width: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
