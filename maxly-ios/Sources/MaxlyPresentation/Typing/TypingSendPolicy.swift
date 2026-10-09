import Foundation
import MaxlyDomain

/// Кадр `MSG_TYPING` 65: `{chatId, type}`, в комментариях к посту ещё `postId`. Ответа нет.
public struct TypingFrame: Hashable, Sendable {
    public var chatId: String
    public var type: String
    public var postId: String?

    public init(chatId: String, type: String, postId: String? = nil) {
        self.chatId = chatId
        self.type = type
        self.postId = postId
    }
}

/// Когда отправлять «я печатаю». Чистая логика с внешними часами: каждое событие возвращает
/// кадры, которые нужно отправить прямо сейчас. Общие с Kotlin сценарии — `test-fixtures/typing`.
///
/// - Один порог на чат, общий для всех типов: кадр не уходит, если в этот чат что-то
///   отправлено меньше 6 с назад. Пропущенный кадр время порога не сдвигает.
/// - `TEXT` — на каждую правку текста в поле ввода.
/// - `AUDIO` и `VIDEO_MSG` — в начале записи и повторно каждые 5 с от её начала, пока она идёт
///   (повтор тоже проходит порог). Повторы делает `tick()`, его время — `nextRepeat`.
/// - `PHOTO`, `VIDEO`, `FILE` — на события хода загрузки.
/// - `STICKER` — при открытии панели стикеров.
/// - Отдельного «перестал» нет: у получателя отметка истекает сама.
/// - В чат, куда писать нельзя (канал без прав), ничего не уходит.
public struct TypingSendPolicy: Sendable {
    /// Порог на чат.
    public static let throttle: TimeInterval = 6
    /// Шаг повтора во время записи.
    public static let recordingRepeat: TimeInterval = 5

    private struct Recording: Sendable {
        var kind: TypingKind
        var postId: String?
        /// Когда следующий повтор, мс.
        var next: Int64
    }

    private let clock: @Sendable () -> Date
    /// id чата → время последнего отправленного кадра, мс.
    private var lastSent: [String: Int64] = [:]
    /// Идущие записи: id чата → запись.
    private var recordings: [String: Recording] = [:]

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    /// Правка текста в поле ввода.
    public mutating func textEdited(chatId: String, postId: String? = nil, canWrite: Bool = true) -> [TypingFrame] {
        report(.text, chatId: chatId, postId: postId, canWrite: canWrite)
    }

    /// Ход загрузки фото, видео или файла.
    public mutating func uploadProgress(_ kind: TypingKind, chatId: String, postId: String? = nil, canWrite: Bool = true) -> [TypingFrame] {
        report(kind, chatId: chatId, postId: postId, canWrite: canWrite)
    }

    /// Открыта панель стикеров.
    public mutating func stickerPanelOpened(chatId: String, postId: String? = nil, canWrite: Bool = true) -> [TypingFrame] {
        report(.sticker, chatId: chatId, postId: postId, canWrite: canWrite)
    }

    /// Разовое действие любого типа: кадр, если чат позволяет писать и порог пройден.
    public mutating func report(_ kind: TypingKind, chatId: String, postId: String? = nil, canWrite: Bool = true) -> [TypingFrame] {
        // «Избранное»: собеседника нет, «печатает…» видеть некому.
        guard canWrite, !chatId.isEmpty, chatId != Chat.savedMessagesId else { return [] }
        return attempt(kind, chatId: chatId, postId: postId, at: now())
    }

    /// Началась запись голосового (`.audio`) или кружка (`.videoMessage`).
    public mutating func recordingStarted(_ kind: TypingKind, chatId: String, postId: String? = nil, canWrite: Bool = true) -> [TypingFrame] {
        // «Избранное»: собеседника нет, «печатает…» видеть некому.
        guard canWrite, !chatId.isEmpty, chatId != Chat.savedMessagesId else { return [] }
        let at = now()
        recordings[chatId] = Recording(kind: kind, postId: postId, next: at + Self.millis(Self.recordingRepeat))
        return attempt(kind, chatId: chatId, postId: postId, at: at)
    }

    /// Запись закончилась (отправлена или отменена): повторов больше нет.
    public mutating func recordingStopped(chatId: String) {
        recordings[chatId] = nil
    }

