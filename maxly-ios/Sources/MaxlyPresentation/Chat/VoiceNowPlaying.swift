import Foundation
import Observation

/// Тот, кто ведёт играющее голосовое (экран чата): полоса управляет им, пока оно играет.
@MainActor
public protocol VoiceNowPlayingOwner: AnyObject {
    /// Пауза или продолжение.
    func nowPlayingToggle()
    /// «Закрыть» на полосе: остановить голосовое.
    func nowPlayingStop()
    /// Голосовое начал другой чат: этот отпускает плеер, не трогая его.
    func nowPlayingReleased()
}

/// Что сейчас играет — для полосы над чатом и списком чатов, как в популярных мессенджерах:
/// пуск и пауза, автор, скорость 1x / 1.5x / 2x (голос не искажается), закрыть, переход к
/// сообщению. Одно голосовое на всё приложение.
@MainActor
@Observable
public final class VoiceNowPlaying {
    public struct Track: Equatable, Sendable {
        public var chatId: String
        public var messageId: String
        /// Автор; пусто — «Голосовое сообщение».
        public var author: String
        /// Время сообщения: чат открывается на нём без отдельного запроса.
        public var date: Date?
        public var progress: Double
        public var durationMs: Int64
        public var isPlaying: Bool

        public init(chatId: String, messageId: String, author: String, date: Date?, progress: Double, durationMs: Int64, isPlaying: Bool) {
            self.chatId = chatId
            self.messageId = messageId
            self.author = author
            self.date = date
            self.progress = progress
            self.durationMs = durationMs
            self.isPlaying = isPlaying
        }

        public var title: String { author.isEmpty ? "Голосовое сообщение" : author }

        /// «0:12 / 0:45».
        public var timeText: String {
            let total = Double(durationMs) / 1000
            return "\(Self.clock(total * min(max(progress, 0), 1))) / \(Self.clock(total))"
        }

        static func clock(_ seconds: Double) -> String {
            let value = Int(max(seconds, 0))
            return String(format: "%d:%02d", value / 60, value % 60)
        }
    }

    public nonisolated static let speeds: [Float] = [1, 1.5, 2]

    public private(set) var track: Track?
    public private(set) var speed: Float = 1
    /// Скорость в плеер: высота голоса не меняется.
    @ObservationIgnored public var applySpeed: ((Float) -> Void)?
    @ObservationIgnored private weak var owner: (any VoiceNowPlayingOwner)?

    public init() {}

    /// Чат начал или продолжил голосовое: прежний владелец отпускает плеер.
    public func claim(_ owner: any VoiceNowPlayingOwner, track: Track) {
        if let previous = self.owner, previous !== owner { previous.nowPlayingReleased() }
        self.owner = owner
        self.track = track
    }

    /// Ход и пауза от владельца.
    public func update(_ owner: any VoiceNowPlayingOwner, track: Track) {
        guard self.owner === owner else { return }
        if self.track != track { self.track = track }
    }

    /// Голосовое кончилось или остановлено у владельца.
    public func clear(_ owner: any VoiceNowPlayingOwner) {
        guard self.owner === owner else { return }
        self.owner = nil
        track = nil
    }

    public func toggle() { owner?.nowPlayingToggle() }

    public func stop() {
        owner?.nowPlayingStop()
        owner = nil
        track = nil
    }

    /// 1x → 1.5x → 2x → 1x.
    public func cycleSpeed() {
        speed = Self.next(speed)
        applySpeed?(speed)
    }

    public nonisolated static func next(_ speed: Float) -> Float {
        speeds.first { $0 > speed + 0.01 } ?? speeds[0]
    }

    public nonisolated static func label(_ speed: Float) -> String {
        speed >= 1.99 ? "2x" : speed >= 1.49 ? "1.5x" : "1x"
    }
}
