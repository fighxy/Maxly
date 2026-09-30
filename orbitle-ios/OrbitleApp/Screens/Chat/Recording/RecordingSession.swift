import AVFoundation
import Foundation
import Observation
import OrbitleDomain
import UIKit

/// Запись голосового или кружка из поля ввода.
///
/// Кнопка справа (когда поле пустое) — микрофон или камера. Удержание — запись, отпустить —
/// отправить. Увести палец влево — отмена, вверх — закрепить запись, тогда её отправляет
/// нажатие той же кнопки, а корзина слева отменяет. Короткое нажатие переключает микрофон
/// и камеру. Выбор режима запоминается.
@MainActor
@Observable
final class RecordingSession {
    enum Mode: String {
        case voice
        case video
    }

    enum Phase: Equatable {
        case idle
        /// Палец на кнопке, запись ещё не началась (короткое нажатие — смена режима).
        case pressing
        case recording
        /// Запись закреплена свайпом вверх: палец можно убрать.
        case locked
        /// Остановка и подготовка файла.
        case finishing
    }

    private(set) var mode: Mode
    private(set) var phase: Phase = .idle
    /// Сдвиг пальца влево (≤ 0) — насколько близко отмена.
    private(set) var dragX: CGFloat = 0
    /// Сдвиг пальца вверх (≤ 0) — насколько близко закрепление.
    private(set) var dragY: CGFloat = 0
    /// Подсказка над полем ввода: после короткого нажатия или когда записать нельзя.
    private(set) var hint: String?

    let voice = VoiceRecorder()
    let video = VideoNoteRecorder()

    /// Готовая запись для отправки.
    @ObservationIgnored var onRecorded: ((AttachmentDraft) -> Void)?
    /// Запись началась: остановить воспроизведение голосовых.
    @ObservationIgnored var onStart: (() -> Void)?

    static let cancelDistance: CGFloat = 120
    static let lockDistance: CGFloat = 90
    private static let modeKey = "chat.recordMode"

    @ObservationIgnored private var pressTask: Task<Void, Never>?
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    /// Режим, в котором идёт текущая запись.
    @ObservationIgnored private var recordingMode: Mode = .voice

    init() {
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .voice
        voice.onLimit = { [weak self] in self?.send() }
        video.onLimit = { [weak self] in self?.send() }
    }

    /// Идёт запись (или её остановка): вместо поля ввода — полоса записи.
    var isActive: Bool {
        phase == .recording || phase == .locked || phase == .finishing
    }

    var isVideo: Bool { recordingMode == .video && isActive }

    var elapsed: TimeInterval {
        recordingMode == .voice ? voice.elapsed : video.elapsed
    }

    var level: Double { recordingMode == .voice ? voice.level : 0 }

    // MARK: Жест кнопки

    func pressChanged(_ translation: CGSize) {
        switch phase {
        case .idle:
            phase = .pressing
            pressTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard let self, !Task.isCancelled, self.phase == .pressing else { return }
                await self.begin()
            }
        case .recording:
            dragX = min(0, translation.width)
            dragY = min(0, translation.height)
            if dragX < -Self.cancelDistance {
                cancel()
            } else if dragY < -Self.lockDistance {
                phase = .locked
                dragX = 0
                dragY = 0
                Self.haptic(.medium)
            }
        default:
            break
        }
    }

    func pressEnded() {
        switch phase {
        case .pressing:
            pressTask?.cancel()
            pressTask = nil
            phase = .idle
            toggleMode()
        case .recording:
            send()
        case .locked:
            // Закреплённую запись отправляет нажатие той же кнопки.
            send()
        default:
            break
        }
        dragX = 0
        dragY = 0
    }

    // MARK: Запись

    private func begin() async {
        let current = mode
        guard await permitted(current) else {
            phase = .idle
            return
        }
        // Палец могли убрать, пока шёл запрос доступа.
        guard phase == .pressing else { return }
        recordingMode = current
        onStart?()
        phase = .recording
        Self.haptic(.light)
        do {
            switch current {
            case .voice: try voice.start()
            case .video: try await video.start()
            }
        } catch {
            Log.warning(.media, "Запись не началась: \(error)")
            phase = .idle
            show(current == .voice ? "Не удалось включить микрофон" : "Не удалось включить камеру")
        }
    }

    /// Остановить и отправить.
    func send() {
        guard phase == .recording || phase == .locked else { return }
        phase = .finishing
        dragX = 0
        dragY = 0
        let current = recordingMode
        Task { [weak self] in
            guard let self else { return }
            let draft: AttachmentDraft?
            switch current {
            case .voice:
                draft = await self.voice.stop().map {
                    AttachmentDraft.voice(path: $0.url.path, durationMs: $0.durationMs, waveform: $0.waveform)
                }
            case .video:
                draft = await self.video.stop().map {
                    AttachmentDraft.videoNote(path: $0.url.path, durationMs: $0.durationMs, side: $0.side)
                }
            }
            self.phase = .idle
            if let draft {
                Self.haptic(.light)
                self.onRecorded?(draft)
            }
        }
    }

    /// Выбросить запись (свайп влево, корзина, уход с экрана).
    func cancel() {
        pressTask?.cancel()
        pressTask = nil
        switch phase {
        case .recording, .locked:
            if recordingMode == .voice { voice.cancel() } else { video.cancel() }
            Self.haptic(.rigid)
        default:
            break
        }
        if phase != .finishing { phase = .idle }
        dragX = 0
        dragY = 0
    }

    private func toggleMode() {
        mode = mode == .voice ? .video : .voice
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        Self.haptic(.soft)
        show(mode == .voice
             ? "Удерживайте, чтобы записать голосовое. Нажмите — для видеосообщения"
             : "Удерживайте, чтобы записать видеосообщение. Нажмите — для голосового")
    }

    private func show(_ text: String) {
        hint = text
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.hint = nil
        }
    }

    /// Доступ к микрофону (и камере для кружка). Первый раз спрашивается системой, запись
    /// тогда не начинается: палец уже убран ради окна запроса.
    private func permitted(_ mode: Mode) async -> Bool {
        let microphone = AVAudioApplication.shared.recordPermission
        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        switch mode {
        case .voice:
            if microphone == .granted { return true }
            if microphone == .undetermined {
                _ = await VoiceRecorder.requestPermission()
                return false
            }
            show("Нет доступа к микрофону. Разрешите его в Настройках")
            return false
        case .video:
            if microphone == .granted, camera == .authorized { return true }
            if microphone == .undetermined || camera == .notDetermined {
                _ = await VideoNoteRecorder.requestPermissions()
                return false
            }
            show("Нет доступа к камере или микрофону. Разрешите их в Настройках")
            return false
        }
    }

    private static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
