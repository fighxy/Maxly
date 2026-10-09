import Foundation
import OrbitleDomain

/// Правила содержимого пузыря, независимые от SwiftUI. У сообщения одно место для
/// времени и статуса, даже если сервер прислал несколько разных видов вложений.
public struct MessageBubbleLayout: Equatable, Sendable {
    public enum Standalone: Equatable, Sendable {
        case sticker(StickerContent)
        case emoji([String], lottie: URL?)
    }

    public enum Metadata: Equatable, Sendable {
        case standalone
        case media
        case voice(String)
        case call(String)
        case text
        case reactions
        case footer
    }

    public let standalone: Standalone?
    public let hasText: Bool
    public let hasHeader: Bool
    public let hasFill: Bool
    public let reactionsInside: Bool
    public let metadata: Metadata

    public init(message: Message, showsAuthorName: Bool = false, showsComments: Bool = false) {
        let content = message.content
        hasText = !message.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.sticker == nil
        hasHeader = (showsAuthorName && !message.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || content.reply != nil || content.forward != nil

        if let sticker = content.sticker {
            standalone = .sticker(sticker)
        } else if content.attachments.isEmpty, content.reply == nil, content.forward == nil,
                  content.linkPreview == nil, content.keyboard == nil, !showsComments,
                  (content.formatting ?? []).allSatisfy({ $0.kind == .animoji }),
                  let emoji = ChatContentFormat.bigEmoji(message.displayText) {
            let lottie = emoji.count == 1
                ? (content.formatting ?? []).first { $0.kind == .animoji }?.url.flatMap(URL.init(string:))
                : nil
            standalone = .emoji(emoji, lottie: lottie)
        } else {
            standalone = nil
        }

        hasFill = hasText || hasHeader || content.visuals.isEmpty || showsComments
            || !content.voices.isEmpty || !content.files.isEmpty || !content.contacts.isEmpty
            || !content.calls.isEmpty || content.poll != nil || content.linkPreview != nil || content.edited == true
        reactionsInside = standalone == nil && hasFill && !content.reactions.isEmpty

        // Порядок соответствует блокам пузыря: медиа, голосовые, файлы, контакты,
        // опрос, звонки, подпись, превью ссылки, реакции, комментарии.
        if standalone != nil {
            metadata = .standalone
        } else if reactionsInside {
            metadata = .reactions
        } else if content.linkPreview != nil {
            metadata = .footer
        } else if hasText {
            metadata = .text
        } else if let call = content.calls.last {
            metadata = .call(call.id)
        } else if content.poll != nil || !content.files.isEmpty || !content.contacts.isEmpty {
            metadata = .footer
        } else if let voice = content.voices.last {
            metadata = .voice(voice.id)
        } else if !content.visuals.isEmpty {
            // Подпись «изм.» должна оставаться видна и у медиа без текста.
            metadata = content.edited == true ? .footer : .media
        } else {
            metadata = .footer
        }
    }
}
