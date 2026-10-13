import AVFoundation
import Foundation
import Observation
import MaxlyDomain
import SwiftUI
import UIKit

/// Записанный кружок: квадратный MP4, длительность и сторона кадра.
struct VideoNoteRecording: Sendable {
    let url: URL
    let durationMs: Int64
    let side: Int
}

/// Запись круглого видеосообщения: фронтальная камера, до минуты.
///
/// Камера пишет обычный ролик, после остановки он обрезается по центру в квадрат
/// 480×480 и перекодируется в MP4 как у Komet (`VideoNoteExporter`): круг рисует уже пузырь.
@MainActor
@Observable
final class VideoNoteRecorder {
    private(set) var isRecording = false
    /// Запись на паузе: камера и превью идут, в файл ничего не пишется.
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    @ObservationIgnored private var accumulated: TimeInterval = 0

    nonisolated static let maximumDuration: TimeInterval = 60
    static let minimumDuration: TimeInterval = 1

    @ObservationIgnored let capture = CaptureController()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date()
    /// Вызывается, когда запись упёрлась в минуту.
    @ObservationIgnored var onLimit: (() -> Void)?

    var session: AVCaptureSession { capture.session }

    /// Камера и микрофон: спрашиваются при первой записи.
    static func requestPermissions() async -> Bool {
        let camera = await AVCaptureDevice.requestAccess(for: .video)
        let microphone = await AVAudioApplication.requestRecordPermission()
        return camera && microphone
    }

    func start() async throws {
        guard !isRecording else { return }
        isRecording = true
        elapsed = 0
        do {
            try await capture.start()
        } catch {
            isRecording = false
            throw error
        }
        startedAt = .now
        accumulated = 0
        isPaused = false
        Log.info(.media, "Запись кружка началась")
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isRecording else { return }
                guard !self.isPaused else { continue }
                self.elapsed = self.accumulated + Date.now.timeIntervalSince(self.startedAt)
                if self.elapsed >= Self.maximumDuration { self.onLimit?() }
            }
        }
    }

    /// Пауза и продолжение записи кружка.
    func setPaused(_ value: Bool) {
        guard isRecording, isPaused != value else { return }
        if value {
            accumulated += Date.now.timeIntervalSince(startedAt)
            elapsed = accumulated
        } else {
            startedAt = .now
        }
        isPaused = value
        capture.setPaused(value)
        Log.info(.media, "Кружок: \(value ? "пауза" : "продолжение")")
    }

    /// Остановить и получить квадратный ролик. `nil` — слишком коротко или не вышло.
    func stop() async -> VideoNoteRecording? {
        guard isRecording else { return nil }
        ticker?.cancel()
        ticker = nil
        isRecording = false
        isPaused = false
        flashOn = false
        capture.setTorch(false)
        let raw = await capture.stopRecording()
        capture.stopSession()
        guard let raw else {
            Log.warning(.media, "Кружок не записался")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: raw) }
        do {
            let note = try await VideoNoteExporter.square(raw)
            guard Double(note.durationMs) / 1000 >= Self.minimumDuration else {
                try? FileManager.default.removeItem(at: note.url)
                return nil
            }
            Log.info(.media, "Кружок записан: \(note.durationMs) мс, \(note.side)×\(note.side)")
            return note
        } catch {
            Log.warning(.media, "Кружок не подготовлен: \(error)")
            return nil
        }
    }

    func cancel() {
        ticker?.cancel()
        ticker = nil
        isRecording = false
        isPaused = false
        capture.cancel()
        usesFrontCamera = true
        flashOn = false
    }

    /// Вспышка: у основной камеры — фонарик, у фронтальной экран светит белым (`VideoNoteOverlay`).
    private(set) var flashOn = false

    /// Экран светит вместо вспышки: вспышка включена, а пишет фронтальная камера.
    var screenFlash: Bool { isRecording && flashOn && usesFrontCamera }

    func toggleFlash() {
        guard isRecording else { return }
        flashOn.toggle()
        capture.setTorch(flashOn && !usesFrontCamera)
        Log.info(.media, "Кружок: вспышка \(flashOn ? "включена" : "выключена")")
    }

    /// Пишет фронтальная камера (по умолчанию) или основная.
    private(set) var usesFrontCamera = true
    @ObservationIgnored private var switching = false

    /// Сменить камеру, не прерывая запись: ролик идёт дальше с другой камеры.
    func switchCamera() async {
        guard isRecording, !switching else { return }
        switching = true
        defer { switching = false }
        let front = await capture.switchCamera()
        usesFrontCamera = front
        // Фонарик есть только у основной: у фронтальной светит экран.
        capture.setTorch(flashOn && !front)
        Log.info(.media, "Кружок: камера \(front ? "фронтальная" : "основная")")
    }
}

