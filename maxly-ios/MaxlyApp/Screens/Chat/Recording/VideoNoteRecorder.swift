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
    private(set) var elapsed: TimeInterval = 0

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
        Log.info(.media, "Запись кружка началась")
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isRecording else { return }
                self.elapsed = Date.now.timeIntervalSince(self.startedAt)
                if self.elapsed >= Self.maximumDuration { self.onLimit?() }
            }
        }
    }

    /// Остановить и получить квадратный ролик. `nil` — слишком коротко или не вышло.
    func stop() async -> VideoNoteRecording? {
        guard isRecording else { return nil }
        ticker?.cancel()
        ticker = nil
        isRecording = false
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
        capture.cancel()
    }
}

/// Сессия камеры на своей очереди: `startRunning` блокирует поток, а делегат записи
/// вызывается не на главном.
final class CaptureController: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    enum Failure: Error {
        case noCamera
    }

    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "maxly.note.capture")
    // Меняется только на `queue`.
    private var configured = false
    private var finished: CheckedContinuation<URL?, Never>?
    private var autoFinished: URL?
    private var discardNext = false

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try configure()
                    if !session.isRunning { session.startRunning() }
                    autoFinished = nil
                    discardNext = false
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("note-\(UUID().uuidString).mov")
                    output.startRecording(to: url, recordingDelegate: self)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopRecording() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard output.isRecording else {
                    // Минута кончилась раньше: файл уже готов.
                    continuation.resume(returning: autoFinished)
                    autoFinished = nil
                    return
                }
                finished = continuation
                output.stopRecording()
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
            if output.isRecording {
                discardNext = true
                output.stopRecording()
            }
            if let autoFinished { try? FileManager.default.removeItem(at: autoFinished) }
            autoFinished = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() throws {
        guard !configured else { return }
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
        preferSixtyFrames(camera)
        if let microphone = AVCaptureDevice.default(for: .audio),
           let audio = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(audio) {
            session.addInput(audio)
        }
        guard session.canAddOutput(output) else { throw Failure.noCamera }
        session.addOutput(output)
        output.maxRecordedDuration = CMTime(seconds: VideoNoteRecorder.maximumDuration, preferredTimescale: 600)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                // Как в зеркале: так видит себя пишущий и так кружок привычно выглядит в мессенджерах.
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        configured = true
    }

    /// 60 кадров в секунду, если камера умеет: самый маленький формат не меньше 480 по короткой
    /// стороне с 60 fps (сессия тогда переходит в `inputPriority`). Иначе остаётся пресет.
    private func preferSixtyFrames(_ camera: AVCaptureDevice) {
        func area(_ format: AVCaptureDevice.Format) -> Int32 {
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return size.width * size.height
        }
        let candidates = camera.formats.filter { format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return min(size.width, size.height) >= Int32(VideoNoteExporter.side)
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 }
        }
        guard let format = candidates.min(by: { area($0) < area($1) }) else { return }
        do {
            try camera.lockForConfiguration()
            camera.activeFormat = format
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
            camera.unlockForConfiguration()
        } catch {
            // Не вышло — пишем с частотой пресета.
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        let finishedKey = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool
        let success = error == nil || finishedKey == true
        queue.async { [self] in
            if discardNext {
                discardNext = false
                try? FileManager.default.removeItem(at: url)
                finished?.resume(returning: nil)
                finished = nil
                return
            }
            let result = success ? url : nil
            if let finished {
                finished.resume(returning: result)
                self.finished = nil
            } else {
                autoFinished = result
            }
        }
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
