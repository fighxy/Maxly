import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Раскрытая полоса историй в шапке списка чатов: своя история первой
/// (с плюсом), затем непросмотренные, затем просмотренные.
struct StoriesStrip: View {
    let stories: StoriesViewModel
    let selfAvatar: ChatAvatar
    let onAdd: () -> Void
    @ScaledMetric(relativeTo: .caption) private var labelHeight: CGFloat = 16
    private let avatarSize: CGFloat = 62
    private let tileWidth: CGFloat = 76

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 2) {
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
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .frame(height: avatarSize + labelHeight + 16)
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
                    .foregroundStyle(Color.maxlyOnAccent)
                    .frame(width: 22, height: 22)
                    .background(Color.maxlyAccent, in: Circle())
                    .overlay(Circle().stroke(Color.maxlyBackground, lineWidth: 2))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: -3, y: 27)
            .accessibilityLabel("Новая история")
        }
    }

    private func tileLabel<Avatar: View>(title: String, dim: Bool, @ViewBuilder avatar: () -> Avatar) -> some View {
        VStack(spacing: 4) {
            avatar()
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .frame(height: labelHeight)
                .foregroundStyle(dim ? Color.secondary : Color.primary)
        }
        .frame(width: tileWidth)
        .contentShape(Rectangle())
    }
}

/// Свёрнутая полоса у заголовка «Чаты»: до трёх аватаров внахлёст, каждый
/// со своим кольцом. Касание раскрывает полосу.
struct StoryStack: View {
    let rings: [StoryRing]
    private let size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.36) {
            ForEach(Array(rings.prefix(3).enumerated()), id: \.element.owner) { index, ring in
                StoryRingAvatar(avatar: StoryText.avatar(ring), ring: ring, size: size, reservesRingSpace: true)
                    .background(Circle().fill(Color.maxlyBackground))
                    // Первый — сверху.
                    .zIndex(Double(3 - index))
            }
        }
        .accessibilityHidden(true)
    }
}
