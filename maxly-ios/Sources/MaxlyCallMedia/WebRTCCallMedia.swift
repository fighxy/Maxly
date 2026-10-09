import AVFoundation
import Foundation
@preconcurrency import WebRTC
import MaxlyData
import MaxlyDomain
#if os(iOS)
import ReplayKit
import UIKit
#endif

/// Фабрика WebRTC одна на приложение: кодеки по умолчанию (H.264 аппаратный, VP8, VP9).
@MainActor
enum WebRTCFactory {
    static let shared: RTCPeerConnectionFactory = {
        _ = RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()
}

/// Свои микрофон, камера и экран для одного звонка.
@MainActor
public final class WebRTCCallMedia: CallMedia {
    static let streamId = "orbitle"

    let audioTrack: RTCAudioTrack
    private let factory: RTCPeerConnectionFactory
    private var cameraCapturer: RTCCameraVideoCapturer?
    private var cameraTrack: RTCVideoTrack?
    private var screenTrack: RTCVideoTrack?
    private var screenSource: RTCVideoSource?
    #if os(iOS)
    private var screenCapture: ScreenCapture?
    #endif

    public init() {
        let factory = WebRTCFactory.shared
        self.factory = factory
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "googEchoCancellation": kRTCMediaConstraintsValueTrue,
                "googNoiseSuppression": kRTCMediaConstraintsValueTrue,
                "googAutoGainControl": kRTCMediaConstraintsValueTrue,
                "googHighpassFilter": kRTCMediaConstraintsValueTrue,
            ]
        )
        let source = factory.audioSource(with: constraints)
        audioTrack = factory.audioTrack(with: source, trackId: "audio-\(Self.shortId())")
    }

    public func makePeer(iceServers: [CallIceServer]) -> (any CallPeer)? {
        WebRTCPeer(factory: factory, iceServers: iceServers, media: self)
    }

    public func trackId(of video: LocalVideo) -> String? {
        videoTrack(video)?.trackId
    }

    func videoTrack(_ video: LocalVideo) -> RTCVideoTrack? {
        switch video {
        case .camera: cameraTrack
        case .screen: screenTrack
        }
    }

    public func startCamera(_ position: CallCameraPosition) async throws(CallMediaError) {
        guard await Self.cameraAllowed() else { throw .denied }
        let devices = RTCCameraVideoCapturer.captureDevices()
        let wanted: AVCaptureDevice.Position = position == .front ? .front : .back
        guard let device = devices.first(where: { $0.position == wanted }) ?? devices.first,
              let format = Self.format(for: device)
        else { throw .unavailable }
        if cameraTrack == nil {
            let source = factory.videoSource()
            cameraCapturer = RTCCameraVideoCapturer(delegate: source)
            let track = factory.videoTrack(with: source, trackId: "camera-\(Self.shortId())")
            cameraTrack = track
            CallVideoRegistry.shared.register(track)
        }
        guard let capturer = cameraCapturer, let track = cameraTrack else { throw .unavailable }
        let fps = Self.frameRate(of: format)
        let started: Bool = await withCheckedContinuation { continuation in
            capturer.startCapture(with: device, format: format, fps: fps) { @Sendable error in
                continuation.resume(returning: error == nil)
            }
        }
        guard started else { throw .unavailable }
        track.isEnabled = true
        CallVideoRegistry.shared.setMirrored(track.trackId, device.position == .front)
    }

    public func stopCamera() {
        cameraCapturer?.stopCapture()
        cameraTrack?.isEnabled = false
    }

    public func startScreen() async throws(CallMediaError) {
        #if os(iOS)
        if screenTrack == nil {
            let source = factory.videoSource(forScreenCast: true)
            source.adaptOutputFormat(toWidth: 1280, height: 720, fps: 15)
            screenSource = source
            let track = factory.videoTrack(with: source, trackId: "screen-\(Self.shortId())")
            screenTrack = track
            CallVideoRegistry.shared.register(track)
        }
        guard let source = screenSource else { throw .unavailable }
        let capture = ScreenCapture(source: source)
        try await capture.start()
        screenCapture = capture
        screenTrack?.isEnabled = true
        #else
        throw .unavailable
        #endif
    }

    public func stopScreen() {
        #if os(iOS)
        screenCapture?.stop()
        screenCapture = nil
        #endif
        screenTrack?.isEnabled = false
    }

    public func setMicrophone(enabled: Bool) {
        audioTrack.isEnabled = enabled
    }

    public func setSpeaker(_ on: Bool) {
        #if os(iOS)
        CallAudio.setSpeaker(on)
        #endif
    }

    public func shutdown() {
        cameraCapturer?.stopCapture()
        cameraCapturer = nil
        stopScreen()
        audioTrack.isEnabled = false
        cameraTrack = nil
        screenTrack = nil
        screenSource = nil
        CallVideoRegistry.shared.removeAll()
        #if os(iOS)
        CallAudio.setSpeaker(false)
        #endif
    }

    // MARK: Камера

    private static func cameraAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// Формат ближе всего к 1280×720: этого хватает для звонка, сеть WebRTC подстроит сама.
    private static func format(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let target = 1280 * 720
        return RTCCameraVideoCapturer.supportedFormats(for: device).min { left, right in
            let a = abs(pixels(left) - target)
            let b = abs(pixels(right) - target)
            return a != b ? a < b : frameRate(of: left) > frameRate(of: right)
        }
    }

    private static func pixels(_ format: AVCaptureDevice.Format) -> Int {
        let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(size.width) * Int(size.height)
    }

    private static func frameRate(of format: AVCaptureDevice.Format) -> Int {
        let best = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        return Int(min(30, best))
    }

    private static func shortId() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }
}

