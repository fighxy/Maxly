package app.orbitle.domain

/** Судьба сообщения: в очереди, на сервере или не ушло. */
enum class MessageStatus { SENDING, SENT, FAILED }

/** Сообщение, как его видит экран чата. Время — миллисекунды Unix. */
data class Message(
    val id: String,
    val chatId: String,
    val authorId: String,
    val text: String,
    val timeMs: Long,
    val status: MessageStatus = MessageStatus.SENT,
    val content: MessageContent = MessageContent.empty,
    val authorName: String = "",
    val authorAvatarUrl: String? = null,
    /** Своё сообщение прочитано собеседником. */
    val isRead: Boolean = false,
    /** Служебное сообщение сервера (`CONTROL`): «X добавил Y», «Чат создан». */
    val isService: Boolean = false,
) {
    /** Текст пузыря: у пересылки без своего текста — текст оригинала. */
    val displayText: String
        get() {
            val own = text.trim()
            val forwarded = content.forward?.text
            return if (own.isEmpty() && !forwarded.isNullOrEmpty()) forwarded else text
        }

    /** Короткая подпись для цитаты в ответе. */
    val replySnippet: String
        get() {
            val trimmed = displayText.trim()
            if (trimmed.isNotEmpty()) return trimmed
            if (content.voices.isNotEmpty()) return "Голосовое сообщение"
            if (content.attachments.any { it is ChatAttachment.Video }) return "Видео"
            if (content.attachments.any { it is ChatAttachment.Photo }) return "Фото"
            content.files.firstOrNull()?.let { return it.name.trim().ifEmpty { "Файл" } }
            content.attachments.filterIsInstance<ChatAttachment.Contact>().firstOrNull()?.let {
                return if (it.contact.name.isEmpty()) "Контакт" else "Контакт: ${it.contact.name}"
            }
            content.call?.let { return if (it.isGroup) "Групповой звонок" else "Звонок" }
            content.sticker?.let { return "Стикер" }
            content.poll?.let { return "Опрос" }
            return "Сообщение"
        }

    val replyKind: MessageReply.Kind
        get() = when {
            text.trim().isNotEmpty() -> MessageReply.Kind.TEXT
            content.voices.isNotEmpty() -> MessageReply.Kind.VOICE
            content.attachments.any { it is ChatAttachment.Video } -> MessageReply.Kind.VIDEO
            content.attachments.any { it is ChatAttachment.Photo } -> MessageReply.Kind.PHOTO
            content.files.isNotEmpty() -> MessageReply.Kind.FILE
            else -> MessageReply.Kind.TEXT
        }
}

/** Всё, что лежит рядом с текстом: вложения, цитата, пересылка, реакции, разметка. */
data class MessageContent(
    val reply: MessageReply? = null,
    val attachments: List<ChatAttachment> = emptyList(),
    val reactions: List<MessageReaction> = emptyList(),
    val comments: Int? = null,
    val formatting: List<TextSpan> = emptyList(),
    val forward: MessageForward? = null,
    val edited: Boolean = false,
    /** Время правки (мс), если сервер его прислал (`updateTime`). */
    val editedAtMs: Long? = null,
    /** Закрепление из служебного `CONTROL` `pin` / `unpin`. */
    val pin: PinNotice? = null,
    /** Превью ссылки из текста (вложение `SHARE`). */
    val linkPreview: LinkPreview? = null,
    /** Inline-кнопки бота под сообщением (вложение `INLINE_KEYBOARD`). */
    val keyboard: InlineKeyboard? = null,
) {
    val visuals: List<ChatAttachment> get() = attachments.filter { it is ChatAttachment.Photo || it is ChatAttachment.Video }
    val voices: List<VoiceContent> get() = attachments.filterIsInstance<ChatAttachment.Voice>().map { it.voice }
    val files: List<FileContent> get() = attachments.filterIsInstance<ChatAttachment.File>().map { it.file }
    val sticker: StickerContent? get() = attachments.filterIsInstance<ChatAttachment.Sticker>().firstOrNull()?.sticker
    val call: CallContent? get() = attachments.filterIsInstance<ChatAttachment.Call>().firstOrNull()?.call
    val poll: PollContent? get() = attachments.filterIsInstance<ChatAttachment.Poll>().firstOrNull()?.poll

    companion object {
        val empty = MessageContent()
    }
}