/// Сессия камеры на своей очереди: `startRunning` блокирует поток, кадры и звук приходят
/// не на главном.
///
/// Ролик пишет `AVAssetWriter` из кадров и звука самой сессии, а не `AVCaptureMovieFileOutput`:
/// тот обрывает запись при смене входа, и после смены камеры кружок не сохранялся (журнал
/// 13.10: «Кружок не записался»). Так же делается пауза: пока она идёт, отсчёты не пишутся,
/// а после неё время сдвигается на длину паузы.
final class CaptureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Failure: Error {
        case noCamera
        case noWriter
    }

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "maxly.note.capture")
    // Всё ниже меняется только на `queue`.
    private var configured = false
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var target: URL?
    private var sessionStarted = false
    private var recording = false
    private var paused = false
    /// Время первого отсчёта, пропущенного паузой, и общий сдвиг времени после пауз.
    private var pausedAt: CMTime?
    private var offset = CMTime.zero
    private var resumeNeedsOffset = false

    /// Сторона кадра ролика до обрезки в квадрат: портрет 480×640.
    private static let width = 480
    private static let height = 640

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try configure()
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("note-\(UUID().uuidString).mp4")
                    try makeWriter(url)
                    if !session.isRunning { session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func makeWriter(_ url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Self.width,
            AVVideoHeightKey: Self.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_600_000],
        ])
        video.expectsMediaDataInRealTime = true
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 64_000,
        ])
        audio.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw Failure.noWriter }
        writer.add(video)
        if writer.canAdd(audio) { writer.add(audio) }
        guard writer.startWriting() else { throw writer.error ?? Failure.noWriter }
        self.writer = writer
        videoInput = video
        audioInput = writer.inputs.contains(audio) ? audio : nil
        target = url
        sessionStarted = false
        paused = false
        pausedAt = nil
        offset = .zero
        resumeNeedsOffset = false
        recording = true
    }

    /// Пауза записи: камера и превью идут, в файл ничего не пишется.
    func setPaused(_ value: Bool) {
        queue.async { [self] in
            guard recording, paused != value else { return }
            paused = value
            if !value { resumeNeedsOffset = pausedAt != nil }
        }
    }

    /// Дописать файл и отдать его. `nil` — ни одного кадра или запись не вышла.
    func stopRecording() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard recording, let writer else {
                    continuation.resume(returning: nil)
                    return
                }
                recording = false
                let url = target
                guard sessionStarted, writer.status == .writing else {
                    writer.cancelWriting()
                    reset()
                    if let url { try? FileManager.default.removeItem(at: url) }
                    continuation.resume(returning: nil)
                    return
                }
                videoInput?.markAsFinished()
                audioInput?.markAsFinished()
                nonisolated(unsafe) let finishing = writer
                writer.finishWriting { [self] in
                    let ok = finishing.status == .completed
                    queue.async { [self] in
                        reset()
                        if !ok, let url { try? FileManager.default.removeItem(at: url) }
                        continuation.resume(returning: ok ? url : nil)
                    }
                }
            }
        }
    }

    func stopSession() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func cancel() {
        queue.async { [self] in
            if recording {
                recording = false
                writer?.cancelWriting()
                if let target { try? FileManager.default.removeItem(at: target) }
            }
            reset()
            if session.isRunning { session.stopRunning() }
        }
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        target = nil
        sessionStarted = false
        paused = false
        pausedAt = nil
        offset = .zero
        resumeNeedsOffset = false
    }

    // MARK: Отсчёты

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard recording, let writer, writer.status == .writing else { return }
        let video = output === videoOutput
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if paused {
            if pausedAt == nil { pausedAt = time }
            return
        }
        if resumeNeedsOffset, let pausedAt {
            offset = CMTimeAdd(offset, CMTimeSubtract(time, pausedAt))
            self.pausedAt = nil
            resumeNeedsOffset = false
        }
        if !sessionStarted {
            // Файл начинается с кадра: звук до первого кадра не пишется.
            guard video else { return }
            writer.startSession(atSourceTime: time)
            sessionStarted = true
        }
        let buffer = offset == .zero ? sampleBuffer : Self.shifted(sampleBuffer, by: offset) ?? sampleBuffer
        if video {
            if let videoInput, videoInput.isReadyForMoreMediaData { videoInput.append(buffer) }
        } else if let audioInput, audioInput.isReadyForMoreMediaData {
            audioInput.append(buffer)
        }
    }

    /// Копия отсчёта со временем раньше на [offset] — длину пауз.
    private static func shifted(_ buffer: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for index in timing.indices {
            timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, offset)
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, offset)
            }
        }
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: buffer, sampleTimingEntryCount: count, sampleTimingArray: &timing, sampleBufferOut: &copy)
        return copy
    }

    // MARK: Камера

    /// Сменить камеру на другую сторону посреди записи: кадры идут дальше в тот же файл.
    /// Возвращает, фронтальная ли камера стала. Не вышло — прежняя.
    func switchCamera() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let current = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device.hasMediaType(.video) }
                let wasFront = current?.device.position != .back
                let target: AVCaptureDevice.Position = wasFront ? .back : .front
                guard let current,
                      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: target),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: wasFront)
                    return
                }
                session.beginConfiguration()
                session.removeInput(current)
                let front: Bool
                if session.canAddInput(input) {
                    session.addInput(input)
                    front = target == .front
                } else {
                    session.addInput(current)
                    front = wasFront
                }
                orient(mirrored: front)
                session.commitConfiguration()
                continuation.resume(returning: front)
            }
        }
    }

    /// Фонарик основной камеры. У фронтальной его нет — вызов ничего не делает.
    func setTorch(_ on: Bool) {
        queue.async { [self] in
            guard let device = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) })?.device,
                  device.hasTorch, device.isTorchModeSupported(on ? .on : .off) else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {
                // Фонарик занят или перегрет: запись идёт без него.
            }
        }
    }

    /// Поворот кадра и зеркало: фронтальная камера — как в зеркале, основная — как есть.
    private func orient(mirrored: Bool) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    private func configure() throws {
        guard !configured else {
            // Прошлый кружок мог закончиться на основной камере: новый снова с фронтальной.
            resetToFront()
            return
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else {
            session.sessionPreset = .medium
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video) else { throw Failure.noCamera }
        let video = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(video) else { throw Failure.noCamera }
        session.addInput(video)
        if let microphone = AVCaptureDevice.default(for: .audio),
           let audio = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(audio) {
            session.addInput(audio)
        }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else { throw Failure.noCamera }
        session.addOutput(videoOutput)
        audioOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        // Как в зеркале: так видит себя пишущий и так кружок привычно выглядит в мессенджерах.
        orient(mirrored: true)
        configured = true
    }

    private func resetToFront() {
        let current = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device.hasMediaType(.video) }
        guard let current, current.device.position == .back,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.removeInput(current)
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            session.addInput(current)
        }
        orient(mirrored: true)
        session.commitConfiguration()
    }
}

