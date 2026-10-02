import AVFoundation
import Foundation
import Observation
import OrbitleData
import OrbitleDomain

/// Записанное голосовое: файл Ogg/Opus, длительность и дорожка громкости для пузыря.
struct VoiceRecording: Sendable {
    let url: URL
    let durationMs: Int64
    /// 80 столбиков 0…120, как отправляет Komet.
    let waveform: [Int]
}

/// Запись голосового: микрофон, счётчик времени и живой уровень громкости.
///
/// Звук с микрофона (`AVAudioEngine`) переводится в 48 кГц моно, кодируется системным кодером
/// Opus и раскладывается по страницам Ogg (`OggOpusWriter`): сервер Max доводит до готовности
/// только Ogg/Opus. Кодирование идёт на своей очереди, экран видит только время и уровень.
@MainActor
@Observable
final class VoiceRecorder {
    private(set) var isRecording = false
    /// Секунды записи.
    private(set) var elapsed: TimeInterval = 0
    /// Текущая громкость 0…1 для пульсации кнопки.
    private(set) var level: Double = 0

    /// Короче этого голосовое не отправляется: это случайное касание.
    static let minimumDuration: TimeInterval = 0.6
    /// Длиннее запись останавливается сама.
    static let maximumDuration: TimeInterval = 15 * 60

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var encoder: VoiceEncoder?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date()
    /// Вызывается, когда запись упёрлась в предел длительности.
    @ObservationIgnored var onLimit: (() -> Void)?

