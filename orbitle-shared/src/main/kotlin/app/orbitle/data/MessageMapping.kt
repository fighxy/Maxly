package app.orbitle.data

import app.orbitle.domain.CallContent
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.ContactContent
import app.orbitle.domain.FileContent
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageForward
import app.orbitle.domain.MessageReaction
import app.orbitle.domain.MessageReply
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.PhotoContent
import app.orbitle.domain.PinNotice
import app.orbitle.domain.PollAnswer
import app.orbitle.domain.PollContent
import app.orbitle.domain.StickerContent
import app.orbitle.domain.TextSpan
import app.orbitle.domain.VideoContent
import app.orbitle.domain.VoiceContent
import com.max.core.api.MaxMessage
import com.max.core.state.MaxState
import java.util.Base64

/**
 * Сообщения ядра в моделях экрана. Разбор вложений, цитат, пересылок, реакций и разметки —
 * те же правила, что у iOS-клиента (`MessageContentCodec`), только прямо по картам ядра.
 */
object MessageMapping {

    fun message(message: MaxMessage, fallbackChatId: Long, state: MaxState, peerRead: Long = 0): Message {
        val sender = message.sender
        val user = sender?.let { state.users[it] }
        val outgoing = sender != null && sender == state.me
        val names: (Long) -> String? = { id -> state.users[id]?.displayName }
        val control = message.attaches.firstNotNullOfOrNull { (it as? Map<*, *>)?.takeIf { map -> map["_type"] == "CONTROL" } }
        return Message(
            id = message.id.toString(),
            chatId = (message.chatId ?: fallbackChatId).toString(),
            authorId = sender?.toString().orEmpty(),
            text = if (control != null && message.text.isBlank()) serviceText(control, user?.displayName, names) else message.text,
            timeMs = message.time,
            status = MessageStatus.SENT,
            content = content(message, names),
            authorName = user?.displayName.orEmpty(),
            authorAvatarUrl = user?.baseUrl?.takeIf { it.isNotBlank() },
            isRead = outgoing && peerRead > 0 && peerRead >= message.time,
            isService = control != null,
        )
    }

    /** Подпись служебного сообщения (`CONTROL`) по его `event`. */
    fun serviceText(control: Map<*, *>, actor: String?, names: (Long) -> String?): String {
        val who = actor?.takeIf { it.isNotBlank() }
        val targets = (control["userIds"] as? List<*>).orEmpty().mapNotNull { ChatMapping.longOf(it)?.let(names) }
        val whom = targets.joinToString(", ")
        val title = (control["title"] as? String)?.trim().orEmpty()
        return when ((control["event"] as? String)?.lowercase()) {
            "new" -> if (title.isNotEmpty()) "Создан чат «$title»" else "Чат создан"
            "add" -> listOfNotNull(who, "добавил(а)", whom.ifEmpty { "участников" }).joinToString(" ")
            "remove" -> listOfNotNull(who, "исключил(а)", whom.ifEmpty { "участника" }).joinToString(" ")
            "leave" -> listOfNotNull(who, "покинул(а) чат").joinToString(" ")
            "joinbylink" -> listOfNotNull(who, "присоединился(-ась) по ссылке").joinToString(" ")
            "title" -> if (title.isNotEmpty()) listOfNotNull(who, "изменил(а) название на «$title»").joinToString(" ") else "Название изменено"
            "icon" -> listOfNotNull(who, "изменил(а) фото чата").joinToString(" ")
            "pin" -> listOfNotNull(who, "закрепил(а) сообщение").joinToString(" ")
            else -> "Служебное сообщение"
        }.replaceFirstChar { it.uppercase() }
    }

