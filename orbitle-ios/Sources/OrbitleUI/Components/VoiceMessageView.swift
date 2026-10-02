import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Голосовое: круглая кнопка, дорожка громкости, время и кнопка расшифровки «→T».
///
/// Во время воспроизведения прослушанная часть дорожки закрашивается, а время показывает,
/// сколько уже прозвучало.
///
/// Раскладка как у привычных мессенджеров. Сверху кнопка, дорожка и длительность под
/// ней; кнопка расшифровки — в правом верхнем углу пузыря. Время отправки и галочки — в
/// правом нижнем углу, как у любого сообщения: под кнопкой расшифровки, а при раскрытом
/// тексте — в конце его последней строки. Если у пузыря есть реакции, время уходит в их
/// ряд (это решает `MessageBubble` и тогда не передаёт `time`).
/// Расшифровка: капсула 40×28 с бледной заливкой цвета акцента; «→Т» свёрнуто,
/// круг — идёт расшифровка, «^» — текст раскрыт. Раскрытый текст — во всю ширину пузыря.
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
            HStack(alignment: .top, spacing: 10) {
                button
                VStack(alignment: .leading, spacing: 3) {
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
                    }
                }
                .padding(.top, 2)
                // Дорожка занимает всё место между кнопкой и правой колонкой: пустого
                // промежутка перед кнопкой расшифровки нет, в широком пузыре она тянется.
                .frame(maxWidth: .infinity, alignment: .leading)
                trailingColumn
            }
            if isOpen {
                transcriptBody
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        // Без верхнего предела: пузырь шире (реакции, подпись, пост канала) — ряд тянется
        // на всю его ширину, кнопка расшифровки у правого края.
        .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: transcript)
    }

    /// Правый край верхнего ряда: кнопка расшифровки наверху, время с галочками внизу,
    /// на уровне низа круглой кнопки. При раскрытом тексте время уходит под текст.
    @ViewBuilder
    private var trailingColumn: some View {
        let showsTime = time != nil && !isOpen
        if onTranscribe != nil || showsTime {
            VStack(alignment: .trailing, spacing: 0) {
                if let onTranscribe {
                    transcribeButton(onTranscribe)
                }
                Spacer(minLength: 2)
                if showsTime, let time { time }
            }
            // Высота задана явно: пузырь меряет себя по идеальной высоте, и распорка без
            // заданной высоты сжималась бы в ноль. С крупным шрифтом строка времени растёт.
            .frame(height: max(Self.playSize, (onTranscribe != nil ? 30 : 0) + (showsTime ? timeLine : 0)))
        }
    }

    /// Высота строки времени с галочками при текущем размере шрифта.
    @ScaledMetric(relativeTo: .caption2) var timeLine: CGFloat = 14

    private static let playSize: CGFloat = 44

    private var isOpen: Bool {
        transcript == .failed || (transcript == .expanded && voice.transcript != nil)
    }

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
            .frame(width: Self.playSize, height: Self.playSize)
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
        let wave = voice.waveform
        let played = (phase.isPlaying || isPaused) ? phase.progress : 0
        let active = outgoing ? Color.white : Color.orbitleAccent
        let rest = outgoing ? Color.white.opacity(0.45) : Color.orbitleAccent.opacity(0.35)
        return Canvas { context, size in
            // Столбики на всю данную ширину: число — сколько влезает, остаток — в зазоры.
            let layout = WaveformLayout(width: Double(size.width), barWidth: Self.barWidth, spacing: Self.barSpacing)
            for (index, height) in layout.heights(samples: wave).enumerated() {
                let h = max(3, size.height * height)
                let bar = CGFloat(layout.barWidth)
                let rect = CGRect(x: CGFloat(layout.x(of: index)), y: (size.height - h) / 2, width: bar, height: h)
                let color = layout.isPlayed(index, progress: played) ? active : rest
                context.fill(Path(roundedRect: rect, cornerRadius: bar / 2), with: .color(color))
            }
        }
        .frame(height: 22)
        // Идеальная ширина от длительности задаёт ширину пузыря; данная — заполняется целиком.
        .frame(minWidth: 72, idealWidth: waveWidth, maxWidth: .infinity)
        .animation(.linear(duration: 0.1), value: phase.progress)
        .accessibilityHidden(true)
    }

    private static let barWidth: Double = 3
    private static let barSpacing: Double = 2

    private var waveWidth: CGFloat {
        let seconds = CGFloat(max(voice.durationMs, 0)) / 1000
        return min(190, max(96, 70 + seconds * 2.4))
    }

    private var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }
}
