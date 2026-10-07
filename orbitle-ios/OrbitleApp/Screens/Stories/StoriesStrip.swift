import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Один горизонтальный ряд внутри списка: вертикальная прокрутка принадлежит List.
struct StoriesStrip: View {
    let stories: StoriesViewModel
    let selfAvatar: ChatAvatar
    let onAdd: () -> Void
    @ScaledMetric(relativeTo: .caption) private var labelHeight: CGFloat = 16
    private let avatarSize: CGFloat = 58

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 4) {
                selfTile
                ForEach(stories.rings, id: \.owner) { ring in
                    Button { stories.open(ring.owner.id, kind: ring.owner.kind) } label: {
                        tileLabel(title: StoryText.title(ring, own: false), dim: !ring.hasUnread) {
                            StoryRingAvatar(avatar: StoryText.avatar(ring), ring: ring, size: avatarSize, reservesRingSpace: true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(StoryText.title(ring, own: false))
                    .accessibilityValue(ring.hasUnread ? "Есть непросмотренные истории" : "Просмотрено")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(height: avatarSize + labelHeight + 22)
    }

    private var selfTile: some View {
        Button {
            if let own = stories.own { stories.open(own.owner.id, kind: own.owner.kind) } else { onAdd() }
        } label: {
            tileLabel(title: StoryText.yourStory, dim: false) {
                StoryRingAvatar(avatar: selfAvatar, ring: stories.own, size: avatarSize,
                                progress: stories.publishProgress, reservesRingSpace: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(StoryText.yourStory)
        // Отдельная кнопка, а не Button внутри Button: плюс не открывает просмотр вместе с редактором.
        .overlay(alignment: .topTrailing) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.orbitleOnAccent)
                    .frame(width: 22, height: 22)
                    .background(Color.orbitleAccent, in: Circle())
                    .overlay(Circle().stroke(Color.orbitleBackground, lineWidth: 2))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 1, y: 25)
            .accessibilityLabel("Новая история")
        }
    }

    private func tileLabel<Avatar: View>(title: String, dim: Bool, @ViewBuilder avatar: () -> Avatar) -> some View {
        VStack(spacing: 6) {
            avatar()
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .frame(height: labelHeight)
                .foregroundStyle(dim ? Color.secondary : Color.primary)
        }
        .frame(width: 88)
        .contentShape(Rectangle())
    }
}