/// Обрезка ролика по центру в квадрат для кружка.
enum VideoNoteExporter {
    enum Failure: Error {
        case noVideo
        case exportFailed(String?)
    }

    static let side = 480

    static func square(_ source: URL) async throws -> VideoNoteRecording {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.noVideo }
        let duration = try await asset.load(.duration)
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frameRate = (try? await track.load(.nominalFrameRate)) ?? 30
        let box = CGRect(origin: .zero, size: natural).applying(transform)
        let width = abs(box.width)
        let height = abs(box.height)
        let crop = min(width, height)
        guard crop > 0 else { throw Failure.noVideo }
        let out = CGFloat(min(side, Int(crop)) / 2 * 2)
        let scale = out / crop
        let placed = transform
            .concatenating(CGAffineTransform(translationX: -box.minX, y: -box.minY))
            .concatenating(CGAffineTransform(translationX: -(width - crop) / 2, y: -(height - crop) / 2))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(placed, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: out, height: out)
        // Частота ролика с камеры (60, если она её дала), не больше 60.
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(min(60, max(24, frameRate.rounded()))))
        composition.instructions = [instruction]

        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = caches.appendingPathComponent("Outgoing", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("note.mp4")
        let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
        try await transcode(asset: asset, video: track, audio: audioTrack, composition: composition, side: Int(out), to: target)
        await writePoster(of: target, to: folder.appendingPathComponent("poster.jpg"))
        let seconds = CMTimeGetSeconds(duration)
        let durationMs = seconds.isFinite ? Int64((seconds * 1000).rounded()) : 0
        return VideoNoteRecording(url: target, durationMs: durationMs, side: Int(out))
    }
}

