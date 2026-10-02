import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Голосовое: круглая кнопка, дорожка громкости, время и кнопка расшифровки «→T».
///
/// Во время воспроизведения прослушанная часть дорожки закрашивается, а время показывает,
/// сколько уже прозвучало. Без текста в сообщении справа снизу стоит время отправки.
/// Расшифровка, как в Komet (KometTeam/Komet#147): капсула 40×28 с бледной заливкой цвета
/// акцента; «→Т» свёрнуто, круг — идёт расшифровка, «^» — текст раскрыт. Значок сменяется
/// растворением с масштабом. Раскрытый текст — во всю ширину пузыря, время переезжает в
/// конец его последней строки.
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
                        if let time, !isOpen { time }
                    }
                }
                if let onTranscribe {
                    transcribeButton(onTranscribe)
                }
            }
            if isOpen {
                transcriptBody
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(minWidth: 200, maxWidth: 280, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: transcript)
    }

    /// Текст расшифровки или ошибка раскрыты под дорожкой.
    private var isOpen: Bool {
        transcript == .failed || (transcript == .expanded && voice.transcript != nil)
    }

    // MARK: Расшифровка

    /// Акцент голосового: белый в своём пузыре, фирменный — в чужом.
    private var accent: Color {
        outgoing ? Color.white : Color.orbitleAccent
    }

    private func transcribeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                glyph
                    .id(glyphKey)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            .frame(width: 40, height: 28)
            .background(accent.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: glyphKey)
        }
        .buttonStyle(.plain)
        .disabled(transcript == .loading)
        .accessibilityLabel(transcribeLabel)
    }

    /// Значок капсулы: меняется вместе с состоянием, сворачивание и ошибка — один «^».
    private var glyphKey: Int {
        switch transcript {
        case .collapsed: 0
        case .loading: 1
        case .expanded, .failed: 2
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch transcript {
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .tint(accent)
        case .expanded, .failed:
            Image(systemName: "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
        case .collapsed:
            Text(verbatim: "→Т")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent)
        }
    }

    private var transcribeLabel: String {
        switch transcript {
        case .collapsed: "Расшифровать"
        case .loading: "Расшифровывается"
        case .expanded, .failed: "Скрыть расшифровку"
        }
    }

    /// Текст во всю ширину обычным размером; время — в конце последней строки, под него
    /// оставлено невидимое место, чтобы строка не заходила под время.
    private var transcriptBody: some View {
        ZStack(alignment: .bottomTrailing) {
            (transcriptText + Text(verbatim: time == nil ? "" : "\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}").font(.caption2))
                .font(.body)
                .foregroundStyle(transcript == .failed ? secondary : (outgoing ? Color.white : Color.primary))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let time { time }
        }
    }

    private var transcriptText: Text {
        if transcript == .failed { return Text("Не удалось расшифровать").italic() }
        let trimmed = (voice.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Text("Речь не распознана").italic() : Text(trimmed)
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
