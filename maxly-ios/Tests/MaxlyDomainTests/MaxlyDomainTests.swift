import Foundation
import Testing
@testable import MaxlyDomain

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
struct MaxlyErrorTests {
    @Test("Текст отклонённого ввода показывается как есть")
    func rejectedText() {
        #expect(MaxlyError.rejected("Неверный пароль").errorDescription == "Неверный пароль")
        #expect(MaxlyError.networkUnavailable.errorDescription == "Нет соединения с сервером")
    }
}

@Suite("Ошибки для экрана")
struct MaxlyErrorMessageTests {
    @Test("Отмену экран не показывает, остальное показывает по-русски")
    func userMessage() {
        #expect(MaxlyError.cancelled.userMessage == nil)
        #expect(MaxlyError.authExpired.userMessage == "Сессия истекла, войдите снова")
        #expect(MaxlyError.server(code: "proto.bad", text: nil).userMessage == "Ошибка сервера (proto.bad). Попробуйте позже")
        #expect(MaxlyError.unknown.userMessage == "Что-то пошло не так")
    }

    @Test("Временные ошибки отличаются от постоянных")
    func transient() {
        #expect(MaxlyError.networkUnavailable.isTransient)
        #expect(MaxlyError.server(code: "x", text: nil).isTransient)
        #expect(!MaxlyError.rejected("Неверный код").isTransient)
        #expect(!MaxlyError.authExpired.isTransient)
        #expect(!MaxlyError.cancelled.isTransient)
    }
}
