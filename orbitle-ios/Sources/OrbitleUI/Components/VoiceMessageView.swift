import SwiftUI
import OrbitleDomain
import OrbitlePresentation

struct VoiceMessageView: View {
    let voice: VoiceContent
    let phase: VoicePhase
    let outgoing: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                button
                bars
                Text(ChatContentFormat.clock(ms: voice.durationMs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(outgoing ? Color.white.opacity(0.85) : Color.secondary)
            }
            if let transcript = voice.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.footnote)
                    .foregroundStyle(outgoing ? Color.white.opacity(0.9) : Color.primary)
            }
            if case .failed = phase {
                Text("Не удалось воспроизвести")
                    .font(.caption2)
                    .foregroundStyle(outgoing ? Color.white.opacity(0.85) : Color.red)
            }
        }
    }

    private var button: some View {
        Button(action: onToggle) {
            ZStack {
                Circle().fill(outgoing ? Color.white.opacity(0.2) : Color.orbitleAccent)
                symbol
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(outgoing ? Color.white : Color.white)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(phase.isPlaying ? "Пауза" : "Воспроизвести")
    }

    @ViewBuilder
    private var symbol: some View {
        switch phase {
        case .downloading:
            ProgressView().tint(.white)
        case .playing:
            Image(systemName: "pause.fill")
        case .failed:
            Image(systemName: "exclamationmark")
        case .idle, .paused:
            Image(systemName: "play.fill")
        }
    }

    private var bars: some View {
        let samples = ChatContentFormat.waveBars(samples: voice.waveform)
        return HStack(alignment: .center, spacing: 2) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(barColor(index: index, count: samples.count))
                    .frame(width: 3, height: max(4, 28 * height))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private func barColor(index: Int, count: Int) -> Color {
        let played = phase.progress * Double(max(count, 1))
        let active = Double(index) < played
        if outgoing {
            return Color.white.opacity(active ? 0.95 : 0.4)
        }
        return active ? Color.orbitleAccent : Color.secondary.opacity(0.45)
    }
}
