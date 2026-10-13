import AVFoundation
import Foundation
import Observation
import MaxlyDomain
import UIKit

/// Запись голосового или кружка из поля ввода, как в WhatsApp: у каждой записи своя кнопка.
///
/// Микрофон: удержание — голосовое. Камера: удержание — кружок, короткое нажатие — снимок
/// (`onCameraTap`). Отпустить — отправить. Увести палец влево — отмена, вверх — закрепить
/// запись, тогда её отправляет нажатие той же кнопки, а корзина слева отменяет.
@MainActor
@Observable
final class RecordingSession {
    enum Mode: String {
        case voice
        case video
    }

    enum Phase: Equatable {
        case idle
        /// Палец на кнопке: ожидание удержания, разрешения или готовности рекордера.
        case pressing
        case recording
        /// Запись закреплена свайпом вверх: палец можно убрать.
        case locked
        /// Остановка и подготовка файла.
        case finishing
        /// Кружок остановлен кнопкой «стоп»: просмотр, обрезка, отправка или корзина.
        case reviewing
    }

    private(set) var phase: Phase = .idle
    /// Режим текущего нажатия или записи: другая кнопка на это время прячется.
    private(set) var recordingMode: Mode = .voice
    /// Сдвиг пальца влево (≤ 0) — насколько близко отмена.
    private(set) var dragX: CGFloat = 0
    /// Сдвиг пальца вверх (≤ 0) — насколько близко закрепление.
    private(set) var dragY: CGFloat = 0
    /// Подсказка над полем ввода: после короткого нажатия или когда записать нельзя.
    private(set) var hint: String?

    let voice = VoiceRecorder()
    let video = VideoNoteRecorder()
    /// Записанный кружок на просмотре (`reviewing`).
    private(set) var review: VideoNoteReview?
    /// Записанное голосовое на просмотре (`reviewing`).
    private(set) var voiceReview: VoiceReview?

    /// Готовая запись для отправки.
    @ObservationIgnored var onRecorded: ((AttachmentDraft) -> Void)?
    /// Запись началась: остановить воспроизведение голосовых.
    @ObservationIgnored var onStart: (() -> Void)?
    /// Полоса записи появилась (режим) или запись кончилась (`nil`): собеседник видит
    /// «записывает аудио» или «записывает видеосообщение».
    @ObservationIgnored var onRecordingChange: ((Mode?) -> Void)?
    /// Короткое нажатие камеры: снимок.
    @ObservationIgnored var onCameraTap: (() -> Void)?

    static let cancelDistance: CGFloat = 120
    static let lockDistance: CGFloat = 90

    @ObservationIgnored private var pressTask: Task<Void, Never>?
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    /// Микрофон или камера включены под пальцем, полосы записи ещё нет.
    @ObservationIgnored private var warming = false
    /// Идёт системный запрос доступа: отпущенный палец режим не меняет.
    @ObservationIgnored private var requestingAccess = false
    /// Номер нажатия: поздний ответ рекордера прежнего нажатия экран не трогает.
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var recorderQueue: Task<Void, Never>?
    /// Запись закреплена этим же нажатием: его отпускание не отправляет её.
    @ObservationIgnored private var lockedInPress = false
    @ObservationIgnored private var holdTriggered = false

    init() {
        voice.onLimit = { [weak self] in self?.send() }
        video.onLimit = { [weak self] in self?.send() }
    }

    /// Идёт запись (или её остановка): вместо поля ввода — полоса записи.
    var isActive: Bool {
        phase == .recording || phase == .locked || phase == .finishing || phase == .reviewing
    }

    var isVideo: Bool { recordingMode == .video && isActive }

    var elapsed: TimeInterval {
        if let review { return review.selectedSeconds }
        if let voiceReview { return voiceReview.selectedSeconds }
        return recordingMode == .voice ? voice.elapsed : video.elapsed
    }

    var level: Double { recordingMode == .voice ? voice.level : 0 }

    // MARK: Жест кнопки