    /// Доступ к микрофону: спрашивается при первой записи.
    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceEncoder.Failure.noInput }
        let encoder = try VoiceEncoder(inputFormat: format)
        encoder.install(on: input, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.encoder = encoder
        startedAt = .now
        elapsed = 0
        level = 0
        isRecording = true
        Log.info(.media, "Запись голосового: \(Int(format.sampleRate)) Гц, каналов \(format.channelCount)")
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.isRecording else { return }
                self.elapsed = Date.now.timeIntervalSince(self.startedAt)
                self.level = Double(encoder.currentLevel)
                if self.elapsed >= Self.maximumDuration { self.onLimit?() }
            }
        }
    }

    /// Остановить и получить файл. `nil` — запись слишком короткая или не вышла.
    func stop() async -> VoiceRecording? {
        guard isRecording, let encoder else { return nil }
        halt()
        let result = await encoder.finish()
        deactivateSession()
        guard let result else {
            Log.warning(.media, "Голосовое не записалось")
            return nil
        }
        guard Double(result.durationMs) / 1000 >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: result.url)
            return nil
        }
        Log.info(.media, "Голосовое записано: \(result.durationMs) мс")
        return result
    }

    /// Остановить и выбросить запись.
    func cancel() {
        guard isRecording else { return }
        let encoder = encoder
        halt()
        encoder?.discard()
        deactivateSession()
    }

    private func halt() {
        ticker?.cancel()
        ticker = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        encoder = nil
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Кодирование на своей очереди. Не привязан к главному актору: блок записи звука вызывается
/// с потока звука, а замыкание, созданное внутри `@MainActor`, упало бы на проверке изоляции.
final class VoiceEncoder: @unchecked Sendable {
    enum Failure: Error {
        case noInput
        case noCodec
    }

    private let queue = DispatchQueue(label: "orbitle.voice.encoder")
    private let pcmFormat: AVAudioFormat
    private let opusFormat: AVAudioFormat
    private let resampler: AVAudioConverter
    private let encoder: AVAudioConverter
    // Всё ниже меняется только на `queue`.
    private var writer = OggOpusWriter()
    private var pending: [AVAudioPCMBuffer] = []
    private var frames: Int64 = 0
    private var peaks: [Float] = []
    private var discarded = false
    // Уровень для экрана читается с главного потока.
    private let levelLock = NSLock()
    private var level: Float = 0

    init(inputFormat: AVAudioFormat) throws {
        guard let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false) else {
            throw Failure.noCodec
        }
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 960, mBytesPerFrame: 0, mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0
        )
        guard let opus = AVAudioFormat(streamDescription: &description),
              let resampler = AVAudioConverter(from: inputFormat, to: pcm),
              let encoder = AVAudioConverter(from: pcm, to: opus) else {
            throw Failure.noCodec
        }
        encoder.bitRate = 32_000
        pcmFormat = pcm
        opusFormat = opus
        self.resampler = resampler
        self.encoder = encoder
    }

    var currentLevel: Float {
        levelLock.lock()
        defer { levelLock.unlock() }
        return level
    }

    func install(on node: AVAudioInputNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
    }

    /// Блок записи: буфер переиспользуется, поэтому он сразу пересчитывается в свой 48 кГц.
    private func consume(_ buffer: AVAudioPCMBuffer) {
        let ratio = 48_000 / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256
        guard buffer.frameLength > 0, let converted = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: capacity) else { return }
        // Буферы звука не Sendable, но живут только внутри этого вызова и очереди кодера.
        nonisolated(unsafe) let source = buffer
        let once = Once()
        var error: NSError?
        resampler.convert(to: converted, error: &error) { _, status in
            guard once.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return source
        }
        guard error == nil, converted.frameLength > 0 else { return }
        let peak = Self.peak(converted)
        levelLock.lock()
        level = Self.normalized(peak)
        levelLock.unlock()
        nonisolated(unsafe) let chunk = converted
        queue.async { [self] in
            guard !discarded else { return }
            frames += Int64(chunk.frameLength)
            peaks.append(peak)
            pending.append(chunk)
            drain(end: false)
        }
    }

    /// Дописать хвост и сохранить файл.
    func finish() async -> VoiceRecording? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard !discarded else {
                    continuation.resume(returning: nil)
                    return
                }
                drain(end: true)
                let data = writer.finish()
                guard frames > 0, data.count > 200 else {
                    continuation.resume(returning: nil)
                    return
                }
                do {
                    let url = try Self.target()
                    try data.write(to: url)
                    let durationMs = frames * 1000 / 48_000
                    continuation.resume(returning: VoiceRecording(url: url, durationMs: durationMs, waveform: Self.wave(peaks)))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func discard() {
        queue.async { [self] in
            discarded = true
            pending.removeAll()
        }
    }

    /// Прогнать накопленный звук через кодер и сложить пакеты в Ogg.
    private func drain(end: Bool) {
        let capacity = max(encoder.maximumOutputPacketSize, 1500)
        let output = AVAudioCompressedBuffer(format: opusFormat, packetCapacity: 32, maximumPacketSize: capacity)
        while true {
            var error: NSError?
            let status = encoder.convert(to: output, error: &error) { [self] _, inputStatus in
                if !pending.isEmpty {
                    inputStatus.pointee = .haveData
                    return pending.removeFirst()
                }
                inputStatus.pointee = end ? .endOfStream : .noDataNow
                return nil
            }
            if let descriptions = output.packetDescriptions {
                for index in 0..<Int(output.packetCount) {
                    let item = descriptions[index]
                    let packet = Data(bytes: output.data.advanced(by: Int(item.mStartOffset)), count: Int(item.mDataByteSize))
                    writer.append(packet: packet)
                }
            }
            let produced = output.packetCount
            output.packetCount = 0
            if status == .error || status == .endOfStream || status == .inputRanDry || produced == 0 { break }
        }
    }

    private static func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(samples[index]))
        }
        return peak
    }

    /// Громкость 0…1 по шкале −50…0 дБ.
    private static func normalized(_ peak: Float) -> Float {
        guard peak > 0 else { return 0 }
        let db = 20 * log10(peak)
        return min(1, max(0, (db + 50) / 50))
    }

    /// 80 столбиков: пик каждого отрезка записи, 0…120 (как у Komet).
    static func wave(_ peaks: [Float], bars: Int = 80) -> [Int] {
        guard !peaks.isEmpty else { return [] }
        return (0..<bars).map { index in
            let start = index * peaks.count / bars
            let end = min(peaks.count, max(start + 1, (index + 1) * peaks.count / bars))
            let peak = peaks[start..<end].max() ?? 0
            return Int((normalized(peak) * 120).rounded())
        }
    }

    private static func target() throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = caches.appendingPathComponent("Outgoing", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("voice.ogg")
    }
}

/// Флаг «один раз» для блока конвертера: он может вызываться несколько раз за `convert`.
private final class Once: @unchecked Sendable {
    private var used = false

    func take() -> Bool {
        guard !used else { return false }
        used = true
        return true
    }
}