/// Видеодорожки идущего звонка по id: экран звонка рисует их по id из `CallState`.
@MainActor
public final class CallVideoRegistry {
    public static let shared = CallVideoRegistry()

    private var tracks: [String: RTCVideoTrack] = [:]
    private var mirrored: Set<String> = []

    func register(_ track: RTCVideoTrack) {
        tracks[track.trackId] = track
    }

    func track(_ id: String) -> RTCVideoTrack? {
        tracks[id]
    }

    func setMirrored(_ id: String, _ on: Bool) {
        if on { mirrored.insert(id) } else { mirrored.remove(id) }
    }

    /// Своё видео с фронтальной камеры показывается зеркально, как в зеркале.
    public func isMirrored(_ id: String) -> Bool {
        mirrored.contains(id)
    }

    func removeAll() {
        tracks = [:]
        mirrored = []
    }
}

#if os(iOS)
/// Звук звонка. С CallKit звук включает система (`activated`), WebRTC ждёт её.
@MainActor
public enum CallAudio {
    /// Звук ведёт CallKit: WebRTC не трогает аудиосессию сам.
    public static func useCallKit() {
        let session = RTCAudioSession.sharedInstance()
        session.useManualAudio = true
        session.isAudioEnabled = false
    }

    /// Категория для разговора: громкость звонка, гарнитура Bluetooth.
    public static func configure(video: Bool) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        do {
            try session.setCategory(.playAndRecord, mode: video ? .videoChat : .voiceChat, options: [.allowBluetooth])
        } catch {
            Log.warning(.calls, "Аудиосессия: \(error)")
        }
    }

    /// CallKit включил звук.
    public static func activated(_ audioSession: AVAudioSession) {
        let session = RTCAudioSession.sharedInstance()
        session.audioSessionDidActivate(audioSession)
        session.isAudioEnabled = true
    }

    /// CallKit выключил звук.
    public static func deactivated(_ audioSession: AVAudioSession) {
        let session = RTCAudioSession.sharedInstance()
        session.audioSessionDidDeactivate(audioSession)
        session.isAudioEnabled = false
    }

    /// Без CallKit звук включается сам.
    public static func activateDirectly() {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        do {
            try session.setActive(true)
        } catch {
            Log.warning(.calls, "Аудиосессия не включилась: \(error)")
        }
        session.unlockForConfiguration()
        session.isAudioEnabled = true
    }

    static func setSpeaker(_ on: Bool) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        do {
            try session.overrideOutputAudioPort(on ? .speaker : .none)
        } catch {
            Log.warning(.calls, "Громкая связь: \(error)")
        }
    }
}