extension VideoNoteExporter {
    /// Перекодирование в MP4 с параметрами Komet: сервер Max проверяет кружок
    /// (`VIDEO_VALIDATION_FAILED` на ролик из `AVAssetExportSession`). Видео H.264 High,
    /// квадрат, около 1 Мбит/с; звук AAC моно 44,1 кГц, 64 кбит/с.
    static func transcode(
        asset: AVAsset,
        video: AVAssetTrack,
        audio: AVAssetTrack?,
        composition: AVVideoComposition,
        side: Int,
        to target: URL
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [video],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw Failure.exportFailed("video output") }
        reader.add(videoOutput)
        var audioOutput: AVAssetReaderTrackOutput?
        if let audio {
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        let writer = try AVAssetWriter(outputURL: target, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: side,
            AVVideoHeightKey: side,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_024_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw Failure.exportFailed("video input") }
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 64_000,
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else { throw Failure.exportFailed(reader.error?.localizedDescription) }
        guard writer.startWriting() else { throw Failure.exportFailed(writer.error?.localizedDescription) }
        writer.startSession(atSourceTime: .zero)
        let videoPump = SamplePump(input: videoInput, output: videoOutput, label: "video")
        let audioPump = audioInput.flatMap { input in audioOutput.map { SamplePump(input: input, output: $0, label: "audio") } }
        async let videoDone: Void = videoPump.run()
        await audioPump?.run()
        await videoDone
        if reader.status == .failed {
            writer.cancelWriting()
            throw Failure.exportFailed(reader.error?.localizedDescription)
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure.exportFailed(writer.error?.localizedDescription) }
    }

    /// Первый кадр кружка в JPEG: пузырь показывает его, пока сервер не прислал свой.
    static func writePoster(of video: URL, to target: URL) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: side, height: side)
        guard let image = try? await generator.image(at: CMTime(value: 1, timescale: 10)).image else { return }
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: target)
    }
}

/// Перекладывает отсчёты из чтения в запись, пока вход готов их принять.
/// Чтение и запись живут только в этом перекодировании, поэтому `@unchecked Sendable`.
private final class SamplePump: @unchecked Sendable {
    private let input: AVAssetWriterInput
    private let output: AVAssetReaderOutput
    private let queue: DispatchQueue
    private var done = false

    init(input: AVAssetWriterInput, output: AVAssetReaderOutput, label: String) {
        self.input = input
        self.output = output
        queue = DispatchQueue(label: "maxly.note.\(label)")
    }

    func run() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !done else { return }
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                        done = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }
}

/// Живая картинка камеры для кружка.
struct NoteCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
