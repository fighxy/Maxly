import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Уведомления о новых сообщениях в фоне")
struct MessageNotificationRulesTests {
    private func notice(
        type: ChatType = .private,
        title: String = "Анна",
        author: String = "Анна",
        text: String = "Привет",
        media: MessageMediaKind? = nil,
        muted: Bool = false
    ) -> IncomingMessageNotice {
        IncomingMessageNotice(
            chatId: "1", messageId: "10", chatTitle: title, chatType: type,
            authorName: author, text: text, media: media, isMuted: muted
        )
    }

    @Test("На экране, при выключенной настройке и в чате без звука — не показываем")
    func suppressed() {
        #expect(MessageNotificationRules.content(for: notice(), appActive: true, enabled: true) == nil)
        #expect(MessageNotificationRules.content(for: notice(), appActive: false, enabled: false) == nil)
        #expect(MessageNotificationRules.content(for: notice(muted: true), appActive: false, enabled: true) == nil)
    }

    @Test("Личный чат: заголовок — собеседник, текст — сообщение")
    func privateChat() {
        let content = MessageNotificationRules.content(for: notice(), appActive: false, enabled: true)
        #expect(content == .init(title: "Анна", subtitle: nil, body: "Привет"))
    }

    @Test("Группа: заголовок — чат, подзаголовок — автор; вложение без текста — подпись")
    func group() {
        let content = MessageNotificationRules.content(
            for: notice(type: .group, title: "Семья", author: "Пётр", text: " ", media: .photo),
            appActive: false, enabled: true
        )
        #expect(content == .init(title: "Семья", subtitle: "Пётр", body: "Фото"))
    }

    @Test("Канал без названия и длинный текст")
    func channel() {
        let long = String(repeating: "а", count: 500)
        let content = MessageNotificationRules.content(
            for: notice(type: .channel, title: "", author: "", text: long),
            appActive: false, enabled: true
        )
        #expect(content?.title == MessageNotificationRules.untitledChat)
        #expect(content?.subtitle == nil)
        #expect(content?.body.count == MessageNotificationRules.bodyLimit)
    }
}