/// Показ экрана: кадры приложения через ReplayKit (`startCapture`) уходят в видеоисточник
/// WebRTC. Показывается само приложение, не весь телефон.
@MainActor
final class ScreenCapture {
    private let target: Unchecked<(source: RTCVideoSource, capturer: RTCVideoCapturer)>

    init(source: RTCVideoSource) {
        target = Unchecked(value: (source, RTCVideoCapturer(delegate: source)))
    }

    func start() async throws(CallMediaError) {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else { throw .unavailable }
        recorder.isMicrophoneEnabled = false
        let target = self.target
        let throttle = FrameThrottle(interval: 1.0 / 15)
        let failure: (any Error)? = await withCheckedContinuation { continuation in
            recorder.startCapture(handler: { @Sendable buffer, type, error in
                guard type == .video, error == nil, CMSampleBufferIsValid(buffer),
                      let pixels = CMSampleBufferGetImageBuffer(buffer)
                else { return }
                let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
                guard throttle.allows(seconds) else { return }
                let frame = RTCVideoFrame(
                    buffer: RTCCVPixelBuffer(pixelBuffer: pixels),
                    rotation: ._0,
                    timeStampNs: Int64(seconds * 1_000_000_000)
                )
                target.value.source.capturer(target.value.capturer, didCapture: frame)
            }, completionHandler: { @Sendable error in
                continuation.resume(returning: error)
            })
        }
        if let failure {
            Log.warning(.calls, "Показ экрана не начался: \(failure)")
            throw (failure as NSError).code == RPRecordingErrorCode.userDeclined.rawValue ? .denied : .unavailable
        }
    }

    func stop() {
        // ReplayKit зовёт обработчик на своей очереди: замыкание не должно наследовать главный актор.
        RPScreenRecorder.shared().stopCapture { @Sendable _ in }
    }
}

/// Не чаще одного кадра за `interval` секунд.
final class FrameThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: Double
    private var last = -Double.infinity

    init(interval: Double) {
        self.interval = interval
    }

    func allows(_ time: Double) -> Bool {
        lock.withLock {
            guard time - last >= interval else { return false }
            last = time
            return true
        }
    }
}

/// Видео звонка по id дорожки из `CallState`.
public final class CallVideoUIView: UIView {
    private let renderer = RTCMTLVideoView(frame: .zero)
    private var attached: RTCVideoTrack?

    public var trackId: String? {
        didSet { if trackId != oldValue { attach() } }
    }

    /// Заполнять кадр (обрезая края) или вписывать целиком.
    public var fills = true {
        didSet { renderer.videoContentMode = fills ? .scaleAspectFill : .scaleAspectFit }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .black
        renderer.videoContentMode = .scaleAspectFill
        renderer.frame = bounds
        renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(renderer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    /// Снова найти дорожку: она могла появиться после того, как вид создан.
    public func refresh() {
        attach()
    }

    /// Отцепить видео, когда вид убирают с экрана.
    public func detach() {
        attached?.remove(renderer)
        attached = nil
    }

    private func attach() {
        let next = trackId.flatMap { CallVideoRegistry.shared.track($0) }
        if next !== attached {
            attached?.remove(renderer)
            next?.add(renderer)
            attached = next
        }
        let mirrored = trackId.map { CallVideoRegistry.shared.isMirrored($0) } ?? false
        renderer.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }
}
#endif