/** Превью ссылки (`SHARE`): адрес, сайт, заголовок, описание и картинка, как их собрал сервер. */
data class LinkPreview(
    val url: String,
    val host: String? = null,
    val title: String? = null,
    val summary: String? = null,
    val imageUrl: String? = null,
    val imageWidth: Int? = null,
    val imageHeight: Int? = null,
) {
    /** Сайт для подписи: `host` сервера или хост адреса без `www.`. */
    val site: String?
        get() {
            val raw = host ?: runCatching { java.net.URI(url).host }.getOrNull() ?: return null
            return raw.removePrefix("www.").takeIf { it.isNotEmpty() }
        }
}

/** Inline-клавиатура бота: ряды кнопок и `callbackId` для нажатий `CALLBACK` (опкод 118). */
data class InlineKeyboard(val callbackId: String?, val rows: List<List<InlineButton>>)

/** Кнопка бота. [type] — как прислал сервер, заглавными: `CALLBACK`, `LINK`, `OPEN_APP`, `CLIPBOARD`… */
data class InlineButton(
    val type: String,
    val text: String,
    val url: String? = null,
    val webApp: String? = null,
    val contactId: String? = null,
    val payload: String? = null,
) {
    sealed interface Action {
        /** Нажатие уходит боту (опкод 118). */
        data object Callback : Action
        data class Link(val url: String) : Action
        /**
         * Мини-приложение бота: [botId], если кнопка его назвала, параметр запуска и [chatId]
         * из ссылки `webApp` (`chat_id`), если она его задаёт; иначе — чат сообщения.
         */
        data class OpenApp(val botId: String?, val startParam: String?, val chatId: String? = null) : Action
        data class Copy(val text: String) : Action
    }

    /** Что делает нажатие. Неизвестные типы уходят боту, как в других клиентах Max. */
    val action: Action
        get() = when (type.uppercase()) {
            "LINK" -> url?.takeIf { it.isNotBlank() }?.let { Action.Link(it) } ?: Action.Callback
            "OPEN_APP" -> {
                val query = webApp?.let { runCatching { java.net.URI(it).rawQuery }.getOrNull() }.orEmpty()
                val params = query.split('&').map { it.split('=', limit = 2) }.filter { it.size == 2 }
                fun param(vararg names: String) = params.firstOrNull { it[0] in names }?.get(1)
                    ?.let { java.net.URLDecoder.decode(it, "UTF-8") }
                Action.OpenApp(contactId, payload ?: param("startapp", "startApp"), param("chat_id")?.takeIf { it.toLongOrNull() != null })
            }
            "CLIPBOARD" -> Action.Copy(payload.orEmpty())
            else -> Action.Callback
        }

    /** Значок-подсказка справа: ссылка, приложение, копирование. */
    val hint: Hint?
        get() = when (action) {
            is Action.Link -> Hint.LINK
            is Action.OpenApp -> Hint.APP
            is Action.Copy -> Hint.COPY
            Action.Callback -> null
        }

    enum class Hint { LINK, APP, COPY }
}

/** Отрезок разметки текста (смещения UTF-16, как у сервера). */
data class TextSpan(
    val kind: Kind,
    val from: Int,
    val length: Int,
    val url: String? = null,
    val userId: String? = null,
    val entityId: String? = null,
    /**
     * Элемент незнакомого типа ([Kind.UNKNOWN], разметка другого клиента): тип как пришёл и все
     * его данные (`entityId`, `entityName`, `attributes`); смещения в нём нулевые — они в [from] и
     * [length]. Такой отрезок не рисуется, но хранится и при правке уходит обратно как был.
     */
    val foreign: com.max.core.api.TextElement? = null,
) {
    /** Виды разметки; [UNKNOWN] — незнакомый тип сервера, всегда последний. */
    enum class Kind { STRONG, EMPHASIZED, UNDERLINE, STRIKETHROUGH, MONOSPACED, HEADING, QUOTE, LINK, MENTION, ANIMOJI, UNKNOWN }
}

data class MessageForward(val authorName: String, val text: String)