    /// Повторы идущих записей, чьё время пришло. Несколько пропущенных шагов дают один кадр.
    public mutating func tick() -> [TypingFrame] {
        let at = now()
        let step = Self.millis(Self.recordingRepeat)
        var frames: [TypingFrame] = []
        for chatId in recordings.keys.sorted() {
            guard var recording = recordings[chatId], recording.next <= at else { continue }
            while recording.next <= at { recording.next += step }
            recordings[chatId] = recording
            frames += attempt(recording.kind, chatId: chatId, postId: recording.postId, at: at)
        }
        return frames
    }

    /// Когда `tick()` пора вызвать снова. `nil` — записей нет.
    public var nextRepeat: Date? {
        guard let next = recordings.values.map(\.next).min() else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(next) / 1000)
    }

    private mutating func attempt(_ kind: TypingKind, chatId: String, postId: String?, at: Int64) -> [TypingFrame] {
        if let last = lastSent[chatId], at - last < Self.millis(Self.throttle) { return [] }
        lastSent[chatId] = at
        return [TypingFrame(chatId: chatId, type: kind.rawValue, postId: postId)]
    }

    private func now() -> Int64 {
        Self.millis(clock().timeIntervalSince1970)
    }

    private static func millis(_ seconds: TimeInterval) -> Int64 {
        Int64((seconds * 1000).rounded())
    }
}

/// Отправляет кадры `TypingSendPolicy` через `TypingSender` и сам делает повторы во время
/// записи. Отправитель подключается, когда мост ядра отдаст `sendTyping`: до этого стоит
/// `SilentTypingSender`, и экраны этот объект не вызывают.
@MainActor
public final class TypingReporter {
    private var policy: TypingSendPolicy
    private let sender: any TypingSender
    private let clock: @Sendable () -> Date
    private var repeats: Task<Void, Never>?

    public init(sender: any TypingSender = SilentTypingSender(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.sender = sender
        self.clock = clock
        self.policy = TypingSendPolicy(clock: clock)
    }

    public func textEdited(chatId: String, postId: String? = nil, canWrite: Bool = true) {
        send(policy.textEdited(chatId: chatId, postId: postId, canWrite: canWrite))
    }

    public func uploadProgress(_ kind: TypingKind, chatId: String, postId: String? = nil, canWrite: Bool = true) {
        send(policy.uploadProgress(kind, chatId: chatId, postId: postId, canWrite: canWrite))
    }

    public func stickerPanelOpened(chatId: String, postId: String? = nil, canWrite: Bool = true) {
        send(policy.stickerPanelOpened(chatId: chatId, postId: postId, canWrite: canWrite))
    }

    public func recordingStarted(_ kind: TypingKind, chatId: String, postId: String? = nil, canWrite: Bool = true) {
        send(policy.recordingStarted(kind, chatId: chatId, postId: postId, canWrite: canWrite))
        scheduleRepeats()
    }

    public func recordingStopped(chatId: String) {
        policy.recordingStopped(chatId: chatId)
        if policy.nextRepeat == nil {
            repeats?.cancel()
            repeats = nil
        }
    }

    /// Уход с экрана: повторы прекращаются.
    public func stop() {
        repeats?.cancel()
        repeats = nil
    }

    private func scheduleRepeats() {
        guard repeats == nil, policy.nextRepeat != nil else { return }
        repeats = Task { [weak self] in
            while !Task.isCancelled {
                // Пока ждём, объект не удерживается: ушли с экрана — повторы кончаются.
                guard let delay = self?.repeatDelay() else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let reporter = self else { return }
                reporter.send(reporter.policy.tick())
            }
        }
    }

    /// Сколько ждать до следующего повтора. `nil` — записей нет.
    private func repeatDelay() -> TimeInterval? {
        guard let next = policy.nextRepeat else {
            repeats = nil
            return nil
        }
        return max(0, next.timeIntervalSince(clock()))
    }

    private func send(_ frames: [TypingFrame]) {
        guard !frames.isEmpty else { return }
        let sender = sender
        Task {
            for frame in frames {
                try? await sender.sendTyping(chatId: frame.chatId, type: frame.type, postId: frame.postId)
            }
        }
    }
}
