import Foundation
import Observation
import MaxlyDomain

/// Расшифровка голосовых открытого чата: какие раскрыты, какие ждут текста, какие не удались.
/// Ошибка показывается в самом пузыре, а не над полем ввода.
@MainActor
@Observable
public final class TranscriptionModel {
    /// Голосовые (id вложения), чья расшифровка идёт: текст ещё не пришёл.
    public private(set) var transcribing: Set<String> = []
    /// Голосовые, у которых расшифровка раскрыта.
    public private(set) var open: Set<String> = []
    /// Голосовые, чья расшифровка не удалась: ошибка раскрыта в пузыре до нажатия «^».
    public private(set) var failed: Set<String> = []
    @ObservationIgnored private let repository: any MessageRepository
    /// Столько ждём пуша с текстом, если сервер ответил «ещё расшифровываю».
    static let wait: Duration = .seconds(60)

    public init(repository: any MessageRepository) {
        self.repository = repository
    }

    /// Расшифровать можно голосовое, уже принятое сервером.
    public func canTranscribe(_ message: Message) -> Bool {
        guard let voice = message.content.voices.first else { return false }
        if voice.transcript != nil { return true }
        return message.status == .sent && message.serverId.flatMap { Int64($0) } != nil && Int64(voice.id) != nil
    }

    public func phase(for voice: VoiceContent) -> TranscriptPhase {
        if transcribing.contains(voice.id) { return .loading }
        if failed.contains(voice.id) { return .failed }
        if open.contains(voice.id), voice.transcript != nil { return .expanded }
        return .collapsed
    }

    /// «→T»: раскрыть расшифровку (запросив её у сервера, если её ещё нет) или свернуть.
    public func toggle(_ message: Message) {
        guard let voice = message.content.voices.first, !transcribing.contains(voice.id) else { return }
        // «^» у ошибки сворачивает её; следующее «→Т» спросит сервер заново.
        if failed.remove(voice.id) != nil { return }
        if open.contains(voice.id) {
            open.remove(voice.id)
            return
        }
        if voice.transcript != nil {
            open.insert(voice.id)
            return
        }
        guard canTranscribe(message) else { return }
        let id = voice.id
        transcribing.insert(id)
        Task { [weak self] in
            guard let self else { return }
            do {
                let ready = try await self.repository.transcribe(messageId: message.id, attachmentId: id)
                if ready {
                    // Текст уже в базе; снимок ленты с ним мог прийти раньше ответа.
                    if self.transcribing.remove(id) != nil { self.open.insert(id) }
                    return
                }
                // Сервер ещё работает: текст придёт пушем (`settle`).
                try? await Task.sleep(for: Self.wait)
                if self.transcribing.remove(id) != nil { self.failed.insert(id) }
            } catch {
                self.transcribing.remove(id)
                if (error as? MaxlyError) != .cancelled { self.failed.insert(id) }
            }
        }
    }

    /// Пришёл текст голосового, чья расшифровка шла: она раскрывается.
    func settle(in messages: [Message]) {
        guard !transcribing.isEmpty else { return }
        for message in messages {
            for voice in message.content.voices where voice.transcript != nil && transcribing.contains(voice.id) {
                transcribing.remove(voice.id)
                open.insert(voice.id)
            }
        }
    }
}
