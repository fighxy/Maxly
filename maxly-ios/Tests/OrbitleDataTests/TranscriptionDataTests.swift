import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

@Suite("Расшифровка голосовых: данные")
struct TranscriptionDataTests {
    private func voiceRecord(_ id: String, text: String = "", transcript: String? = nil) -> MessageRecord {
        let content = MessageContent(attachments: [.voice(VoiceContent(id: "900", url: URL(string: "https://cdn.invalid/v.ogg"), durationMs: 3000, transcript: transcript))])
        return MessageRecord(
            id: id, serverId: id, chatId: "c1", authorId: "bob", text: text,
            timestamp: Date(timeIntervalSince1970: 1), status: .sent,
            contentJSON: MessageContentCodec.encode(content)
        )
    }

    private func transcript(_ repository: MessageRepositoryImpl, _ id: String) async throws -> String? {
        let rows = try await repository.page(chatId: "c1", before: nil, limit: 10)
        return try #require(rows.first { $0.id == id }).domain.content.voices.first?.transcript
    }

    @Test("Готовый ответ: текст ложится в голосовое, запрос несёт чат, сообщение и audioId")
    func ready() async throws {
        let api = FakeMaxAPI()
        await api.setTranscription(.success(CoreTranscription(status: 1, text: "Привет")))
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([voiceRecord("501")])

        let ready = try await repository.transcribe(messageId: "501", attachmentId: "900")
        #expect(ready)
        #expect(await api.transcriptionCalls == ["c1:501:900"])
        #expect(try await transcript(repository, "501") == "Привет")
    }

    @Test("«Ещё расшифровываю»: текст приходит пушем, сверка историей его не стирает")
    func pending() async throws {
        let api = FakeMaxAPI()
        await api.setTranscription(.success(CoreTranscription(status: 0, text: "")))
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([voiceRecord("502")])

        #expect(try await repository.transcribe(messageId: "502", attachmentId: "900") == false)
        #expect(try await transcript(repository, "502") == nil)
        await repository.applyTranscription(chatId: "c1", messageId: "502", text: "Позже")
        #expect(try await transcript(repository, "502") == "Позже")

        try await repository.upsert([voiceRecord("502")])
        #expect(try await transcript(repository, "502") == "Позже")
    }

    @Test("Отказ сервера — понятная ошибка, текста нет")
    func refused() async throws {
        let api = FakeMaxAPI()
        await api.setTranscription(.success(CoreTranscription(status: -1, text: "")))
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([voiceRecord("503")])
        #expect(await failure { _ = try await repository.transcribe(messageId: "503", attachmentId: "900") } == .rejected("Не удалось расшифровать голосовое"))
        #expect(try await transcript(repository, "503") == nil)
    }
}
