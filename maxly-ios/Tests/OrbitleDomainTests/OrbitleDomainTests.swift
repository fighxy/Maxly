import Foundation
import Testing
@testable import OrbitleDomain

@Suite("Ссылки")
struct DeepLinkTests {
    @Test("Чат, сообщение и профиль")
    func parses() {
        #expect(DeepLink.parse(URL(string: "orbitle://chat/abc")!) == .chat(id: "abc"))
        #expect(DeepLink.parse(URL(string: "ORBITLE://chat/abc/message/m1")!) == .message(chatId: "abc", messageId: "m1"))
        #expect(DeepLink.parse(URL(string: "orbitle://user/u1")!) == .user(id: "u1"))
        #expect(DeepLink.parse(URL(string: "maxly://chat/abc")!) == .chat(id: "abc"))
        #expect(DeepLink.parse(URL(string: "MAXLY://chat/abc/message/m1")!) == .message(chatId: "abc", messageId: "m1"))
        #expect(DeepLink.parse(URL(string: "maxly://user/u1")!) == .user(id: "u1"))
        #expect(DeepLink.parse(URL(string: "https://chat/abc")!) == nil)
        #expect(DeepLink.parse(URL(string: "https://example.com/chat/abc")!) == nil)
        #expect(DeepLink.parse(URL(string: "orbitle://chat")!) == nil)
        #expect(DeepLink.parse(URL(string: "orbitle://other/abc")!) == nil)
    }
}

@Suite("Тип чата")
struct ChatTypeTests {
    @Test("Строки ядра")
    func fromCore() {
        #expect(ChatType.fromCore("DIALOG") == .private)
        #expect(ChatType.fromCore("private") == .private)
        #expect(ChatType.fromCore("CHANNEL") == .channel)
        #expect(ChatType.fromCore("CHAT") == .group)
        #expect(ChatType.fromCore("") == .group)
    }
}

@Suite("Ошибки")
struct OrbitleErrorTests {
    @Test("Текст отклонённого ввода показывается как есть")
    func rejectedText() {
        #expect(OrbitleError.rejected("Неверный пароль").errorDescription == "Неверный пароль")
        #expect(OrbitleError.networkUnavailable.errorDescription == "Нет соединения с сервером")
    }
}

@Suite("Ошибки для экрана")
struct OrbitleErrorMessageTests {
    @Test("Отмену экран не показывает, остальное показывает по-русски")
    func userMessage() {
        #expect(OrbitleError.cancelled.userMessage == nil)
        #expect(OrbitleError.authExpired.userMessage == "Сессия истекла, войдите снова")
        #expect(OrbitleError.server(code: "proto.bad", text: nil).userMessage == "Ошибка сервера (proto.bad). Попробуйте позже")
        #expect(OrbitleError.unknown.userMessage == "Что-то пошло не так")
    }

    @Test("Временные ошибки отличаются от постоянных")
    func transient() {
        #expect(OrbitleError.networkUnavailable.isTransient)
        #expect(OrbitleError.server(code: "x", text: nil).isTransient)
        #expect(!OrbitleError.rejected("Неверный код").isTransient)
        #expect(!OrbitleError.authExpired.isTransient)
        #expect(!OrbitleError.cancelled.isTransient)
    }
}
