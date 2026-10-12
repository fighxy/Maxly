import AVFoundation
import Foundation
import MaxlyDomain

/// Держит приложение живым в фоне, чтобы входящий звонок и новые сообщения доходили и в
/// свёрнутом приложении (`docs/background.md`).
///
/// Сервер Max шлёт пуши только своему приложению, поэтому звонок приходит лишь по
/// соединению ядра. В фоне iOS через 5–20 с приостанавливает приложение, и соединение рвётся.
/// Пока приложение свёрнуто, оно проигрывает тишину в режиме фонового звука (`audio` в
/// `UIBackgroundModes`): iOS его не приостанавливает, соединение живёт, входящий звонок
/// показывается через CallKit, о сообщениях приходят уведомления. Звук смешивается с чужим
/// (`mixWithOthers`): музыку и подкасты не прерывает.
///
/// Не работает, если приложение смахнули из переключателя или телефон перезагрузили.
/// Во время звонка тишина выключена: звуком владеет CallKit.
@MainActor
final class BackgroundKeepAlive {
    static let settingKey = "backgroundKeepAlive"

    /// Включено в настройках. По умолчанию — да: без этого в свёрнутом приложении не звонят.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.settingKey)
            refresh()
        }
    }

    private var inBackground = false
    private var inCall = false
    private var signedIn = false
    private var player: AVAudioPlayer?
    /// Сессию звука включили мы: выключаем её только тогда.
    private var ownsSession = false
    private var observers: [NSObjectProtocol] = []

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.settingKey) as? Bool ?? true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            Task { @MainActor in self?.interrupted(began: began) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.servicesReset() }
        })
    }

    /// Приложение ушло в фон (`true`) или вернулось на экран.
    func setBackground(_ background: Bool) {
        inBackground = background
        refresh()
    }

    /// Идёт звонок: звуком владеет CallKit, тишина выключается и возвращается после звонка.
    func setInCall(_ busy: Bool) {
        inCall = busy
        refresh()
    }

    /// Без входа соединения нет — и держать нечего.
    func setSignedIn(_ value: Bool) {
        signedIn = value
        refresh()
    }

    private var shouldRun: Bool { isEnabled && inBackground && signedIn && !inCall }

    private func refresh() {
        if shouldRun { start() } else { stop() }
    }

    private func start() {
        if player?.isPlaying == true { return }
        let session = AVAudioSession.sharedInstance()
        // Запись голосового или кружка в фоне держит приложение сама: её сессию не трогаем.
        // После звонка категория тоже остаётся `.playAndRecord`, но с режимом звонка
        // (`.voiceChat`, `.videoChat`): тогда тишину включаем.
        if Self.isRecording(session) {
            Log.info(.app, "Фон: идёт запись, тишина не нужна")
            return
        }
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            ownsSession = true
            let player = try self.player ?? AVAudioPlayer(data: Self.silence)
            player.numberOfLoops = -1
            player.prepareToPlay()
            guard player.play() else {
                Log.warning(.app, "Фон: тишина не заиграла")
                DiagnosticEvent.event("background.keepalive", ["state": "failed"], snapshot: true)
                return
            }
            self.player = player
            Log.info(.app, "Фон: приложение держится живым")
            DiagnosticEvent.event("background.keepalive", ["state": "started"], snapshot: true)
        } catch {
            Log.warning(.app, "Фон: звук не включился: \(error)")
            DiagnosticEvent.event("background.keepalive", ["state": "failed"], snapshot: true)
        }
    }

    private func stop() {
        guard player?.isPlaying == true || ownsSession else { return }
        player?.stop()
        // Звонку сессию не выключаем: её сейчас настраивает CallKit.
        if ownsSession, !inCall {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        ownsSession = false
        DiagnosticEvent.event("background.keepalive", ["state": inCall ? "paused-call" : "stopped"], snapshot: true)
    }

    /// Звонок по сотовой, Siri или другое приложение забрали звук. После них тишина
    /// включается снова, если приложение всё ещё в фоне.
    private func interrupted(began: Bool) {
        guard ownsSession || shouldRun else { return }
        DiagnosticEvent.event("background.keepalive", ["state": began ? "interrupted" : "resumed"], snapshot: true)
        guard !began, shouldRun else { return }
        player?.stop()
        start()
    }

    /// Звуковая служба iOS перезапустилась: прежний плеер и сессия недействительны.
    private func servicesReset() {
        player = nil
        ownsSession = false
        refresh()
    }

    /// Сессию держит запись голосового или кружка, а не оставшийся после звонка WebRTC.
    private static func isRecording(_ session: AVAudioSession) -> Bool {
        session.category == .playAndRecord && session.mode != .voiceChat && session.mode != .videoChat
    }

    /// Секунда тишины в WAV: 8 кГц, моно, 16 бит. Играет по кругу.
    nonisolated static let silence: Data = {
        let rate: UInt32 = 8_000
        let samples = rate
        let dataSize = samples * 2
        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1)
        append16(1)
        append32(rate)
        append32(rate * 2)
        append16(2)
        append16(16)
        data.append(contentsOf: Array("data".utf8))
        append32(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }()
}
