import Foundation
import Observation
import MaxlyDomain

/// Голосовые открытого чата: пуск, пауза, перемотка, скачивание файла перед первым
/// проигрыванием и полоса «играет голосовое» (`VoiceNowPlaying`), которой эта модель владеет,
/// пока её голосовое играет. Плеер один на приложение (`VoicePlaying`).
@MainActor
@Observable
public final class VoicePlaybackModel {
    public let chatId: String
    public let currentUserId: String
    /// Фаза голосового по id вложения; нет записи — не играет.
    public private(set) var phases: [String: VoicePhase] = [:]
    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private let media: (any MediaRepository)?
    @ObservationIgnored private let voice: (any VoicePlaying)?
    /// Полоса «играет голосовое»; `nil` — без неё.
    @ObservationIgnored public var nowPlaying: VoiceNowPlaying?
    /// Голосовое вот-вот заиграет: кружок в ленте останавливается.
    @ObservationIgnored public var onWillPlay: (() -> Void)?
    @ObservationIgnored private var activeId: String?
    @ObservationIgnored private var activeMessage: Message?
    @ObservationIgnored private var followTask: Task<Void, Never>?
    @ObservationIgnored private var toggleTask: Task<Void, Never>?
    /// Перемотка, пришедшая, пока файл качается: применяется, когда плеер откроется.
    @ObservationIgnored private var pendingSeek: (id: String, fraction: Double)?

