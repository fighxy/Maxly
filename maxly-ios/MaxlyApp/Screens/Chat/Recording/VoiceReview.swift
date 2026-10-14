import Foundation
import MaxlyDomain
import Observation
import SwiftUI
import MaxlyUI

/// Голосовое на просмотре перед отправкой: прослушать, обрезать ручками по
/// волне, отправить или выбросить. Обрезка — те же пакеты Opus без перекодирования.
@MainActor
@Observable
final class VoiceReview {
    let recording: VoiceRecording
    let duration: Double
    var start: Double = 0
    var end: Double = 1
    private(set) var isPlaying = false
    /// Место воспроизведения, доля всей записи.
    private(set) var position: Double = 0

    @ObservationIgnored private let player = SystemVoicePlayer()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Следующее нажатие начинает кусок сначала: плеер остановлен или ручки сдвинуты.
    @ObservationIgnored private var restart = true

    /// Короче секунды голосовое не обрезается.
    static let minimumSeconds: Double = 1

    init(recording: VoiceRecording) {
        self.recording = recording
        duration = max(0.1, Double(recording.durationMs) / 1000)
    }

    var minimumSpan: Double { min(1, Self.minimumSeconds / duration) }
    var selectedSeconds: Double { (end - start) * duration }

    /// Играть выбранный кусок или остановить.
    func togglePlay() {
        if isPlaying {
            pause()
            return
        }
        if restart || position < start || position >= end - 0.005 {
            guard player.play(url: recording.url) else { return }
            player.seek(to: start)
            restart = false
        } else if !player.resume() {
            return
        }
        isPlaying = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.isPlaying else { return }
                self.position = self.player.progress
                if self.position >= self.end || !self.player.isPlaying {
                    self.player.pause()
                    self.isPlaying = false
                    self.position = self.start
                    self.restart = true
                    return
                }
            }
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        ticker?.cancel()
    }

    func stop() {
        ticker?.cancel()
        player.stop()
        isPlaying = false
        position = start
        restart = true
    }

    /// Ручку тянут: остановить и встать на её место.
    func handleMoved() {
        if isPlaying { stop() }
        position = start
    }

    /// Выбранный кусок: целиком — как есть, иначе новый файл. `nil` — не вышло.
    func result() -> VoiceRecording? {
        stop()
        if start <= 0.001 && end >= 0.999 { return recording }
        do {
            let cut = try recording.trimmed(fromMs: Int64(start * duration * 1000), toMs: Int64(end * duration * 1000))
            try? FileManager.default.removeItem(at: recording.url.deletingLastPathComponent())
            return cut
        } catch {
            Log.warning(.media, "Голосовое не обрезано: \(error)")
            return nil
        }
    }

    func discard() {
        stop()
        try? FileManager.default.removeItem(at: recording.url.deletingLastPathComponent())
    }
}

/// Полоса просмотра голосового: кнопка воспроизведения, волна с ручками обрезки и время.
struct VoiceReviewStrip: View {
    let review: VoiceReview
    private let handle: CGFloat = 12

    var body: some View {
        HStack(spacing: 8) {
            Button {
                review.togglePlay()
            } label: {
                Image(systemName: review.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.maxlyOnAccent)
                    .frame(width: 30, height: 30)
                    .background(Color.maxlyAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(review.isPlaying ? "Пауза" : "Прослушать")
            wave
            Text(RecordingBar.clock(review.selectedSeconds).components(separatedBy: ",").first ?? "")
                .font(.app(.footnote).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var wave: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let left = review.start * width
            let right = review.end * width
            let bars = review.recording.waveform.isEmpty ? Array(repeating: 10, count: 40) : review.recording.waveform
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 1.5) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                        let fraction = (Double(index) + 0.5) / Double(bars.count)
                        let inside = fraction >= review.start && fraction <= review.end
                        let played = review.isPlaying && fraction <= review.position
                        Capsule()
                            .fill(played ? Color.maxlyAccent : (inside ? Color.primary.opacity(0.55) : Color.primary.opacity(0.18)))
                            .frame(height: max(3, CGFloat(value) / 120 * geo.size.height))
                    }
                }
                .frame(width: width, height: geo.size.height)
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.maxlyAccent, lineWidth: 2)
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
            .coordinateSpace(name: "voice-trim")
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel("Обрезка голосового: \(Int(review.selectedSeconds.rounded())) с")
    }

    private var knob: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.maxlyAccent)
            .frame(width: handle)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -10))
    }

    private func drag(width: CGFloat, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("voice-trim"))
            .onChanged { value in
                guard width > 0 else { return }
                let fraction = min(1, max(0, value.location.x / width))
                if leading {
                    review.start = max(0, min(fraction, review.end - review.minimumSpan))
                } else {
                    review.end = min(1, max(fraction, review.start + review.minimumSpan))
                }
                review.handleMoved()
            }
    }
}
