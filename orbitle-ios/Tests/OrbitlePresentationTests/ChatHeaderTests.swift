import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Шапка чата")
struct ChatHeaderTests {
    @Test("Собеседник в сети — «в сети» цветом акцента, иначе статус со строчной")
    func presence() {
        #expect(ChatHeaderStatus.make(kind: .user, subtitle: "Был(а) недавно", isOnline: false, live: ChatHeaderLive(isOnline: true)) == .accent("в сети"))
        #expect(ChatHeaderStatus.make(kind: .user, subtitle: "Был(а) недавно", isOnline: false, live: ChatHeaderLive()) == .plain("был(а) недавно"))
    }

    @Test("«печатает» перекрывает статус, в группе — число печатающих, точки рисует экран")
    func typing() {
        #expect(ChatHeaderStatus.make(kind: .user, subtitle: "В сети", isOnline: true, live: ChatHeaderLive(typingCount: 1)) == .typing("печатает"))
        let group = ChatHeaderStatus.make(kind: .group, subtitle: "5 участников", isOnline: false, live: ChatHeaderLive(typingCount: 3))
        guard case .typing(let text) = group else { Issue.record("ожидалось «печатают»"); return }
        #expect(!text.hasSuffix("…"))
        #expect(text.contains("3"))
    }

    @Test("Канал — подписчики, «Избранное» — без строки")
    func channelAndSaved() {
        #expect(ChatHeaderStatus.make(kind: .channel, subtitle: "12 подписчиков", isOnline: false, live: ChatHeaderLive(typingCount: 2)) == .plain("12 подписчиков"))
        #expect(ChatHeaderStatus.make(kind: .saved, subtitle: "заметки", isOnline: false, live: ChatHeaderLive()) == .none)
    }
}

@Suite("Общие медиа профиля")
struct SharedMediaTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func message(_ id: String, text: String = "", attachments: [ChatAttachment] = [], at seconds: TimeInterval = 0, author: String = "2") -> Message {
        Message(
            id: id, chatId: "c", authorId: author, text: text,
            timestamp: Date(timeIntervalSince1970: 1_757_000_000 + seconds),
            status: .sent,
            content: MessageContent(attachments: attachments),
            authorName: "Анна"
        )
    }

    @Test("Вкладки по типам, новые первыми, пустые не показываются")
    func tabs() {
        let messages = [
            message("1", attachments: [.photo(PhotoContent(id: "p1", url: URL(string: "https://x/1.jpg")))]),
            message("2", attachments: [.photo(PhotoContent(id: "p2", url: URL(string: "https://x/2.jpg")))], at: 60),
            message("3", attachments: [.file(FileContent(id: "f1", name: "отчёт.pdf", size: 2048))], at: 120),
        ]
        let shared = SharedMedia.collect(messages, calendar: calendar, now: Date(timeIntervalSince1970: 1_757_000_000))
        #expect(shared.tabs == [.media, .files])
        #expect(shared.media.map(\.attachmentId) == ["p2", "p1"])
        #expect(shared.files.first?.ext == "PDF")
    }

    @Test("Ссылки из текста и разметки без повторов, своё голосовое — «Вы»")
    func linksAndVoice() {
        let messages = [
            message("1", text: "Смотри https://github.com/fighxy и https://github.com/fighxy"),
            message("2", attachments: [.voice(VoiceContent(id: "v1", url: nil, waveform: [], durationMs: 42_000))], author: "me"),
        ]
        let shared = SharedMedia.collect(messages, currentUserId: "me", calendar: calendar, now: Date(timeIntervalSince1970: 1_757_000_000))
        #expect(shared.links.count == 1)
        #expect(shared.links.first?.host == "github.com")
        #expect(shared.links.first?.letter == "G")
        #expect(shared.voices.first?.author == "Вы")
        #expect(shared.voices.first?.details.hasSuffix("0:42") == true)
    }
}