    public init(
        chatId: String,
        currentUserId: String,
        repository: any MessageRepository,
        media: (any MediaRepository)?,
        voice: (any VoicePlaying)?
    ) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.repository = repository
        self.media = media
        self.voice = voice
    }

    public func phase(for id: String) -> VoicePhase {
        phases[id] ?? .idle
    }

    public func toggle(_ message: Message) {
        onWillPlay?()
        toggleTask?.cancel()
        toggleTask = Task { await self.play(message) }
    }

    /// Перемотка голосового касанием или протяжкой по дорожке, как у популярных мессенджеров:
    /// играющее продолжает с нового места, на паузе и не начатое — начинает играть с него.
    /// Пока файл качается, место запоминается и применяется, когда плеер откроется.
    public func seek(_ message: Message, to fraction: Double) {
        guard let clip = message.content.voices.first else { return }
        let target = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        if activeId == clip.id {
            switch phase(for: clip.id) {
            case .playing:
                voice?.seek(to: target)
                phases[clip.id] = .playing(target)
                return
            case .paused:
                toggleTask?.cancel()
                voice?.seek(to: target)
                if voice?.resume() == true {
                    phases[clip.id] = .playing(target)
                    followProgress(clip.id)
                    reportNowPlaying(claim: true)
                } else {
                    phases[clip.id] = .failed
                    activeId = nil
                }
                return
            case .downloading:
                pendingSeek = (clip.id, target)
                return
            case .idle, .failed:
                break
            }
        }
        pendingSeek = (clip.id, target)
        toggle(message)
    }

    public func stop() {
        toggleTask?.cancel()
        toggleTask = nil
        followTask?.cancel()
        followTask = nil
        voice?.stop()
        if let id = activeId { phases[id] = .idle }
        activeId = nil
        nowPlaying?.clear(self)
    }

    /// Полоса «играет голосовое»: что, чьё, где и сколько. `claim` — этот чат начал голосовое.
    private func reportNowPlaying(claim: Bool = false) {
        guard let nowPlaying, let id = activeId, let message = activeMessage,
              let clip = message.content.voices.first, clip.id == id else { return }
        let phase = phase(for: id)
        let author = message.authorId == currentUserId ? "Вы" : message.authorName
        let track = VoiceNowPlaying.Track(
            chatId: chatId,
            messageId: message.id,
            author: author,
            date: message.timestamp,
            progress: phase.progress,
            durationMs: clip.durationMs,
            isPlaying: phase.isPlaying
        )
        if claim { nowPlaying.claim(self, track: track) } else { nowPlaying.update(self, track: track) }
    }

    private func play(_ message: Message) async {
        guard let clip = message.content.voices.first else { return }
        if activeId == clip.id, phase(for: clip.id).isPlaying {
            voice?.pause()
            phases[clip.id] = .paused(voice?.progress ?? phase(for: clip.id).progress)
            followTask?.cancel()
            followTask = nil
            reportNowPlaying()
            return
        }
        if activeId == clip.id, case .paused = phase(for: clip.id) {
            if voice?.resume() == true {
                phases[clip.id] = .playing(voice?.progress ?? 0)
                followProgress(clip.id)
                reportNowPlaying(claim: true)
            } else {
                phases[clip.id] = .failed
            }
            return
        }
        stopPlayback()
        activeId = clip.id
        activeMessage = message
        if let file = clip.fileURL {
            startPlayback(clip.id, url: file)
            return
        }
        guard let item = clip.cacheItem(), let media else {
            phases[clip.id] = .failed
            activeId = nil
            return
        }
        phases[clip.id] = .downloading(0)
        do {
            let file = try await media.preview(for: item)
            guard !Task.isCancelled, activeId == clip.id else { return }
            await repository.noteDownloaded(messageId: message.id, attachmentId: clip.id, localPath: file.path)
            guard !Task.isCancelled, activeId == clip.id else { return }
            startPlayback(clip.id, url: file)
        } catch {
            guard activeId == clip.id else { return }
            phases[clip.id] = .failed
            activeId = nil
        }
    }

    /// Останавливает плеер, не отменяя задачу, которая сейчас качает следующий файл.
    private func stopPlayback() {
        followTask?.cancel()
        followTask = nil
        voice?.stop()
        if let id = activeId { phases[id] = .idle }
        activeId = nil
        nowPlaying?.clear(self)
    }

    private func startPlayback(_ id: String, url: URL) {
        let seek = pendingSeek
        pendingSeek = nil
        guard let voice, voice.play(url: url) else {
            phases[id] = .failed
            activeId = nil
            return
        }
        if let seek, seek.id == id {
            voice.seek(to: seek.fraction)
            phases[id] = .playing(seek.fraction)
        } else {
            phases[id] = .playing(0)
        }
        followProgress(id)
        reportNowPlaying(claim: true)
    }

    private func followProgress(_ id: String) {
        followTask?.cancel()
        followTask = Task { @MainActor [weak self] in
            var seenPlaying = false
            var silentTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.activeId == id else { return }
                if self.voice?.failed == true {
                    self.phases[id] = .failed
                    self.activeId = nil
                    return
                }
                let playing = self.voice?.isPlaying ?? false
                let progress = self.voice?.progress ?? 0
                if playing {
                    seenPlaying = true
                    silentTicks = 0
                    self.phases[id] = .playing(progress)
                    self.reportNowPlaying()
                } else if seenPlaying {
                    // Пауза тоже останавливает плеер. Это не конец записи: фазу паузы
                    // оставляет кнопка, а слежение её не затирает.
                    if case .paused = self.phase(for: id) { continue }
                    self.phases[id] = .idle
                    self.activeId = nil
                    self.voice?.stop()
                    self.nowPlaying?.clear(self)
                    return
                } else {
                    silentTicks += 1
                    // Плеер принял файл, но так и не начал. Иначе пузырь крутится бесконечно.
                    if silentTicks >= 15 {
                        self.voice?.stop()
                        self.phases[id] = .failed
                        self.activeId = nil
                        return
                    }
                }
            }
        }
    }
}

// MARK: Полоса «играет голосовое»

extension VoicePlaybackModel: VoiceNowPlayingOwner {
    public func nowPlayingToggle() {
        guard let message = activeMessage else { return }
        toggle(message)
    }

    public func nowPlayingStop() {
        stop()
    }

    /// Голосовое начал другой чат: плеер уже его, здесь только сброс своего состояния.
    public func nowPlayingReleased() {
        toggleTask?.cancel()
        toggleTask = nil
        followTask?.cancel()
        followTask = nil
        if let id = activeId { phases[id] = .idle }
        activeId = nil
        activeMessage = nil
    }
}
