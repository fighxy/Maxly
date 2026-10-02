import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Голосовое: круглая кнопка, дорожка громкости, время и кнопка расшифровки «→T».
///
/// Во время воспроизведения прослушанная часть дорожки закрашивается, а время показывает,
/// сколько уже прозвучало. Без текста в сообщении справа снизу стоит время отправки.
/// «→T»: пока сервер расшифровывает — круг загрузки, раскрытый текст —
/// кнопка «^» подсвечена, текст под дорожкой.
struct VoiceMessageView: View {
    let voice: VoiceContent
    let phase: VoicePhase
    let outgoing: Bool
    var time: AnyView?
    var transcript: TranscriptPhase = .collapsed
    /// `nil` — расшифровать нельзя (ещё не отправлено): кнопки нет.
    var onTranscribe: (() -> Void)?
    let onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                if let onTranscribe {
                    transcribeButton(onTranscribe)
                }
            }
            if transcript == .expanded, let text = voice.transcript {
                transcriptText(text)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(minWidth: 200, maxWidth: 280, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: transcript)
    }

    // MARK: Расшифровка

    /// «→T» свернуто, круг — идёт расшифровка, «^» на подсвеченной плашке — текст раскрыт.
    private func transcribeButton(_ action: @escaping () -> Void) -> some View {
        let expanded = transcript == .expanded
        return Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(transcribeFill(expanded: expanded))
                switch transcript {
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                        .tint(outgoing ? Color.white : Color.orbitleAccent)
                case .expanded:
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(outgoing ? Color.orbitleOutgoing : Color.white)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                case .collapsed:
                    Text(verbatim: "→T")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(outgoing ? Color.white : Color.orbitleAccent)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: 32, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(transcript == .loading)
        .accessibilityLabel(transcribeLabel)
    }

    private func transcribeFill(expanded: Bool) -> Color {
        if expanded { return outgoing ? Color.white : Color.orbitleAccent }
        return outgoing ? Color.white.opacity(0.2) : Color.orbitleAccent.opacity(0.14)
    }

    private var transcribeLabel: String {
        switch transcript {
        case .collapsed: "Расшифровать голосовое"
        case .loading: "Расшифровывается"
        case .expanded: "Скрыть расшифровку"
        }
    }

    @ViewBuilder
    private func transcriptText(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Text("Речь не распознана")
                .font(.footnote.italic())
                .foregroundStyle(secondary)
        } else {
            Text(trimmed)
                .font(.subheadline)
                .foregroundStyle(outgoing ? Color.white : Color.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
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
