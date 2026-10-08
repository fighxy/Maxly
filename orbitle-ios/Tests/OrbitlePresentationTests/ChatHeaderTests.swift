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

    @Test("«печатает» перекрывает статус, в группе — имена или число печатающих, точки рисует экран")
    func typing() {
        let one = [TypingFormatter.Participant(name: "Иван")]
        #expect(ChatHeaderStatus.make(kind: .user, subtitle: "В сети", isOnline: true, live: ChatHeaderLive(typing: one)) == .typing("печатает"))
        let unnamed = Array(repeating: TypingFormatter.Participant(), count: 3)
        let group = ChatHeaderStatus.make(kind: .group, subtitle: "5 участников", isOnline: false, live: ChatHeaderLive(typing: unnamed))
        guard case .typing(let text) = group else { Issue.record("ожидалось «печатают»"); return }
        #expect(!text.hasSuffix("…"))
        #expect(text.contains("3"))
        let named = [TypingFormatter.Participant(name: "Иван", type: "STICKER"), TypingFormatter.Participant(name: "Петя", type: "STICKER")]
        #expect(ChatHeaderStatus.make(kind: .group, subtitle: "5 участников", isOnline: false, live: ChatHeaderLive(typing: named)) == .typing("Иван и Петя выбирают стикер"))
        #expect(ChatHeaderStatus.make(kind: .bot, subtitle: "бот", isOnline: false, live: ChatHeaderLive(typing: named)) == .typing("выбирает стикер"))
    }

    @Test("Канал — подписчики, «Избранное» — без строки")
    func channelAndSaved() {
        #expect(ChatHeaderStatus.make(kind: .channel, subtitle: "12 подписчиков", isOnline: false, live: ChatHeaderLive(typing: [TypingFormatter.Participant(name: "Иван")])) == .plain("12 подписчиков"))
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

    @Test("Видео в сетке — по обложке; свой ролик без обложки отдаёт файл для кадра, кружков нет")
    func videos() {
        let messages = [
            message("1", attachments: [.video(VideoContent(id: "v1", url: URL(string: "https://x/v.mp4"), posterURL: URL(string: "https://x/p.jpg"), durationMs: 5_000))]),
            message("2", attachments: [.video(VideoContent(id: "v2", url: nil, durationMs: 3_000, localPath: "/tmp/own.mp4"))], at: 60),
            message("3", attachments: [.video(VideoContent(id: "v3", url: nil, durationMs: 2_000, isRound: true))], at: 120),
        ]
        let shared = SharedMedia.collect(messages, calendar: calendar, now: Date(timeIntervalSince1970: 1_757_000_000))
        #expect(shared.media.map(\.attachmentId) == ["v2", "v1"])
        #expect(shared.media[0].thumbnailURL == nil)
        #expect(shared.media[0].videoFile == URL(fileURLWithPath: "/tmp/own.mp4"))
        #expect(shared.media[1].thumbnailURL == URL(string: "https://x/p.jpg"))
        #expect(shared.media[1].videoFile == nil)
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

private struct CachedProfiles: ChatProfileRepository {
    let cached: ChatProfile
    func profile(chatId: String) async throws(OrbitleError) -> ChatProfile { throw .networkUnavailable }
    func cachedProfile(chatId: String) async -> ChatProfile? { cached }
}

@Suite("Профиль из кэша")
@MainActor
struct ChatProfileCacheTests {
    @Test("Без сети профиль показывает сохранённую карточку, а не ошибку")
    func offline() async {
        let card = ChatProfile(kind: .group, chatId: "7", title: "Семья", participants: 4)
        let model = ChatProfileViewModel(chatId: "7", title: "Семья", repository: CachedProfiles(cached: card))
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.subtitle == "4 участника")
    }

    @Test("Общие медиа берут историю из кэша и окно чата без повторов")
    func sharedFromHistory() async {
        let model = ChatProfileViewModel(chatId: "7", title: "Семья", repository: CachedProfiles(cached: ChatProfile(kind: .group, chatId: "7", title: "Семья")))
        func photo(_ id: String, _ seconds: TimeInterval) -> Message {
            Message(
                id: id, chatId: "7", authorId: "2", text: "",
                timestamp: Date(timeIntervalSince1970: seconds), status: .sent,
                content: MessageContent(attachments: [.photo(PhotoContent(id: "p" + id, url: URL(string: "https://x/\(id).jpg")))])
            )
        }
        let window = [photo("3", 300), photo("4", 400)]
        await model.updateShared(window, currentUserId: "me") { [photo("1", 100), photo("2", 200), photo("3", 300)] }
        #expect(model.shared.media.map(\.attachmentId) == ["p4", "p3", "p2", "p1"])
    }
}
