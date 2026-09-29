import Foundation
import Testing
@testable import OrbitlDomain

@Suite("Ссылки")
struct DeepLinkTests {
    @Test("Чат, сообщение и профиль")
    func parses() {
        #expect(DeepLink.parse(URL(string: "orbitl://chat/abc")!) == .chat(id: "abc"))
        #expect(DeepLink.parse(URL(string: "ORBITL://chat/abc/message/m1")!) == .message(chatId: "abc", messageId: "m1"))
        #expect(DeepLink.parse(URL(string: "orbitl://user/u1")!) == .user(id: "u1"))
        #expect(DeepLink.parse(URL(string: "https://example.com/chat/abc")!) == nil)
        #expect(DeepLink.parse(URL(string: "orbitl://chat")!) == nil)
        #expect(DeepLink.parse(URL(string: "orbitl://other/abc")!) == nil)
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
struct OrbitlErrorTests {
    @Test("Текст отклонённого ввода показывается как есть")
    func rejectedText() {
        #expect(OrbitlError.rejected("Неверный пароль").errorDescription == "Неверный пароль")
        #expect(OrbitlError.networkUnavailable.errorDescription == "Нет соединения с сервером")
    }
}

@Suite("Ошибки для экрана")
struct OrbitlErrorMessageTests {
    @Test("Отмену экран не показывает, остальное показывает по-русски")
    func userMessage() {
        #expect(OrbitlError.cancelled.userMessage == nil)
        #expect(OrbitlError.authExpired.userMessage == "Сессия истекла, войдите снова")
        #expect(OrbitlError.server(code: "proto.bad").userMessage == "Ошибка сервера (proto.bad). Попробуйте позже")
        #expect(OrbitlError.unknown.userMessage == "Что-то пошло не так")
    }

    @Test("Временные ошибки отличаются от постоянных")
    func transient() {
        #expect(OrbitlError.networkUnavailable.isTransient)
        #expect(OrbitlError.server(code: "x").isTransient)
        #expect(!OrbitlError.rejected("Неверный код").isTransient)
        #expect(!OrbitlError.authExpired.isTransient)
        #expect(!OrbitlError.cancelled.isTransient)
    }
}
