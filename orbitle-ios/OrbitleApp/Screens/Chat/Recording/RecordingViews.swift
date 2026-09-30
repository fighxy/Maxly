import SwiftUI
import OrbitleUI

/// Кнопка записи справа от поля ввода: микрофон или камера.
///
/// Жест висит на этой кнопке всё время записи (SwiftUI обрывает жест, если его вид
/// пропадает), поэтому во время записи меняется только её вид: крупный круг под пальцем
/// с пульсом громкости, над ним — подсказка «вверх — закрепить».
struct RecordButton: View {
    let session: RecordingSession

    var body: some View {
        ZStack {
            if session.phase == .locked || session.phase == .finishing {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.orbitleAccent, in: Circle())
            } else {
                Image(systemName: session.mode == .voice ? "mic" : "video")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
                    .orbitleGlassCircle(size: 44)
                    .opacity(session.phase == .recording ? 0 : 1)
            }
        }
        .frame(width: 44, height: 44)
        .overlay {
            if session.phase == .recording {
                recordingKnob
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if session.phase == .recording {
                lockHint
                    .offset(y: -86 + max(session.dragY, -RecordingSession.lockDistance) * 0.4)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { session.pressChanged($0.translation) }
                .onEnded { _ in session.pressEnded() }
        )
        .animation(.spring(duration: 0.25), value: session.phase)
        .animation(.spring(duration: 0.3), value: session.mode)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(session.phase == .idle ? "Удерживайте для записи, нажмите для смены режима" : "")
    }

    /// Круг под пальцем: идёт за ним влево и вверх, пульсирует от громкости.
    private var recordingKnob: some View {
        ZStack {
            Circle()
                .fill(Color.orbitleAccent.opacity(0.25))
                .frame(width: 84, height: 84)
                .scaleEffect(1 + session.level * 0.6)
                .animation(.easeOut(duration: 0.12), value: session.level)
            Circle()
                .fill(Color.orbitleAccent)
                .frame(width: 84, height: 84)
            Image(systemName: session.mode == .voice ? "mic.fill" : "video.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
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
        .orbitleGlassRounded(radius: 18)
    }

    private var accessibilityLabel: String {
        switch session.phase {
        case .locked, .finishing: "Отправить запись"
        default: session.mode == .voice ? "Голосовое сообщение" : "Видеосообщение"
        }
    }
}

/// Полоса записи вместо поля ввода: точка, время и «влево — отмена» (или корзина, когда
/// запись закреплена).
struct RecordingBar: View {
    let session: RecordingSession
    @State private var blink = false

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
                .opacity(blink ? 0.25 : 1)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: blink)
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
        .orbitleGlassCapsule()
        .accessibilityElement(children: .contain)
    }

    /// `0:07,4` — минуты, секунды и десятые, как в Telegram.
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
                    CameraPreview(session: session.video.session)
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                    Circle()
                        .trim(from: 0, to: min(1, session.elapsed / VideoNoteRecorder.maximumDuration))
                        .stroke(Color.orbitleAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
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
