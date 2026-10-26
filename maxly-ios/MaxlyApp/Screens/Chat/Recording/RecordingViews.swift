import UIKit
import SwiftUI
import MaxlyUI
import MaxlyPresentation

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
    @State private var press = RecordingPressState()

    /// Нажатие или запись идут на этой кнопке.
    private var mine: Bool { session.phase != .idle && session.recordingMode == mode }

    var body: some View {
        ZStack {
            if mine, session.phase == .locked || session.phase == .finishing || session.phase == .reviewing {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.maxlyOnAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.maxlyAccent, in: Circle())
            } else if mode == .voice {
                // Микрофон — главная кнопка пустого поля: залитый круг.
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
                .onChanged { value in
                    if press.begin() { session.pressBegan(mode: mode) }
                    session.pressChanged(value.translation, mode: mode)
                }
                .onEnded { _ in
                    guard press.end(generation: press.generation) else { return }
                    session.pressEnded(mode: mode)
                }
        )
        .onChange(of: touching) { _, live in
            // Обычное отпускание уже отработало в `onEnded`; здесь остаётся только обрыв жеста.
            guard !live, session.recordingMode == mode else { return }
            let generation = press.generation
            Task { @MainActor in
                guard !touching, press.end(generation: generation), session.recordingMode == mode else { return }
                session.pressCancelled()
            }
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
        if mine, session.phase == .locked || session.phase == .finishing || session.phase == .reviewing { return "Отправить запись" }
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
        if session.phase == .reviewing, let review = session.review {
            reviewBar(review)
        } else if session.phase == .reviewing, let voiceReview = session.voiceReview {
            voiceReviewBar(voiceReview)
        } else {
            recordingBar
        }
    }

    /// Просмотр голосового: корзина, воспроизведение и волна с ручками обрезки.
    private func voiceReviewBar(_ review: VoiceReview) -> some View {
        HStack(spacing: 6) {
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
            .accessibilityLabel("Удалить голосовое")
            VoiceReviewStrip(review: review)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(minHeight: 44)
        .maxlyGlassCapsule()
    }

    /// Просмотр кружка: корзина и полоса обрезки; отправляет кнопка справа.
    private func reviewBar(_ review: VideoNoteReview) -> some View {
        HStack(spacing: 8) {
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
            .accessibilityLabel("Удалить кружок")
            VideoNoteTrimStrip(review: review)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
        .maxlyGlassCapsule()
    }

    private var recordingBar: some View {
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
                .fill(session.isPaused ? Color.secondary : Color.red)
                .frame(width: 10, height: 10)
                .opacity(session.isPaused ? 1 : (!reduceMotion && blink ? 0.25 : 1))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: blink)
                .onAppear { blink = true }
            Text(Self.clock(session.elapsed))
                .font(.app(.body).monospacedDigit())
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if session.phase == .recording {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Влево — отмена")
                        .font(.app(.subheadline))
                }
                .foregroundStyle(.secondary)
                .offset(x: session.dragX * 0.5)
                .opacity(1 - min(1, -session.dragX / RecordingSession.cancelDistance) * 0.7)
            } else if session.phase == .finishing {
                ProgressView()
                    .controlSize(.small)
            } else if session.phase == .locked {
                // Пауза и продолжение записи.
                Button {
                    session.togglePause()
                } label: {
                    Image(systemName: session.isPaused ? (session.recordingMode == .voice ? "mic.fill" : "video.fill") : "pause.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.isPaused ? "Продолжить запись" : "Пауза")
                // «Стоп»: запись на просмотр — прослушать или посмотреть, обрезать, потом отправить.
                Button {
                    session.stopForReview()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Остановить и посмотреть")
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

/// Кружок во время записи: размытый чат, большой круг камеры с кольцом минуты,
/// а слева внизу над полем ввода — смена камеры и вспышка. Время и «Влево — отмена» показывает
/// само поле ввода.
struct VideoNoteOverlay: View {
    let session: RecordingSession
    /// Верх поля ввода в глобальных координатах: кнопки стоят над ним. `0` — неизвестно.
    var controlsTop: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let bottomInset = controlsTop > 0 ? max(0, frame.maxY - controlsTop) : 90
            let free = max(0, geo.size.height - bottomInset)
            let diameter = max(160, min(geo.size.width - 24, free - 140))
            ZStack {
                // Фон, круг и кольцо касания не ловят: палец держит кнопку записи под ними.
                // Фон — до поля ввода: время, «Влево — отмена» и кнопка записи остаются чёткими.
                background
                    .frame(height: free)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if let review = session.review, session.phase == .reviewing {
                    reviewCircle(review, diameter)
                        .position(x: geo.size.width / 2, y: max(diameter / 2 + 12, free * 0.45))
                } else {
                    circle(diameter)
                        .position(x: geo.size.width / 2, y: max(diameter / 2 + 12, free * 0.45))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    // Нажимаются вторым пальцем, пока первый держит кнопку записи, или после закрепления.
                    HStack(spacing: 14) {
                        flipButton
                        flashButton
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, bottomInset + 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .transition(.opacity)
        .onChange(of: session.video.screenFlash) { _, on in brightness.set(on) }
        .onDisappear { brightness.set(false) }
    }

    /// Размытый чат; со вспышкой фронтальной камеры — белый экран на полной яркости.
    @ViewBuilder
    private var background: some View {
        if session.video.screenFlash {
            Color.white
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    /// Записанный кружок по кругу: без звука, касание включает и выключает звук.
    private func reviewCircle(_ review: VideoNoteReview, _ diameter: CGFloat) -> some View {
        VideoNotePlayerView(player: review.player)
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay(alignment: .bottom) {
                Image(systemName: review.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.5), in: Circle())
                    .padding(.bottom, 18)
            }
            .contentShape(Circle())
            .onTapGesture { review.toggleMuted() }
            .accessibilityElement()
            .accessibilityLabel(review.muted ? "Включить звук кружка" : "Выключить звук кружка")
            .accessibilityAddTraits(.isButton)
    }

    private func circle(_ diameter: CGFloat) -> some View {
        ZStack {
            NoteCameraPreview(session: session.video.session)
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
            Circle()
                .trim(from: 0, to: min(1, session.elapsed / VideoNoteRecorder.maximumDuration))
                .stroke(Color.maxlyAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter + 10, height: diameter + 10)
                .animation(.linear(duration: 0.1), value: session.elapsed)
        }
    }

    @State private var brightness = ScreenBrightness()

    /// Вспышка: фонарик основной камеры или белый экран для фронтальной.
    private var flashButton: some View {
        Button {
            session.video.toggleFlash()
        } label: {
            Image(systemName: session.video.flashOn ? "bolt.fill" : "bolt.slash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(session.video.flashOn ? Color.orange : Color.primary)
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.video.flashOn ? "Выключить вспышку" : "Включить вспышку")
    }

    /// Сменить камеру, не прерывая запись.
    private var flipButton: some View {
        Button {
            Task { await session.video.switchCamera() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.video.usesFrontCamera ? "Переключить на основную камеру" : "Переключить на фронтальную камеру")
    }
}

/// Яркость экрана на время вспышки фронтальной камеры: полная, потом прежняя.
@MainActor
final class ScreenBrightness {
    private var saved: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    func set(_ bright: Bool) {
        guard let screen else { return }
        if bright {
            if saved == nil { saved = screen.brightness }
            screen.brightness = 1
        } else if let saved {
            screen.brightness = saved
            self.saved = nil
        }
    }
}