data class MessageReply(val messageId: String, val authorName: String, val preview: String, val kind: Kind) {
    enum class Kind { TEXT, VOICE, PHOTO, VIDEO, FILE }
}

data class MessageReaction(val emoji: String, val count: Int, val mine: Boolean)

/** Кто поставил реакцию. Пустое имя — профиль не загрузился. */
data class ReactionUser(val userId: String, val name: String, val avatarUrl: String?, val emoji: String)

sealed interface ChatAttachment {
    val id: String

    data class Photo(val photo: PhotoContent) : ChatAttachment { override val id get() = photo.id }
    data class Video(val video: VideoContent) : ChatAttachment { override val id get() = video.id }
    data class Voice(val voice: VoiceContent) : ChatAttachment { override val id get() = voice.id }
    data class File(val file: FileContent) : ChatAttachment { override val id get() = file.id }
    data class Contact(val contact: ContactContent) : ChatAttachment { override val id get() = contact.id }
    data class Sticker(val sticker: StickerContent) : ChatAttachment { override val id get() = sticker.id }
    data class Call(val call: CallContent) : ChatAttachment { override val id get() = call.id }
    data class Poll(val poll: PollContent) : ChatAttachment { override val id get() = poll.id }
}

/** Опрос в сообщении. [id] — `pollId`, по нему уходит голос. */
data class PollContent(
    val id: String,
    val title: String,
    val answers: List<PollAnswer>,
    val total: Int = 0,
)

data class PollAnswer(val id: String, val text: String, val votes: Int = 0)

/** Служебное закрепление: пустой [messageId] — закреп сняли. */
data class PinNotice(val messageId: String?, val preview: String)

data class PhotoContent(val id: String, val url: String?, val width: Int? = null, val height: Int? = null, val preview: ByteArray? = null) {
    override fun equals(other: Any?) = other is PhotoContent && other.id == id && other.url == url && other.width == width && other.height == height
    override fun hashCode() = id.hashCode()
}

data class VideoContent(
    val id: String,
    val url: String?,
    val posterUrl: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val durationMs: Long = 0,
    /** Видеосообщение-кружок (`videoType` 1). */
    val isRound: Boolean = false,
)

data class VoiceContent(
    val id: String,
    val url: String?,
    /** Амплитуды 0…255, как прислал сервер. */
    val waveform: List<Int> = emptyList(),
    val durationMs: Long = 0,
    val transcript: String? = null,
)

data class FileContent(val id: String, val name: String, val size: Long = 0, val url: String? = null)

data class ContactContent(val id: String, val userId: String, val name: String, val phone: String, val avatarUrl: String? = null)

data class StickerContent(val id: String, val stickerId: String, val url: String?, val lottieUrl: String? = null, val width: Int? = null, val height: Int? = null)

/** Звонок в переписке. `duration` в миллисекундах; у группового есть ссылка для входа. */
data class CallContent(
    val id: String,
    val durationMs: Long = 0,
    val isVideo: Boolean = false,
    val hangupType: String = "",
    val conversationId: String? = null,
    val contactIds: List<String> = emptyList(),
    val joinLink: String? = null,
) {
    enum class Hangup { HUNGUP, CANCELED, REJECTED, MISSED, UNKNOWN }

    val hangup: Hangup get() = Hangup.entries.firstOrNull { it.name == hangupType.uppercase() } ?: Hangup.UNKNOWN
    val isGroup: Boolean get() = !joinLink.isNullOrEmpty()

    /** Разговор состоялся: есть длительность и звонок не сброшен. */
    val isConnected: Boolean
        get() = durationMs > 0 && hangup != Hangup.MISSED && hangup != Hangup.REJECTED && hangup != Hangup.CANCELED

    fun outcome(outgoing: Boolean): CallOutcome = when {
        isConnected -> CallOutcome.ANSWERED
        !outgoing -> CallOutcome.MISSED
        hangup == Hangup.REJECTED -> CallOutcome.DECLINED
        else -> CallOutcome.CANCELLED
    }

    fun isMissed(outgoing: Boolean): Boolean = !outgoing && !isConnected
}

enum class CallOutcome { ANSWERED, MISSED, CANCELLED, DECLINED }
