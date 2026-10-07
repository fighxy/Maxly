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
        /// Палец на кнопке, полосы записи ещё нет: микрофон или камера уже включаются
        /// (короткое нажатие — смена режима).
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
    /// Микрофон или камера включены под пальцем, полосы записи ещё нет.
    @ObservationIgnored private var warming = false
    /// Идёт системный запрос доступа: отпущенный палец режим не меняет.
    @ObservationIgnored private var requestingAccess = false
    /// Номер нажатия: поздний ответ рекордера прежнего нажатия экран не трогает.
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var recorderQueue: Task<Void, Never>?
    /// Запись закреплена этим же нажатием: его отпускание не отправляет её.
    @ObservationIgnored private var lockedInPress = false

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

    /// Нажатие короче этого — смена режима, дольше — запись, как в Telegram. Микрофон или
    /// камера включаются сразу под пальцем, так что к этому моменту запись уже идёт.
    static let holdDelay: Duration = .milliseconds(150)

    func pressChanged(_ translation: CGSize) {
        switch phase {
        case .idle:
            press()
        case .recording:
            dragX = min(0, translation.width)
            dragY = min(0, translation.height)
            if dragX < -Self.cancelDistance {
                cancel()
            } else if dragY < -Self.lockDistance {
                phase = .locked
                lockedInPress = true
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
            if warming {
                // Короткое касание: включённый под пальцем микрофон или камера не нужны.
                warming = false
                discard(recordingMode)
                toggleMode()
            } else if !requestingAccess {
                toggleMode()
            }
        case .recording:
            send()
        case .locked:
            // Палец, закрепивший запись, отпускается — запись идёт дальше. Отправляет её
            // следующее нажатие той же кнопки. Раньше отпускание сразу отправляло запись.
            if lockedInPress {
                lockedInPress = false
            } else {
                send()
            }
        default:
            break
        }
        dragX = 0
        dragY = 0
    }

    /// Жест оборвался без отпускания пальца (окно запроса доступа, звонок): `pressEnded` не
    /// придёт. Нажатие без записи забывается, начатая запись закрепляется — её можно
    /// отправить или выбросить кнопками.
    func pressCancelled() {
        switch phase {
        case .pressing:
            pressTask?.cancel()
            pressTask = nil
            if warming {
                warming = false
                discard(recordingMode)
            }
            phase = .idle
        case .recording:
            phase = .locked
        default:
            break
        }
        lockedInPress = false
        dragX = 0
        dragY = 0
    }

    /// Палец лёг на кнопку: запись включается сразу, полоса записи — через `holdDelay`.
    private func press() {
        let current = mode
        attempt &+= 1
        lockedInPress = false
        phase = .pressing
        switch access(current) {
        case .granted:
            recordingMode = current
            warming = true
            onStart?()
            let attempt = attempt
            enqueue { [weak self] in
                guard let self else { return }
                await self.startRecorder(current, attempt: attempt)
            }
            pressTask = Task { [weak self] in
                try? await Task.sleep(for: Self.holdDelay)
                guard let self, !Task.isCancelled, self.phase == .pressing, self.warming else { return }
                self.warming = false
                self.phase = .recording
                Self.haptic(.light)
            }
        case .undetermined:
            // Первое касание спрашивает систему; запись не начинается, палец уходит к окну запроса.
            requestingAccess = true
            Task { [weak self] in
                if current == .voice {
                    _ = await VoiceRecorder.requestPermission()
                } else {
                    _ = await VideoNoteRecorder.requestPermissions()
                }
                self?.requestingAccess = false
            }
        case .denied:
            show(current == .voice
                 ? "Нет доступа к микрофону. Разрешите его в Настройках"
                 : "Нет доступа к камере или микрофону. Разрешите их в Настройках")
        }
    }

    // MARK: Запись

    /// Включение микрофона или камеры. Не вышло — полоса записи уходит, если это нажатие ещё идёт.
    private func startRecorder(_ current: Mode, attempt: Int) async {
        do {
            switch current {
            case .voice: try await voice.start()
            case .video: try await video.start()
            }
        } catch {
            Log.warning(.media, "Запись не началась: \(error)")
            guard attempt == self.attempt, phase == .pressing || phase == .recording || phase == .locked else { return }
            pressTask?.cancel()
            pressTask = nil
            warming = false
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
        let attempt = attempt
        enqueue { [weak self] in
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
            if attempt == self.attempt, self.phase == .finishing { self.phase = .idle }
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
        case .pressing where warming:
            warming = false
            discard(recordingMode)
        case .recording, .locked:
            discard(recordingMode)
            Self.haptic(.rigid)
        default:
            break
        }
        if phase != .finishing { phase = .idle }
        dragX = 0
        dragY = 0
    }

    private func discard(_ current: Mode) {
        enqueue { [weak self] in
            guard let self else { return }
            if current == .voice { await self.voice.cancel() } else { self.video.cancel() }
        }
    }

    /// Включение, остановка и выброс записи идут по очереди: короткое касание выключает
    /// микрофон уже после того, как он включился, а следующее нажатие ждёт выключения.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = recorderQueue
        recorderQueue = Task { @MainActor in
            await previous?.value
            await operation()
        }
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

    private enum Access {
        case granted
        case undetermined
        case denied
    }

    /// Доступ к микрофону (и камере для кружка) без запроса: так нажатие не ждёт.
    private func access(_ mode: Mode) -> Access {
        let microphone = AVAudioApplication.shared.recordPermission
        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        switch mode {
        case .voice:
            if microphone == .granted { return .granted }
            return microphone == .undetermined ? .undetermined : .denied
        case .video:
            if microphone == .granted, camera == .authorized { return .granted }
            return microphone == .undetermined || camera == .notDetermined ? .undetermined : .denied
        }
    }

    private static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