    fun content(message: MaxMessage, names: (Long) -> String? = { null }): MessageContent {
        val body = (message.raw["message"] as? Map<*, *>) ?: message.raw
        val link = message.link
        val forwarded = forward(link, names)
        var attaches = attachments(message.attaches)
        var elements = spans(message.elements)
        // У пересылки свои вложения и разметка пустые: берутся из оригинала.
        forwarded?.second?.let { original ->
            if (attaches.isEmpty()) attaches = attachments(original["attaches"] as? List<*>)
            if (elements.isEmpty()) elements = spans(original["elements"] as? List<*>)
        }
        return MessageContent(
            reply = reply(link, names),
            attachments = attaches,
            reactions = reactions(message.reactionInfo?.raw),
            comments = comments(body),
            formatting = elements,
            forward = forwarded?.first,
            edited = message.status == "EDITED",
            pin = pinNotice(message.attaches),
        )
    }

    /** `CONTROL` `pin` / `unpin`. Текст берётся из `pinnedMessage.text`. */
    fun pinNotice(attaches: List<*>?): PinNotice? {
        val control = attaches.orEmpty().firstNotNullOfOrNull { item ->
            (item as? Map<*, *>)?.takeIf { it["_type"] == "CONTROL" }
        } ?: return null
        return when ((control["event"] as? String)?.lowercase()) {
            "unpin" -> PinNotice(null, "")
            "pin" -> {
                val pinned = control["pinnedMessage"] as? Map<*, *> ?: return PinNotice(null, "")
                val id = stringId(pinned["id"]) ?: return null
                val text = (pinned["text"] as? String)?.trim().orEmpty().ifEmpty { "Сообщение" }
                PinNotice(id, text)
            }
            else -> null
        }
    }

    /** Ссылка `FORWARD`: автор и текст оригинала. */
    private fun forward(link: Map<*, *>?, names: (Long) -> String?): Pair<MessageForward, Map<*, *>>? {
        link ?: return null
        if ((link["type"] as? String)?.uppercase() != "FORWARD") return null
        val message = link["message"] as? Map<*, *> ?: emptyMap<Any, Any>()
        val name = (message["senderName"] as? String)
            ?: ChatMapping.longOf(message["sender"])?.let(names)
            ?: (link["chatName"] as? String)
            ?: (link["senderName"] as? String)
            ?: ""
        val text = message["text"] as? String ?: ""
        return MessageForward(name.ifEmpty { "Неизвестно" }, text) to message
    }

    /** `elements` сервера: `{type, from, length, attributes?, entityId?}`. Незнакомые типы пропускаются. */
    fun spans(value: List<*>?): List<TextSpan> = value.orEmpty().mapNotNull { item ->
        val map = item as? Map<*, *> ?: return@mapNotNull null
        val kind = when ((map["type"] as? String)?.uppercase()) {
            "STRONG" -> TextSpan.Kind.STRONG
            "EMPHASIZED" -> TextSpan.Kind.EMPHASIZED
            "UNDERLINE" -> TextSpan.Kind.UNDERLINE
            "STRIKETHROUGH" -> TextSpan.Kind.STRIKETHROUGH
            "MONOSPACED", "CODE" -> TextSpan.Kind.MONOSPACED
            "HEADING" -> TextSpan.Kind.HEADING
            "QUOTE" -> TextSpan.Kind.QUOTE
            "LINK" -> TextSpan.Kind.LINK
            "USER_MENTION" -> TextSpan.Kind.MENTION
            "ANIMOJI" -> TextSpan.Kind.ANIMOJI
            else -> return@mapNotNull null
        }
        val from = integer(map["from"]) ?: return@mapNotNull null
        val length = integer(map["length"]) ?: return@mapNotNull null
        if (from < 0 || length <= 0) return@mapNotNull null
        val attributes = map["attributes"] as? Map<*, *>
        if (kind == TextSpan.Kind.ANIMOJI) {
            val entity = stringId(map["entityId"]) ?: return@mapNotNull null
            return@mapNotNull TextSpan(kind, from, length, url = (attributes?.get("animojiLottieUrl") ?: attributes?.get("lottieUrl")) as? String, entityId = entity)
        }
        TextSpan(kind, from, length, url = attributes?.get("url") as? String, userId = stringId(map["entityId"]) ?: stringId(attributes?.get("userId")))
    }

