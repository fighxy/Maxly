import SwiftUI
import MaxlyPresentation
import MaxlyUI

/// Строка «играет голосовое» в стеклянной карточке над чатом и списком, как в Telegram: пуск и
/// пауза, по центру автор и «Голосовое сообщение», скорость 1X / 1.5X / 2X (голос не искажается),
/// закрыть, внизу тонкая полоса прогресса. Своего фона нет: строку кладут в `TopDock` вместе
/// с папками или закрепом. Касание по имени — `onOpen`: чат открывается на сообщении и оно
/// подсвечивается.
struct VoicePlayerRow: View {
    let model: VoiceNowPlaying
    let onOpen: (VoiceNowPlaying.Track) -> Void

    static let height: CGFloat = 48

    var body: some View {
        if let track = model.track {
            HStack(spacing: 4) {
                Button { model.toggle() } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(track.isPlaying ? "Пауза" : "Продолжить")
                Button { onOpen(track) } label: {
                    VStack(spacing: 1) {
                        Text(track.title)
                            .font(.app(.subheadline, .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Голосовое сообщение · \(track.timeText)")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: Self.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { model.cycleSpeed() } label: {
                    Text(VoiceNowPlaying.label(model.speed).uppercased())
                        .font(.app(.caption2, .bold))
                        .monospacedDigit()
                        .foregroundStyle(model.speed > 1 ? Color.maxlyAccent : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 2.5]))
                                .foregroundStyle(model.speed > 1 ? Color.maxlyAccent : Color.secondary)
                        }
                        .frame(minWidth: 40, minHeight: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Скорость \(VoiceNowPlaying.label(model.speed))")
                Button { model.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
            .padding(.horizontal, 6)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.maxlyAccent)
                        .frame(width: proxy.size.width * min(max(track.progress, 0), 1), height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .allowsHitTesting(false)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// Стеклянная карточка у верха экрана: секции одна под другой через тонкий разделитель, как
/// папки и плеер в списке или плеер и закреп в чате у Telegram.
struct TopDock<Content: View>: View {
    @ViewBuilder let content: Content

    static var radius: CGFloat { 20 }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .maxlyGlassRounded(radius: Self.radius)
    }
}

/// Тонкий разделитель между секциями `TopDock`.
struct TopDockDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 0.5)
    }
}
