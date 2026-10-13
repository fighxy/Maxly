import SwiftUI
import MaxlyPresentation
import MaxlyUI

/// Полоса «играет голосовое» над чатом и списком чатов, как в популярных мессенджерах: пуск и
/// пауза, автор и время, скорость 1x / 1.5x / 2x (голос не искажается), закрыть. Касание по
/// имени — `onOpen`: чат открывается на сообщении и оно подсвечивается.
struct VoiceMiniBar: View {
    let model: VoiceNowPlaying
    let onOpen: (VoiceNowPlaying.Track) -> Void

    var body: some View {
        if let track = model.track {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button { model.toggle() } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.maxlyAccent)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(track.isPlaying ? "Пауза" : "Продолжить")
                    Button { onOpen(track) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("Голосовое сообщение · \(track.timeText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { model.cycleSpeed() } label: {
                        Text(VoiceNowPlaying.label(model.speed))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(model.speed > 1 ? Color.white : Color.primary)
                            .background(model.speed > 1 ? Color.maxlyAccent : Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Скорость \(VoiceNowPlaying.label(model.speed))")
                    Button { model.stop() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Закрыть")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.maxlyAccent)
                        .frame(width: proxy.size.width * min(max(track.progress, 0), 1))
                }
                .frame(height: 2)
            }
            .background(.bar)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
