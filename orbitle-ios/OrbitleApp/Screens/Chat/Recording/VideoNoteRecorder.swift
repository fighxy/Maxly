import AVFoundation
import Foundation
import Observation
import OrbitleDomain
import SwiftUI
import UIKit

/// Записанный кружок: квадратный MP4, длительность и сторона кадра.
struct VideoNoteRecording: Sendable {
    let url: URL
    let durationMs: Int64
    let side: Int
}

/// Запись круглого видеосообщения, как в Telegram: фронтальная камера, до минуты.
///
/// Камера пишет обычный ролик, после остановки он обрезается по центру в квадрат
/// 480×480 (`VideoNoteExporter`): круг рисует уже пузырь.
@MainActor
@Observable
final class VideoNoteRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0

    static let maximumDuration: TimeInterval = 60
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
    private let queue = DispatchQueue(label: "orbitle.note.capture")
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
                // Как в зеркале: так видит себя пишущий и так кружок выглядит в Telegram.
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        configured = true
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
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.instructions = [instruction]

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else {
            throw Failure.exportFailed(nil)
        }
        session.videoComposition = composition
        session.shouldOptimizeForNetworkUse = true
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = caches.appendingPathComponent("Outgoing", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("note.mp4")
        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: target, as: .mp4)
            } catch {
                throw Failure.exportFailed(error.localizedDescription)
            }
        } else {
            session.outputURL = target
            session.outputFileType = .mp4
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else {
                throw Failure.exportFailed(session.error?.localizedDescription)
            }
        }
        let seconds = CMTimeGetSeconds(duration)
        let durationMs = seconds.isFinite ? Int64((seconds * 1000).rounded()) : 0
        return VideoNoteRecording(url: target, durationMs: durationMs, side: Int(out))
    }
}

/// Живая картинка камеры для кружка.
struct CameraPreview: UIViewRepresentable {
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
