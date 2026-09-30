import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Голосовое: круглая кнопка, дорожка громкости и время.
///
/// Во время воспроизведения прослушанная часть дорожки закрашивается, а время показывает,
/// сколько уже прозвучало. Без текста в сообщении справа снизу стоит время отправки.
struct VoiceMessageView: View {
    let voice: VoiceContent
    let phase: VoicePhase
    let outgoing: Bool
    var time: AnyView?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                button
                VStack(alignment: .leading, spacing: 4) {
                    bars
                    HStack(spacing: 6) {
                        Text(ChatContentFormat.voiceClock(durationMs: voice.durationMs, phase: phase))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(secondary)
                        if case .failed = phase {
                            Text("Не удалось воспроизвести")
                                .font(.caption2)
                                .foregroundStyle(outgoing ? Color.white.opacity(0.85) : Color.red)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let time { time }
                    }
                }
            }
            if let transcript = voice.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.footnote)
                    .foregroundStyle(outgoing ? Color.white.opacity(0.9) : Color.primary)
            }
        }
        .frame(minWidth: 200, maxWidth: 280, alignment: .leading)
    }

    private var secondary: Color {
        outgoing ? Color.white.opacity(0.8) : Color.secondary
    }

    private var button: some View {
        Button(action: onToggle) {
            ZStack {
                Circle().fill(outgoing ? Color.white : Color.orbitleAccent)
                symbol
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(outgoing ? Color.orbitleOutgoing : Color.white)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(phase.isPlaying ? "Пауза" : "Воспроизвести голосовое, \(ChatContentFormat.clock(ms: voice.durationMs))")
    }

    @ViewBuilder
    private var symbol: some View {
        switch phase {
        case .downloading:
            ProgressView().tint(outgoing ? Color.orbitleOutgoing : .white)
        case .playing:
            Image(systemName: "pause.fill")
        case .failed:
            Image(systemName: "exclamationmark")
        case .idle, .paused:
            Image(systemName: "play.fill").offset(x: 1)
        }
    }

    private var bars: some View {
        let samples = ChatContentFormat.waveBars(samples: voice.waveform, count: 36)
        return HStack(alignment: .center, spacing: 2) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(barColor(index: index, count: samples.count))
                    .frame(width: 2.5, height: max(3, 22 * height))
            }
        }
        .frame(height: 22, alignment: .center)
        .animation(.linear(duration: 0.1), value: phase.progress)
        .accessibilityHidden(true)
    }

    private func barColor(index: Int, count: Int) -> Color {
        let played = phase.progress * Double(max(count, 1))
        let active = (phase.isPlaying || isPaused) && Double(index) < played
        if outgoing {
            return Color.white.opacity(active ? 1 : 0.45)
        }
        return active ? Color.orbitleAccent : Color.orbitleAccent.opacity(0.35)
    }

    private var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }
}