    private fun reply(link: Map<*, *>?, names: (Long) -> String?): MessageReply? {
        link ?: return null
        val kind = (link["type"] as? String)?.uppercase()
        if (kind != null && kind != "REPLY") return null
        val message = link["message"] as? Map<*, *>
        val id = stringId(link["messageId"]) ?: stringId(message?.get("id")) ?: return null
        val text = (message?.get("text") as? String)?.trim().orEmpty()
        val attaches = attachments(message?.get("attaches") as? List<*>)
        val preview = text.ifEmpty { previewOf(attaches) }
        val name = (message?.get("senderName") as? String)
            ?: ChatMapping.longOf(message?.get("sender"))?.let(names)
            ?: (link["senderName"] as? String)
            ?: ""
        return MessageReply(id, name.ifEmpty { "Сообщение" }, preview.ifEmpty { "Сообщение" }, replyKind(text, attaches))
    }

    fun attachments(value: List<*>?): List<ChatAttachment> = value.orEmpty().mapNotNull { (it as? Map<*, *>)?.let(::attachment) }

    fun attachment(map: Map<*, *>): ChatAttachment? {
        val type = ((map["_type"] as? String) ?: (map["type"] as? String))?.uppercase()
        return when (type) {
            "PHOTO" -> ChatAttachment.Photo(
                PhotoContent(
                    id = stringId(map["photoId"]) ?: stringId(map["photoToken"]) ?: stableId(map),
                    url = url(map["baseUrl"]) ?: url(map["url"]) ?: url(map["fileUrl"]),
                    width = integer(map["width"]),
                    height = integer(map["height"]),
                    preview = preview(map["previewData"]),
                ),
            )
            "VIDEO" -> ChatAttachment.Video(
                VideoContent(
                    id = stringId(map["videoId"]) ?: stringId(map["token"]) ?: stableId(map),
                    url = url(map["baseUrl"]) ?: url(map["url"]) ?: url(map["fileUrl"]),
                    posterUrl = url(map["thumbnail"]),
                    width = integer(map["width"]),
                    height = integer(map["height"]),
                    durationMs = durationMs(map["duration"]),
                    isRound = (integer(map["videoType"]) ?: 0) == 1,
                ),
            )
            "AUDIO" -> ChatAttachment.Voice(
                VoiceContent(
                    id = stringId(map["audioId"]) ?: stringId(map["token"]) ?: stableId(map),
                    url = url(map["url"]) ?: url(map["baseUrl"]) ?: url(map["fileUrl"]),
                    waveform = wave(map["wave"] ?: map["waveform"]),
                    durationMs = durationMs(map["duration"]),
                    transcript = (map["transcription"] as? String) ?: (map["text"] as? String),
                ),
            )
            "FILE" -> ChatAttachment.File(
                FileContent(
                    id = stringId(map["fileId"]) ?: stringId(map["fileToken"]) ?: stringId(map["token"]) ?: stableId(map),
                    name = (map["name"] as? String)?.trim().orEmpty().ifEmpty { "Файл" },
                    size = ChatMapping.longOf(map["size"]) ?: 0,
                    url = url(map["baseUrl"]) ?: url(map["url"]) ?: url(map["fileUrl"]),
                ),
            )
            "CONTACT" -> {
                // Карточку дополняет сервер: имя целиком или по частям, номер числом или строкой.
                val full = (map["name"] as? String)?.trim().orEmpty()
                val parts = listOf(map["firstName"] as? String, map["lastName"] as? String)
                    .mapNotNull { it?.trim() }.filter { it.isNotEmpty() }.joinToString(" ")
                val userId = stringId(map["contactId"]) ?: stringId(map["userId"]) ?: ""
                ChatAttachment.Contact(
                    ContactContent(
                        id = if (userId.isEmpty()) stableId(map) else "contact-$userId",
                        userId = userId,
                        name = full.ifEmpty { parts },
                        phone = stringId(map["phone"]) ?: stringId(map["phoneNumber"]) ?: "",
                        avatarUrl = url(map["photoUrl"]) ?: url(map["baseUrl"]),
                    ),
                )
            }
            "STICKER" -> {
                val stickerId = stringId(map["stickerId"]) ?: stringId(map["id"]) ?: stableId(map)
                ChatAttachment.Sticker(
                    StickerContent(
                        id = stickerId,
                        stickerId = stickerId,
                        url = url(map["url"]) ?: url(map["baseUrl"]),
                        lottieUrl = url(map["lottieUrl"]),
                        width = integer(map["width"]),
                        height = integer(map["height"]),
                    ),
                )
            }
            "CALL" -> ChatAttachment.Call(call(map))
            "POLL" -> poll(map)?.let(ChatAttachment::Poll)
            else -> null
        }
    }

