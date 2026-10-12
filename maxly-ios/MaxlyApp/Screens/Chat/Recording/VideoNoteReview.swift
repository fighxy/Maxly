import AVFoundation
import Foundation
import Observation
import SwiftUI
import MaxlyDomain
import UIKit

/// Просмотр записанного кружка перед отправкой, как в Telegram: кружок играет по кругу (без
/// звука, касание включает звук), под ним полоса кадров с ручками обрезки; корзина выбрасывает,
/// кнопка отправки шлёт выбранный кусок.
@MainActor
@Observable
final class VideoNoteReview {
    let note: VideoNoteRecording
    /// Длительность ролика, с.
    let duration: Double
    /// Начало и конец выбранного куска, доли длительности.
    var start: Double = 0
    var end: Double = 1
    private(set) var thumbnails: [UIImage] = []
    private(set) var muted = true

    @ObservationIgnored let player = AVQueuePlayer()
    @ObservationIgnored private var looper: AVPlayerLooper?

    nonisolated static let thumbnailCount = 8
    /// Короче секунды кружок не отправляется.
    static let minimumSeconds: Double = 1

    init(note: VideoNoteRecording) {
        self.note = note
        duration = max(0.1, Double(note.durationMs) / 1000)
        player.isMuted = true
        restartLoop()
    }

    /// Наименьшая длина куска, доля длительности.
    var minimumSpan: Double { min(1, Self.minimumSeconds / duration) }

    var selectedSeconds: Double { (end - start) * duration }

    func toggleMuted() {
        muted.toggle()
        player.isMuted = muted
    }

    /// Ручку двигают: показать кадр под ней.
    func preview(at fraction: Double) {
        player.pause()
        player.seek(to: CMTime(seconds: fraction * duration, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Играть выбранный кусок по кругу.
    func restartLoop() {
        looper?.disableLooping()
        player.removeAllItems()
        let item = AVPlayerItem(url: note.url)
        let range = CMTimeRange(
            start: CMTime(seconds: start * duration, preferredTimescale: 600),
            end: CMTime(seconds: end * duration, preferredTimescale: 600)
        )
        looper = AVPlayerLooper(player: player, templateItem: item, timeRange: range)
        player.play()
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }

    /// Кадры для полосы обрезки.
    func loadThumbnails() async {
        thumbnails = await Self.frames(of: note.url, duration: duration)
    }

    /// Кадры вне главного актора: генератор живёт только здесь.
    private nonisolated static func frames(of url: URL, duration: Double) async -> [UIImage] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)
        var images: [UIImage] = []
        for index in 0..<thumbnailCount {
            let seconds = duration * (Double(index) + 0.5) / Double(thumbnailCount)
            if let image = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image {
                images.append(UIImage(cgImage: image))
            }
        }
        return images
    }

    /// Выбранный кусок: весь ролик — как есть, иначе обрезанная копия. `nil` — не вышло.
    func result() async -> VideoNoteRecording? {
        stop()
        if start <= 0.001 && end >= 0.999 { return note }
        let from = start * duration
        let to = end * duration
        guard let trimmed = await Self.trim(note.url, from: from, to: to) else { return nil }
        try? FileManager.default.removeItem(at: note.url.deletingLastPathComponent())
        return VideoNoteRecording(url: trimmed, durationMs: Int64(((to - from) * 1000).rounded()), side: note.side)
    }

    /// Выбросить запись.
    func discard() {
        stop()
        try? FileManager.default.removeItem(at: note.url.deletingLastPathComponent())
    }

    /// Кусок ролика в новую папку отправки (`note.mp4` и `poster.jpg`, как у записи).
    private nonisolated static func trim(_ source: URL, from: Double, to: Double) async -> URL? {
        do {
            let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = caches.appendingPathComponent("Outgoing", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("note.mp4")
            guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough) else { return nil }
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: from, preferredTimescale: 600),
                end: CMTime(seconds: to, preferredTimescale: 600)
            )
            if #available(iOS 18, *) {
                try await session.export(to: target, as: .mp4)
            } else {
                session.outputURL = target
                session.outputFileType = .mp4
                await session.export()
                guard session.status == .completed else { return nil }
            }
            await VideoNoteExporter.writePoster(of: target, to: folder.appendingPathComponent("poster.jpg"))
            return target
        } catch {
            Log.warning(.media, "Кружок не обрезан: \(error)")
            return nil
        }
    }
}

/// Полоса кадров с ручками обрезки: вне выбранного куска кадры затемнены.
struct VideoNoteTrimStrip: View {
    let review: VideoNoteReview
    private let handle: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let left = review.start * width
            let right = review.end * width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(review.thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width / CGFloat(VideoNoteReview.thumbnailCount), height: geo.size.height)
                            .clipped()
                    }
                }
                .frame(width: width, height: geo.size.height, alignment: .leading)
                .background(Color.black.opacity(0.2))
                // Вне выбранного куска — тень.
                Color.black.opacity(0.55)
                    .frame(width: max(0, left))
                Color.black.opacity(0.55)
                    .frame(width: max(0, width - right))
                    .offset(x: right)
                // Рамка куска и ручки.
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.maxlyAccent, lineWidth: 3)
                    .frame(width: max(handle * 2, right - left), height: geo.size.height)
                    .offset(x: left)
                    .allowsHitTesting(false)
                knob
                    .offset(x: left)
                    .gesture(drag(width: width, leading: true))
                knob
                    .offset(x: right - handle)
                    .gesture(drag(width: width, leading: false))
            }
            .coordinateSpace(name: "trim")
        }
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement()
        .accessibilityLabel("Обрезка кружка: \(Int(review.selectedSeconds.rounded())) с")
    }

    private var knob: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.maxlyAccent)
            Capsule()
                .fill(Color.white)
                .frame(width: 3, height: 14)
        }
        .frame(width: handle)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle().inset(by: -10))
    }

    private func drag(width: CGFloat, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("trim"))
            .onChanged { value in
                guard width > 0 else { return }
                let fraction = min(1, max(0, value.location.x / width))
                if leading {
                    review.start = min(fraction, review.end - review.minimumSpan)
                    review.start = max(0, review.start)
                    review.preview(at: review.start)
                } else {
                    review.end = max(fraction, review.start + review.minimumSpan)
                    review.end = min(1, review.end)
                    review.preview(at: review.end)
                }
            }
            .onEnded { _ in review.restartLoop() }
    }
}

/// Слой плеера кружка на экране просмотра.
struct VideoNotePlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
