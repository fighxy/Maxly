import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Содержимое пузыря и единственное место для времени")
struct MessageBubbleLayoutTests {
    private let photo = ChatAttachment.photo(PhotoContent(id: "p", url: nil))
    private let voice = ChatAttachment.voice(VoiceContent(id: "v", url: nil))
    private let file = ChatAttachment.file(FileContent(id: "f", name: "Документ.pdf"))
    private let poll = ChatAttachment.poll(PollContent(id: "poll", title: "Вопрос?", answers: []))
    private let reaction = MessageReaction(emoji: "👍", count: 1, mine: false)

    private func layout(_ text: String = "", content: MessageContent = .empty, comments: Bool = false) -> MessageBubbleLayout {
        MessageBubbleLayout(message: Message(
            id: "1", chatId: "c", authorId: "me", text: text,
            timestamp: Date(timeIntervalSince1970: 0), status: .sent, content: content
        ), showsComments: comments)
    }

    @Test("Текст, фото и фото с подписью выбирают разные места времени")
    func textAndPhoto() {
        #expect(layout("Привет").metadata == .text)
        let media = layout(content: MessageContent(attachments: [photo]))
        #expect(!media.hasFill && media.metadata == .media)
        let caption = layout("Подпись", content: MessageContent(attachments: [photo]))
        #expect(caption.hasFill && caption.metadata == .text)
        let edited = layout(content: MessageContent(attachments: [photo], edited: true))
        #expect(edited.hasFill && edited.metadata == .footer)
    }

    @Test("У опроса, файла и смешанного медиа есть время внизу карточки")
    func attachmentFooter() {
        for attachments in [[poll], [file], [photo, file], [voice, file], [photo, poll]] {
            let result = layout(content: MessageContent(attachments: attachments))
            #expect(result.hasFill)
            #expect(result.metadata == .footer)
        }
    }

    @Test("Время после превью ссылки, а не между текстом и карточкой")
    func linkPreview() {
        let preview = LinkPreview(url: "https://example.com", title: "Сайт")
        #expect(layout("https://example.com", content: MessageContent(linkPreview: preview)).metadata == .footer)
        #expect(layout(content: MessageContent(linkPreview: preview)).metadata == .footer)
        let emojiWithLink = layout("👍", content: MessageContent(linkPreview: preview))
        #expect(emojiWithLink.standalone == nil)
        #expect(emojiWithLink.metadata == .footer)
    }

    @Test("Реакции забирают время из содержимого, кроме медиа без подложки")
    func reactions() {
        for attachments in [[photo], [voice], [poll], [file]] {
            let result = layout(content: MessageContent(attachments: attachments, reactions: [reaction]), comments: true)
            #expect(result.reactionsInside)
            #expect(result.metadata == .reactions)
        }
        let media = layout(content: MessageContent(attachments: [photo], reactions: [reaction]))
        #expect(!media.reactionsInside && media.metadata == .media)
        #expect(layout("Текст", content: MessageContent(reactions: [reaction])).metadata == .reactions)
    }

    @Test("Время только у последнего голосового или звонка; подпись забирает его себе")
    func voiceAndCall() {
        let secondVoice = ChatAttachment.voice(VoiceContent(id: "v2", url: nil))
        let call = ChatAttachment.call(CallContent(id: "call"))
        #expect(layout(content: MessageContent(attachments: [photo, voice])).metadata == .voice("v"))
        #expect(layout(content: MessageContent(attachments: [voice, secondVoice])).metadata == .voice("v2"))
        #expect(layout(content: MessageContent(attachments: [voice, call])).metadata == .call("call"))
        #expect(layout("Подпись", content: MessageContent(attachments: [voice, call])).metadata == .text)
    }

    @Test("Крупные эмодзи не скрывают форматирование, ответы и кнопки бота")
    func emojiContent() {
        #expect(layout("👍").standalone == .emoji(["👍"], lottie: nil))
        #expect(layout("👍", content: MessageContent(formatting: [TextSpan(kind: .strong, from: 0, length: 2)])).standalone == nil)
        #expect(layout("👍", content: MessageContent(forward: MessageForward(authorName: "Боб", text: "👍"))).standalone == nil)
        let reply = MessageReply(messageId: "0", authorName: "Боб", preview: "Привет", kind: .text)
        #expect(layout("👍", content: MessageContent(reply: reply)).standalone == nil)
        let keyboard = InlineKeyboard(callbackId: "k", rows: [[InlineButton(type: "CALLBACK", text: "Ответить")]])
        #expect(layout("👍", content: MessageContent(keyboard: keyboard)).standalone == nil)
        #expect(layout("👍", comments: true).standalone == nil)
    }

    @Test("Пересланный стикер сохраняет заголовок и отдельную плашку времени")
    func forwardedSticker() {
        let sticker = StickerContent(id: "s", stickerId: "s", url: nil)
        let result = layout(content: MessageContent(
            attachments: [.sticker(sticker)], forward: MessageForward(authorName: "Боб", text: "")
        ))
        #expect(result.standalone == .sticker(sticker))
        #expect(result.hasHeader)
        #expect(result.metadata == .standalone)
    }
}