    /** Опрос: без `pollId` голос отправить нечем, такое вложение пропускается. */
    fun poll(map: Map<*, *>): PollContent? {
        val id = stringId(map["pollId"]) ?: return null
        val answers = (map["answers"] as? List<*>).orEmpty().mapNotNull { item ->
            val answer = item as? Map<*, *> ?: return@mapNotNull null
            val answerId = stringId(answer["answerId"]) ?: return@mapNotNull null
            val text = (answer["text"] as? String)?.trim().orEmpty()
            if (text.isEmpty()) return@mapNotNull null
            val votes = (map["state"] as? Map<*, *>)?.let { state ->
                (state["result"] as? List<*>).orEmpty().firstNotNullOfOrNull { row ->
                    val result = row as? Map<*, *> ?: return@firstNotNullOfOrNull null
                    if (stringId(result["answerId"]) != answerId) return@firstNotNullOfOrNull null
                    integer(result["voteCount"])
                }
            } ?: 0
            PollAnswer(answerId, text, votes)
        }
        if (answers.size < 2) return null
        val total = integer((map["state"] as? Map<*, *>)?.get("total")) ?: answers.sumOf { it.votes }
        val title = (map["title"] as? String)?.trim().orEmpty().ifEmpty { "Опрос" }
        return PollContent(id, title, answers, total)
    }

    /** Звонок: id вложения постоянный, чтобы пузырь не пересоздавался при каждом разборе. */
    fun call(map: Map<*, *>): CallContent {
        val conversation = stringId(map["conversationId"])
        return CallContent(
            id = "call-${conversation ?: "message"}",
            durationMs = durationMs(map["duration"]),
            isVideo = (map["callType"] as? String)?.uppercase() == "VIDEO",
            hangupType = (map["hangupType"] as? String).orEmpty().uppercase(),
            conversationId = conversation?.takeIf { it.isNotEmpty() },
            contactIds = (map["contactIds"] as? List<*>).orEmpty().mapNotNull(::stringId),
            joinLink = (map["joinLink"] as? String)?.trim()?.takeIf { it.isNotEmpty() },
        )
    }

    fun reactions(info: Map<*, *>?): List<MessageReaction> {
        info ?: return emptyList()
        val yours = info["yourReaction"] as? String
        return (info["counters"] as? List<*>).orEmpty().mapNotNull { item ->
            val counter = item as? Map<*, *> ?: return@mapNotNull null
            val emoji = counter["reaction"] as? String ?: return@mapNotNull null
            if (emoji.isEmpty()) return@mapNotNull null
            MessageReaction(emoji, maxOf(0, integer(counter["count"]) ?: 0), emoji == yours)
        }.filter { it.count > 0 }
    }

