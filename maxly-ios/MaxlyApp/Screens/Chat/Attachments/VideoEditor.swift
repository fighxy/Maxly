import SwiftUI
import AVKit
import MaxlyDomain

/// Edits a copy; the attachment is replaced only after export succeeds.
struct VideoEditor: View {
    let draft: AttachmentDraft
    let onSave: (AttachmentDraft) -> Void
    let onClose: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var duration = 0.0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var muted = false
    @State private var busy = false
    @State private var failure: String?
    @State private var confirmClose = false

    private var changed: Bool { start > 0 || end < duration || muted }
    private var minimum: Double { min(0.25, duration) }

    var body: some View {
        GeometryReader { available in
        VStack(spacing: 0) {
            HStack {
                Button("Отмена") { if changed { confirmClose = true } else { onClose() } }
                Spacer()
                Text("Редактор видео").font(.headline)
                Spacer()
                Button("Готово") { save() }.disabled(duration <= 0)
            }.padding().disabled(busy)
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            ScrollView {
            VStack(spacing: 12) {
                if let failure { Text(failure).font(.footnote).foregroundStyle(.red) }
                if busy { ProgressView("Сохраняем видео…") }
                HStack {
                    Label("Обрезка", systemImage: "scissors")
                    Spacer()
                    Text(time(end - start)).monospacedDigit().foregroundStyle(.secondary)
                }
                if duration > 0 {
                    HStack { Text("Начало"); Spacer(); Text(time(start)).monospacedDigit() }
                    Slider(value: $start, in: 0...max(0.001, end - minimum), onEditingChanged: { editing in
                        if !editing { seek(start) }
                    }).accessibilityLabel("Начало фрагмента")
                    HStack { Text("Конец"); Spacer(); Text(time(end)).monospacedDigit() }
                    Slider(value: $end, in: min(duration - 0.001, start + minimum)...duration, onEditingChanged: { editing in
                        if !editing { seek(max(start, end - 0.1)) }
                    }).accessibilityLabel("Конец фрагмента")
                }
                HStack {
                    Button { seek(start); player?.play() } label: { Label("Смотреть", systemImage: "play.fill") }
                    Spacer()
                    Toggle("Без звука", isOn: $muted).fixedSize()
                }
                Button("Сбросить") { start = 0; end = duration; muted = false; seek(0) }.disabled(!changed)
            }.padding().disabled(busy || duration <= 0)
            }.frame(maxHeight: min(340, available.size.height * 0.48))
        }
        }
        .background(Color(uiColor: .systemBackground))
        .interactiveDismissDisabled(true)
        .confirmationDialog("Выйти без сохранения?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Выйти", role: .destructive, action: onClose)
            Button("Продолжить", role: .cancel) {}
        }
        .task {
            do {
                let asset = AVURLAsset(url: URL(fileURLWithPath: draft.path))
                let seconds = try await asset.load(.duration).seconds
                guard seconds.isFinite, seconds > 0 else { throw MediaExporter.Failure.unreadable }
                duration = seconds; end = seconds
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
            } catch { failure = "Не удалось открыть видео" }
        }
        .onChange(of: scenePhase) { _, value in if value != .active { player?.pause() } }
        .onChange(of: muted) { _, value in player?.isMuted = value }
        .onChange(of: end) { _, value in player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: value, preferredTimescale: 600) }
        .onDisappear { player?.pause(); player = nil }
    }

    private func seek(_ seconds: Double) {
        player?.pause()
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    private func time(_ seconds: Double) -> String {
        let tenths = Int(max(0, seconds) * 10)
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
    private func save() {
        guard !busy, duration > 0 else { return }
        player?.pause()
        if !changed { onSave(draft); return }
        busy = true; failure = nil
        Task {
            defer { busy = false }
            do { onSave(try await MediaExporter.editVideo(draft, start: start, end: end, muted: muted)) }
            catch { failure = "Не удалось сохранить видео. Попробуйте ещё раз." }
        }
    }
}
