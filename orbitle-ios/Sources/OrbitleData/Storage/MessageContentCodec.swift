import Foundation
import OrbitleDomain

/// Переводит JSON фасада и каноническую запись базы в `MessageContent`.
enum MessageContentCodec {
    static func decode(_ json: String) -> MessageContent {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return .empty }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .empty }
        // Каноническая запись базы всегда несёт `attachments` и `reactions`, фрагмент сервера —
        // никогда. Проверка первой: иначе ключ `edited` правленого сообщения уводил запись базы
        // в разбор сервера, и вложения, цитата и реакции терялись.
        if object["attachments"] != nil, object["reactions"] != nil,
           let content = try? JSONDecoder().decode(MessageContent.self, from: data) {
            return content
        }
        if object["attaches"] != nil || object["reactionInfo"] != nil || object["link"] != nil
            || object["commentsCount"] != nil || object["commentsInfo"] != nil || object["elements"] != nil || object["edited"] != nil {
            return decodeServer(object)
        }
        return (try? JSONDecoder().decode(MessageContent.self, from: data)) ?? .empty
    }

    static func encode(_ content: MessageContent) -> String {
        guard !content.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(content), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    private static func decodeServer(_ object: [String: Any]) -> MessageContent {
        let forwarded = forward(object["link"])
        var attaches = attachments(object["attaches"])
        var elements = spans(object["elements"])
        // У пересылки свои вложения и разметка пустые: берутся из оригинала.
        if let original = forwarded?.message {
            if attaches.isEmpty { attaches = attachments(original["attaches"]) }
            if elements.isEmpty { elements = spans(original["elements"]) }
        }
        return MessageContent(
            reply: reply(object["link"]),
            attachments: attaches,
            reactions: reactions(object["reactionInfo"]),
            comments: comments(object),
            threadOf: nil,
            formatting: elements,
            forward: forwarded?.info,
            edited: (object["edited"] as? Bool) == true,
            pin: pinNotice(object["attaches"]),
            linkPreview: linkPreview(object["attaches"]),
            keyboard: keyboard(object["attaches"])
        )
    }

    /// Вложение `SHARE`: `{url, host?, title?, description?, image?: PHOTO}` (схема Komet).
    static func linkPreview(_ value: Any?) -> LinkPreview? {
        guard let list = value as? [Any] else { return nil }
        for case let map as [String: Any] in list {
            let type = ((map["_type"] as? String) ?? (map["type"] as? String))?.uppercased()
            guard type == "SHARE" else { continue }
            let image = map["image"] as? [String: Any]
            let text: (String) -> String? = { key in
                (map[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            guard let address = text("url") else { continue }
            return LinkPreview(
                url: address,
                host: text("host"),
                title: text("title"),
                summary: text("description"),
                imageURL: image.flatMap { url($0["baseUrl"]) ?? url($0["url"]) },
                imageWidth: image.flatMap { integer($0["width"]) },
                imageHeight: image.flatMap { integer($0["height"]) }
            )
        }
        return nil
    }

    /// Вложение `INLINE_KEYBOARD`: `{callbackId, keyboard: {buttons: [[{type, text, url?, webApp?,
    /// contactId?, payload?}]]}}` (схема Komet). Кнопки без подписи и пустые ряды отбрасываются.
    static func keyboard(_ value: Any?) -> InlineKeyboard? {
        guard let list = value as? [Any] else { return nil }
        for case let map as [String: Any] in list {
            let type = ((map["_type"] as? String) ?? (map["type"] as? String))?.uppercased()
            guard type == "INLINE_KEYBOARD" else { continue }
            let buttons = (map["keyboard"] as? [String: Any])?["buttons"] as? [Any] ?? []
            let rows: [[InlineButton]] = buttons.compactMap { row in
                let items = (row as? [Any] ?? []).compactMap { item -> InlineButton? in
                    guard let b = item as? [String: Any] else { return nil }
                    let title = (b["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !title.isEmpty else { return nil }
                    return InlineButton(
                        type: (b["type"] as? String) ?? "",
                        text: title,
                        url: (b["url"] as? String)?.nilIfEmpty,
                        webApp: (b["webApp"] as? String)?.nilIfEmpty,
                        contactId: stringId(b["contactId"]),
                        payload: (b["payload"] as? String) ?? stringId(b["payload"])
                    )
                }
                return items.isEmpty ? nil : items
            }
            guard !rows.isEmpty else { continue }
            return InlineKeyboard(callbackId: stringId(map["callbackId"]), rows: rows)
        }
        return nil
    }

    /// Ссылка `FORWARD`: автор (имя подставляет ядро) и текст оригинала.
    private static func forward(_ value: Any?) -> (info: MessageForward, message: [String: Any])? {
        guard let link = value as? [String: Any], (link["type"] as? String)?.uppercased() == "FORWARD" else { return nil }
        let message = link["message"] as? [String: Any] ?? [:]
        let name = (message["senderName"] as? String) ?? (link["chatName"] as? String) ?? (link["senderName"] as? String) ?? ""
        let text = message["text"] as? String ?? ""
        return (MessageForward(authorName: name.isEmpty ? "Неизвестно" : name, text: text), message)
    }

    /// `elements` сервера: `{type, from, length, attributes?, entityId?}`. Незнакомые типы пропускаются.
    static func spans(_ value: Any?) -> [TextSpan] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { item in
            guard let map = item as? [String: Any] else { return nil }
            let kind: TextSpan.Kind
            switch (map["type"] as? String)?.uppercased() {
            case "STRONG": kind = .strong
            case "EMPHASIZED": kind = .emphasized
            case "UNDERLINE": kind = .underline
            case "STRIKETHROUGH": kind = .strikethrough
            case "MONOSPACED", "CODE": kind = .monospaced
            case "HEADING": kind = .heading
            case "QUOTE": kind = .quote
            case "LINK": kind = .link
            case "USER_MENTION": kind = .mention
            case "ANIMOJI": kind = .animoji
            default: return nil
            }
            guard let from = integer(map["from"]), let length = integer(map["length"]), from >= 0, length > 0 else { return nil }
            let attributes = map["attributes"] as? [String: Any]
            if kind == .animoji {
                // Анимодзи поверх эмодзи текста: id и его Lottie (KometTeam/Komet `RichMessageController`).
                // Без id отметка ничего не даёт и пропускается.
                guard stringId(map["entityId"]) != nil else { return nil }
                return TextSpan(
                    kind: .animoji, from: from, length: length,
                    url: (attributes?["animojiLottieUrl"] as? String) ?? (attributes?["lottieUrl"] as? String),
                    entityId: stringId(map["entityId"])
                )
            }
            return TextSpan(
                kind: kind,
                from: from,
                length: length,
                url: attributes?["url"] as? String,
                userId: stringId(map["entityId"]) ?? stringId(attributes?["userId"])
            )
        }
    }

    private static func reply(_ value: Any?) -> MessageReply? {
        guard let link = value as? [String: Any] else { return nil }
        let kind = (link["type"] as? String)?.uppercased()
        if let kind, kind != "REPLY" { return nil }
        let message = link["message"] as? [String: Any]
        let id = stringId(link["messageId"]) ?? stringId(message?["id"]) ?? ""
        guard !id.isEmpty else { return nil }
        let text = (message?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let attaches = attachments(message?["attaches"])
        let preview = text.isEmpty ? preview(of: attaches) : text
        let name = (message?["senderName"] as? String) ?? (link["senderName"] as? String) ?? ""
        return MessageReply(
            messageId: id,
            authorName: name.isEmpty ? "Сообщение" : name,
            preview: preview.isEmpty ? "Сообщение" : preview,
            kind: replyKind(text: text, attachments: attaches)
        )
    }

    private static func attachments(_ value: Any?) -> [ChatAttachment] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { item in
            guard let map = item as? [String: Any] else { return nil }
            return attachment(map)
        }
    }

    private static func attachment(_ map: [String: Any]) -> ChatAttachment? {
        let type = ((map["_type"] as? String) ?? (map["type"] as? String))?.uppercased()
        switch type {
        case "PHOTO":
            return .photo(PhotoContent(
                id: stringId(map["photoId"]) ?? stringId(map["photoToken"]) ?? stableId(map),
                url: url(map["baseUrl"]) ?? url(map["url"]) ?? url(map["fileUrl"]),
                width: integer(map["width"]),
                height: integer(map["height"]),
                localPath: map["localPath"] as? String,
                preview: preview(map["previewData"])
            ))
        case "VIDEO":
            let videoType = integer(map["videoType"]) ?? 0
            return .video(VideoContent(
                id: stringId(map["videoId"]) ?? stringId(map["token"]) ?? stableId(map),
                url: url(map["baseUrl"]) ?? url(map["url"]) ?? url(map["fileUrl"]),
                posterURL: url(map["thumbnail"]),
                width: integer(map["width"]),
                height: integer(map["height"]),
                durationMs: durationMs(map["duration"]),
                isRound: videoType == 1,
                localPath: map["localPath"] as? String,
                preview: preview(map["previewData"])
            ))
        case "AUDIO":
            return .voice(VoiceContent(
                id: stringId(map["audioId"]) ?? stringId(map["token"]) ?? stableId(map),
                url: url(map["url"]) ?? url(map["baseUrl"]) ?? url(map["fileUrl"]),
                waveform: wave(map["wave"] ?? map["waveform"]),
                durationMs: durationMs(map["duration"]),
                transcript: (map["transcription"] as? String) ?? (map["text"] as? String),
                localPath: map["localPath"] as? String
            ))
        case "FILE":
            let name = (map["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .file(FileContent(
                id: stringId(map["fileId"]) ?? stringId(map["fileToken"]) ?? stringId(map["token"]) ?? stableId(map),
                name: name.isEmpty ? "Файл" : name,
                size: int64(map["size"]) ?? 0,
                url: url(map["baseUrl"]) ?? url(map["url"]) ?? url(map["fileUrl"]),
                localPath: map["localPath"] as? String
            ))
        case "CONTACT":
            // Карточку дополняет сервер: имя целиком или по частям, номер числом или строкой.
            let full = (map["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = [map["firstName"] as? String, map["lastName"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let userId = stringId(map["contactId"]) ?? stringId(map["userId"]) ?? ""
            return .contact(ContactContent(
                id: userId.isEmpty ? stableId(map) : "contact-\(userId)",
                userId: userId,
                name: full.isEmpty ? parts : full,
                phone: stringId(map["phone"]) ?? stringId(map["phoneNumber"]) ?? "",
                avatarURL: url(map["photoUrl"]) ?? url(map["baseUrl"])
            ))
        case "STICKER":
            let stickerId = stringId(map["stickerId"]) ?? stringId(map["id"]) ?? stableId(map)
            return .sticker(StickerContent(
                id: stickerId,
                stickerId: stickerId,
                url: url(map["url"]) ?? url(map["baseUrl"]),
                lottieURL: url(map["lottieUrl"]),
                width: integer(map["width"]),
                height: integer(map["height"])
            ))
        case "CALL":
            return .call(callContent(map))
        case "POLL":
            return poll(map).map(ChatAttachment.poll)
        default:
            return nil
        }
    }

    /// Опрос: без `pollId` или меньше чем с двумя ответами вложение пропускается.
    private static func poll(_ map: [String: Any]) -> PollContent? {
        guard let id = stringId(map["pollId"]) else { return nil }
        let state = map["state"] as? [String: Any]
        let results = (state?["result"] as? [Any]) ?? []
        let answers = ((map["answers"] as? [Any]) ?? []).compactMap { item -> PollAnswer? in
            guard let answer = item as? [String: Any], let answerId = stringId(answer["answerId"]) else { return nil }
            let text = (answer["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            let votes = results.compactMap { $0 as? [String: Any] }
                .first { stringId($0["answerId"]) == answerId }
                .flatMap { integer($0["voteCount"]) } ?? 0
            return PollAnswer(id: answerId, text: text, votes: votes)
        }
        guard answers.count >= 2 else { return nil }
        let total = integer(state?["total"]) ?? answers.reduce(0) { $0 + $1.votes }
        let title = (map["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return PollContent(id: id, title: title.isEmpty ? "Опрос" : title, answers: answers, total: total)
    }

    /// `CONTROL` `pin` / `unpin`. Текст берётся из `pinnedMessage.text`.
    private static func pinNotice(_ value: Any?) -> PinNotice? {
        guard let list = value as? [Any] else { return nil }
        for item in list {
            guard let map = item as? [String: Any] else { continue }
            let type = ((map["_type"] as? String) ?? (map["type"] as? String))?.uppercased()
            guard type == "CONTROL" else { continue }
            switch (map["event"] as? String)?.lowercased() {
            case "unpin":
                return PinNotice(messageId: nil, preview: "")
            case "pin":
                guard let pinned = map["pinnedMessage"] as? [String: Any] else { return PinNotice(messageId: nil, preview: "") }
                guard let id = stringId(pinned["id"]) else { return nil }
                let text = (pinned["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return PinNotice(messageId: id, preview: text.isEmpty ? "Сообщение" : text)
            default:
                continue
            }
        }
        return nil
    }

    /// Звонок: `duration` в миллисекундах, `callType` AUDIO или VIDEO, `hangupType` HUNGUP,
    /// CANCELED, REJECTED или MISSED; у группового есть `joinLink`. id вложения постоянный:
    /// пузырь не пересоздаётся при каждом разборе.
    private static func callContent(_ map: [String: Any]) -> CallContent {
        let conversation = stringId(map["conversationId"])
        let link = (map["joinLink"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let contacts = (map["contactIds"] as? [Any] ?? []).compactMap { stringId($0) }
        return CallContent(
            id: "call-\(conversation ?? "message")",
            durationMs: durationMs(map["duration"]),
            callType: (map["callType"] as? String)?.uppercased() == CallContent.CallType.video.rawValue ? .video : .audio,
            hangupType: (map["hangupType"] as? String) ?? "",
            conversationId: conversation,
            contactIds: contacts,
            joinLink: link
        )
    }

    /// `reactionsJSON` ядра: `{counters:[{reaction, count}], totalCount, yourReaction}`.
    /// `nil` для пустой строки и мусора: такие реакции источник не прислал. Без ключа
    /// `yourReaction` своя реакция неизвестна, `null` в нём — своей нет.
    static func reactionUpdate(_ json: String) -> ReactionUpdate? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let counters = (info["counters"] as? [Any] ?? []).compactMap { item -> ReactionUpdate.Counter? in
            guard let counter = item as? [String: Any], let emoji = counter["reaction"] as? String, !emoji.isEmpty else { return nil }
            return ReactionUpdate.Counter(emoji: emoji, count: max(0, integer(counter["count"]) ?? 0))
        }
        let known = info.keys.contains("yourReaction")
        let mine = (info["yourReaction"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ReactionUpdate(counters: counters, mine: mine, mineKnown: known)
    }

    private static func reactions(_ value: Any?) -> [MessageReaction] {
        guard let info = value as? [String: Any] else { return [] }
        let yours = info["yourReaction"] as? String
        let counters = info["counters"] as? [Any] ?? []
        return counters.compactMap { item in
            guard let counter = item as? [String: Any] else { return nil }
            let emoji = counter["reaction"] as? String ?? ""
            guard !emoji.isEmpty else { return nil }
            return MessageReaction(emoji: emoji, count: max(0, integer(counter["count"]) ?? 0), mine: emoji == yours)
        }.filter { $0.count > 0 }
    }

    private static func comments(_ object: [String: Any]) -> CommentSummary? {
        if let count = integer(object["commentsCount"]) {
            return CommentSummary(count: max(0, count))
        }
        if let info = object["commentsInfo"] as? [String: Any], let count = integer(info["totalCount"]) {
            return CommentSummary(count: max(0, count))
        }
        return nil
    }

    private static func preview(of attachments: [ChatAttachment]) -> String {
        if attachments.contains(where: { $0.voice != nil }) { return "Голосовое сообщение" }
        if attachments.contains(where: { $0.video != nil }) { return "Видео" }
        if attachments.contains(where: { $0.photo != nil }) { return "Фото" }
        if let file = attachments.compactMap(\.file).first {
            let name = file.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Файл" : name
        }
        if attachments.contains(where: { $0.contact != nil }) { return "Контакт" }
        if attachments.contains(where: { $0.sticker != nil }) { return "Стикер" }
        if let call = attachments.compactMap(\.call).first { return call.isGroup ? "Групповой звонок" : "Звонок" }
        return ""
    }

    private static func replyKind(text: String, attachments: [ChatAttachment]) -> MessageReply.Kind {
        if !text.isEmpty { return .text }
        if attachments.contains(where: { $0.voice != nil }) { return .voice }
        if attachments.contains(where: { $0.video != nil }) { return .video }
        if attachments.contains(where: { $0.photo != nil }) { return .photo }
        if attachments.contains(where: { $0.file != nil }) { return .file }
        return .text
    }

    /// `previewData`: байты картинки массивом или строкой base64 (в том числе `data:`-адресом).
    private static func preview(_ value: Any?) -> Data? {
        if let list = value as? [Any] {
            let bytes = list.compactMap { integer($0) }.map { UInt8(truncatingIfNeeded: $0) }
            return bytes.isEmpty ? nil : Data(bytes)
        }
        guard var text = value as? String, !text.isEmpty else { return nil }
        if text.hasPrefix("data:"), let comma = text.firstIndex(of: ",") {
            text = String(text[text.index(after: comma)...])
        }
        return Data(base64Encoded: text)
    }

    private static func wave(_ value: Any?) -> [Int] {
        if let list = value as? [Int] { return list }
        if let list = value as? [Any] {
            return list.compactMap { integer($0) }
        }
        guard let text = value as? String, !text.isEmpty else { return [] }
        if let data = Data(base64Encoded: text), data.count >= 8 {
            return data.map(Int.init)
        }
        return text.unicodeScalars.map { Int($0.value) & 0xFF }
    }

    /// Длительность приходит сырыми миллисекундами. Секунды из неё не выводим.
    private static func durationMs(_ value: Any?) -> Int64 {
        guard let number = integer(value) else { return 0 }
        return Int64(max(0, number))
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text)
        default:
            return nil
        }
    }

    private static func stringId(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = value as? Int { return String(number) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func url(_ value: Any?) -> URL? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return URL(string: text)
    }

    private static func stableId(_ map: [String: Any]) -> String {
        if let text = (map["baseUrl"] as? String) ?? (map["url"] as? String) ?? (map["fileUrl"] as? String), !text.isEmpty {
            return text
        }
        return UUID().uuidString
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