    private fun comments(body: Map<*, *>): Int? {
        integer(body["commentsCount"])?.let { return maxOf(0, it) }
        val info = body["commentsInfo"] as? Map<*, *> ?: return null
        return integer(info["totalCount"])?.let { maxOf(0, it) }
    }

    fun previewOf(attachments: List<ChatAttachment>): String {
        if (attachments.any { it is ChatAttachment.Voice }) return "Голосовое сообщение"
        if (attachments.any { it is ChatAttachment.Video }) return "Видео"
        if (attachments.any { it is ChatAttachment.Photo }) return "Фото"
        attachments.filterIsInstance<ChatAttachment.File>().firstOrNull()?.let { return it.file.name.trim().ifEmpty { "Файл" } }
        if (attachments.any { it is ChatAttachment.Contact }) return "Контакт"
        if (attachments.any { it is ChatAttachment.Sticker }) return "Стикер"
        attachments.filterIsInstance<ChatAttachment.Poll>().firstOrNull()?.let { return "Опрос" }
        attachments.filterIsInstance<ChatAttachment.Call>().firstOrNull()?.let { return if (it.call.isGroup) "Групповой звонок" else "Звонок" }
        return ""
    }

    private fun replyKind(text: String, attachments: List<ChatAttachment>): MessageReply.Kind = when {
        text.isNotEmpty() -> MessageReply.Kind.TEXT
        attachments.any { it is ChatAttachment.Voice } -> MessageReply.Kind.VOICE
        attachments.any { it is ChatAttachment.Video } -> MessageReply.Kind.VIDEO
        attachments.any { it is ChatAttachment.Photo } -> MessageReply.Kind.PHOTO
        attachments.any { it is ChatAttachment.File } -> MessageReply.Kind.FILE
        else -> MessageReply.Kind.TEXT
    }

    /** `previewData`: байты картинки массивом или строкой base64 (в том числе `data:`-адресом). */
    private fun preview(value: Any?): ByteArray? {
        when (value) {
            is ByteArray -> return value.takeIf { it.isNotEmpty() }
            is List<*> -> return value.mapNotNull { integer(it)?.toByte() }.toByteArray().takeIf { it.isNotEmpty() }
        }
        var text = value as? String ?: return null
        if (text.isEmpty()) return null
        if (text.startsWith("data:")) text = text.substringAfter(',')
        return runCatching { Base64.getDecoder().decode(text) }.getOrNull()
    }

    /** Волна голосового: массив чисел, байты или строка base64. */
    fun wave(value: Any?): List<Int> {
        when (value) {
            is ByteArray -> return value.map { it.toInt() and 0xFF }
            is List<*> -> return value.mapNotNull(::integer)
        }
        val text = value as? String ?: return emptyList()
        if (text.isEmpty()) return emptyList()
        val bytes = runCatching { Base64.getDecoder().decode(text) }.getOrNull()
        if (bytes != null && bytes.size >= 8) return bytes.map { it.toInt() and 0xFF }
        return text.map { it.code and 0xFF }
    }

    /** Длительность приходит сырыми миллисекундами. */
    private fun durationMs(value: Any?): Long = maxOf(0L, ChatMapping.longOf(value) ?: 0L)

    private fun integer(value: Any?): Int? = when (value) {
        is Number -> value.toInt()
        is String -> value.toIntOrNull()
        else -> null
    }

    private fun stringId(value: Any?): String? = when (value) {
        is String -> value.takeIf { it.isNotEmpty() }
        is Number -> value.toLong().toString()
        else -> null
    }

    private fun url(value: Any?): String? = (value as? String)?.takeIf { it.isNotEmpty() }

    private fun stableId(map: Map<*, *>): String =
        listOf(map["baseUrl"], map["url"], map["fileUrl"]).firstNotNullOfOrNull { (it as? String)?.takeIf(String::isNotEmpty) }
            ?: "att-${map.hashCode()}"
}
