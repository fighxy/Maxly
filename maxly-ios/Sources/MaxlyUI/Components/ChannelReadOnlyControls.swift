import SwiftUI

/// Общая ось и размеры поиска, «вниз» и капсулы звука.
public enum ChatControlMetrics {
    public static let diameter: CGFloat = 44
    public static let trailingInset: CGFloat = 16
    public static let gap: CGFloat = 8
}

public struct ChannelReadOnlyControls: View {
    private let isMuted: Bool
    private let onToggleMute: () -> Void
    private let onSearch: (() -> Void)?

    public init(isMuted: Bool, onToggleMute: @escaping () -> Void, onSearch: (() -> Void)?) {
        self.isMuted = isMuted
        self.onToggleMute = onToggleMute
        self.onSearch = onSearch
    }

    public var body: some View {
        ZStack {
            Button(action: onToggleMute) {
                Label(isMuted ? "Включить звук" : "Выключить звук", systemImage: isMuted ? "bell" : "bell.slash")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 16)
                    .frame(height: ChatControlMetrics.diameter)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.maxlyAccent)
            .maxlyGlassCapsule()
            // Симметричные слоты сохраняют центр капсулы, поиск привязан к краю экрана.
            .padding(.horizontal, ChatControlMetrics.diameter + ChatControlMetrics.gap)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .trailing) {
            if let onSearch {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.maxlyAccent)
                        .maxlyGlassCircle(size: ChatControlMetrics.diameter)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Поиск в канале")
            }
        }
    }
}