    /// Голосовое: нажатие короче этого — подсказка, дольше — запись. Микрофон включается
    /// сразу под пальцем, так что к этому моменту запись уже идёт.
    static let holdDelay: Duration = .milliseconds(150)
    /// Камера: короче — снимок, дольше — кружок. Камера для кружка включается только после
    /// этого, чтобы касание ради снимка её не занимало.
    static let videoHoldDelay: Duration = .milliseconds(280)

    func pressBegan(mode: Mode) {
        guard phase == .idle, !requestingAccess else { return }
        press(mode)
    }

    func pressChanged(_ translation: CGSize, mode: Mode) {
        switch phase {
        case .pressing, .recording:
            guard mode == recordingMode else { return }
            dragX = min(0, translation.width)
            dragY = min(0, translation.height)
            if dragX < -Self.cancelDistance {
                cancel()
            } else if phase == .recording, dragY < -Self.lockDistance {
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

    func pressEnded(mode: Mode) {
        guard phase == .idle || mode == recordingMode else { return }
        switch phase {
        case .pressing:
            pressTask?.cancel()
            pressTask = nil
            phase = .idle
            if warming {
                // Короткое касание: включённый под пальцем микрофон не нужен.
                warming = false
                discard(recordingMode)
            }
            if !requestingAccess, !holdTriggered { tapped(mode) }
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
        case .reviewing:
            send()
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

    /// Палец лёг на кнопку. Микрофон включается сразу, полоса записи — через `holdDelay`;
    /// камера для кружка — только через `videoHoldDelay`, раньше отпущенный палец — снимок.
    private func press(_ current: Mode) {
        attempt &+= 1
        lockedInPress = false
        holdTriggered = false
        hint = nil
        recordingMode = current
        phase = .pressing
        if current == .video {
            pressTask = Task { [weak self] in
                try? await Task.sleep(for: Self.videoHoldDelay)
                guard let self, !Task.isCancelled, self.phase == .pressing else { return }
                self.holdTriggered = true
                self.beginHold(current)
            }
            return
        }
        beginHold(current)
    }

    /// Удержание дошло до записи: доступ, включение рекордера и полоса записи.
    private func beginHold(_ current: Mode) {
        switch access(current) {
        case .granted:
            warming = true
            onStart?()
            let attempt = attempt
            enqueue { [weak self] in
                guard let self else { return }
                await self.startRecorder(current, attempt: attempt)
            }
            // Полоса появляется после порога удержания и готовности рекордера.
            let delay: Duration = current == .video ? .zero : Self.holdDelay
            let startup = recorderQueue
            pressTask = Task { [weak self] in
                if delay > .zero { try? await Task.sleep(for: delay) }
                await startup?.value
                guard let self, !Task.isCancelled, attempt == self.attempt, self.phase == .pressing, self.warming else { return }
                self.warming = false
                self.holdTriggered = true
                if self.dragY < -Self.lockDistance {
                    self.phase = .locked
                    self.lockedInPress = true
                    self.dragX = 0
                    self.dragY = 0
                } else {
                    self.phase = .recording
                }
                self.onRecordingChange?(current)
                Self.haptic(.light)
            }
        case .undetermined:
            // Первое касание спрашивает систему; запись не начинается, палец уходит к окну запроса.
            requestingAccess = true
            holdTriggered = true
            Task { [weak self] in
                if current == .voice {
                    _ = await VoiceRecorder.requestPermission()
                } else {
                    _ = await VideoNoteRecorder.requestPermissions()
                }
                self?.requestingAccess = false
            }
        case .denied:
            phase = .idle
            show(current == .voice
                 ? "Нет доступа к микрофону. Разрешите его в Настройках"
                 : "Нет доступа к камере или микрофону. Разрешите их в Настройках")
        }
    }

    /// Короткое касание: у микрофона — подсказка, у камеры — снимок.
    private func tapped(_ mode: Mode) {
        switch mode {
        case .voice:
            Self.haptic(.soft)
            show("Удерживайте, чтобы записать голосовое")
        case .video:
            onCameraTap?()
        }
    }

    // MARK: Запись

    /// Включение микрофона или камеры. Не вышло — полоса записи уходит, если это нажатие ещё идёт.
    private func startRecorder(_ current: Mode, attempt: Int) async {
        guard attempt == self.attempt, phase == .pressing, warming else { return }
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
            onRecordingChange?(nil)
            show(current == .voice ? "Не удалось включить микрофон" : "Не удалось включить камеру")
        }
    }

    /// Закреплённый кружок — на просмотр: запись останавливается, ролик играет по кругу, его
    /// можно обрезать, отправить или выбросить.
    /// Закреплённая запись на паузе.
    var isPaused: Bool { recordingMode == .voice ? voice.isPaused : video.isPaused }

    /// Пауза и продолжение закреплённой записи.
    func togglePause() {
        guard phase == .locked else { return }
        if recordingMode == .voice {
            voice.setPaused(!voice.isPaused)
        } else {
            video.setPaused(!video.isPaused)
        }
        Self.haptic(.light)
    }

    /// Закреплённое голосовое — на просмотр: прослушать, обрезать, отправить или выбросить.
    private func stopVoiceForReview() {
        phase = .finishing
        onRecordingChange?(nil)
        let attempt = attempt
        enqueue { [weak self] in
            guard let self else { return }
            let recording = await self.voice.stop()
            guard attempt == self.attempt, self.phase == .finishing else {
                if let recording { try? FileManager.default.removeItem(at: recording.url.deletingLastPathComponent()) }
                return
            }
            guard let recording else {
                self.phase = .idle
                self.show("Запись слишком короткая или не сохранилась. Попробуйте ещё раз")
                return
            }
            self.voiceReview = VoiceReview(recording: recording)
            self.phase = .reviewing
            Self.haptic(.light)
        }
    }

    /// Отправить голосовое с просмотра: выбранный кусок.
    private func sendVoiceReview() {
        guard phase == .reviewing, let voiceReview else { return }
        phase = .finishing
        let attempt = attempt
        enqueue { [weak self] in
            guard let self else { return }
            let recording = voiceReview.result()
            self.voiceReview = nil
            if attempt == self.attempt, self.phase == .finishing { self.phase = .idle }
            if let recording {
                Self.haptic(.light)
                self.onRecorded?(.voice(path: recording.url.path, durationMs: recording.durationMs, waveform: recording.waveform))
            } else {
                self.show("Голосовое не обрезалось. Попробуйте ещё раз")
            }
        }
    }

    func stopForReview() {
        guard phase == .locked else { return }
        if recordingMode == .voice {
            stopVoiceForReview()
            return
        }
        phase = .finishing
        onRecordingChange?(nil)
        let attempt = attempt
        enqueue { [weak self] in
            guard let self else { return }
            let note = await self.video.stop()
            guard attempt == self.attempt, self.phase == .finishing else {
                if let note { try? FileManager.default.removeItem(at: note.url.deletingLastPathComponent()) }
                return
            }
            guard let note else {
                self.phase = .idle
                self.show("Запись слишком короткая или не сохранилась. Попробуйте ещё раз")
                return
            }
            let review = VideoNoteReview(note: note)
            self.review = review
            self.phase = .reviewing
            Self.haptic(.light)
            await review.loadThumbnails()
        }
    }

    /// Отправить кружок с просмотра: выбранный кусок.
    private func sendReview() {
        guard phase == .reviewing, let review else { return }
        phase = .finishing
        let attempt = attempt
        enqueue { [weak self] in
            guard let self else { return }
            let note = await review.result()
            self.review = nil
            if attempt == self.attempt, self.phase == .finishing { self.phase = .idle }
            if let note {
                Self.haptic(.light)
                self.onRecorded?(.videoNote(path: note.url.path, durationMs: note.durationMs, side: note.side))
            } else {
                self.show("Кружок не обрезался. Попробуйте ещё раз")
            }
        }
    }

    /// Остановить и отправить.
    func send() {
        if phase == .reviewing {
            if voiceReview != nil { sendVoiceReview() } else { sendReview() }
            return
        }
        guard phase == .recording || phase == .locked else { return }
        phase = .finishing
        onRecordingChange?(nil)
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
            } else if attempt == self.attempt {
                self.show("Запись слишком короткая или не сохранилась. Попробуйте ещё раз")
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
            onRecordingChange?(nil)
            Self.haptic(.rigid)
        case .reviewing:
            review?.discard()
            review = nil
            voiceReview?.discard()
            voiceReview = nil
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
