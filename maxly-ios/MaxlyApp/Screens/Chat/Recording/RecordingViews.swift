import SwiftUI
import MaxlyUI

/// Кнопка записи справа от поля ввода: микрофон (голосовое) или камера (кружок, а короткое
/// нажатие — снимок).
///
/// Жест висит на этой кнопке всё время записи (SwiftUI обрывает жест, если его вид
/// пропадает), поэтому во время записи меняется только её вид: крупный круг под пальцем
/// с пульсом громкости, над ним — подсказка «вверх — закрепить».
struct RecordButton: View {
    let session: RecordingSession
    let mode: RecordingSession.Mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Палец на кнопке. Сброс без `onEnded` — жест оборвала система.
    @GestureState private var touching = false

    /// Нажатие или запись идут на этой кнопке.
    private var mine: Bool { session.phase != .idle && session.recordingMode == mode }

    var body: some View {
        ZStack {
            if mine, session.phase == .locked || session.phase == .finishing {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.maxlyOnAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.maxlyAccent, in: Circle())
            } else if mode == .voice {
                // Микрофон — главная кнопка пустого поля, как в WhatsApp: залитый круг.
                Image(systemName: "mic.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.maxlyOnAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.maxlyAccent, in: Circle())
                    .opacity(mine && session.phase == .recording ? 0 : 1)
            } else {
                Image(systemName: "camera")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .maxlyGlassCircle(size: 44)
                    .opacity(mine && session.phase == .recording ? 0 : 1)
            }
        }
        .frame(width: 44, height: 44)
        .overlay {
            if mine, session.phase == .recording {
                recordingKnob
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if mine, session.phase == .recording {
                lockHint
                    .offset(y: -86 + max(session.dragY, -RecordingSession.lockDistance) * 0.4)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { session.pressChanged($0.translation, mode: mode) }
                .onEnded { _ in session.pressEnded(mode: mode) }
        )
        .onChange(of: touching) { _, live in
            // Обычное отпускание уже отработало в `onEnded`; здесь остаётся только обрыв жеста.
            guard !live, session.recordingMode == mode else { return }
            Task { @MainActor in session.pressCancelled() }
        }
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: session.phase)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(session.phase != .idle ? "" : mode == .voice
            ? "Удерживайте, чтобы записать голосовое"
            : "Нажмите — снимок, удерживайте — видеосообщение")
    }

    /// Круг под пальцем: идёт за ним влево и вверх, пульсирует от громкости.
    private var recordingKnob: some View {
        ZStack {
            Circle()
                .fill(Color.maxlyAccent.opacity(0.25))
                .frame(width: 84, height: 84)
                .scaleEffect(reduceMotion ? 1 : 1 + session.level * 0.6)
                .animation(.easeOut(duration: 0.12), value: session.level)
            Circle()
                .fill(Color.maxlyAccent)
                .frame(width: 84, height: 84)
            Image(systemName: mode == .voice ? "mic.fill" : "video.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.maxlyOnAccent)
        }
        .offset(x: session.dragX, y: session.dragY)
    }

    private var lockHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 14, weight: .semibold))
            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.secondary)
        .frame(width: 36, height: 64)
        .maxlyGlassRounded(radius: 18)
    }

    private var accessibilityLabel: String {
        if mine, session.phase == .locked || session.phase == .finishing { return "Отправить запись" }
        return mode == .voice ? "Голосовое сообщение" : "Камера"
    }
}

/// Полоса записи вместо поля ввода: точка, время и «влево — отмена» (или корзина, когда
/// запись закреплена).
struct RecordingBar: View {
    let session: RecordingSession
    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            if session.phase == .locked {
                Button {
                    session.cancel()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить запись")
            }
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(!reduceMotion && blink ? 0.25 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: blink)
                .onAppear { blink = true }
            Text(Self.clock(session.elapsed))
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if session.phase == .recording {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Влево — отмена")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .offset(x: session.dragX * 0.5)
                .opacity(1 - min(1, -session.dragX / RecordingSession.cancelDistance) * 0.7)
            } else if session.phase == .finishing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.leading, session.phase == .locked ? 6 : 16)
        .padding(.trailing, 16)
        .frame(minHeight: 44)
        .maxlyGlassCapsule()
        .accessibilityElement(children: .contain)
    }

    /// `0:07,4` — минуты, секунды и десятые.
    static func clock(_ seconds: TimeInterval) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded(.down))
        return String(format: "%d:%02d,%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }
}

/// Кружок во время записи: затемнение, живая картинка камеры в круге и кольцо минуты.
struct VideoNoteOverlay: View {
    let session: RecordingSession
    private let diameter: CGFloat = 260

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    NoteCameraPreview(session: session.video.session)
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                    Circle()
                        .trim(from: 0, to: min(1, session.elapsed / VideoNoteRecorder.maximumDuration))
                        .stroke(Color.maxlyAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: diameter + 12, height: diameter + 12)
                        .animation(.linear(duration: 0.1), value: session.elapsed)
                }
                Text(RecordingBar.clock(session.elapsed))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .offset(y: -40)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}
