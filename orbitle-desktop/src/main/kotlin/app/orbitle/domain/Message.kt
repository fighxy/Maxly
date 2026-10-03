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
) {
    val visuals: List<ChatAttachment> get() = attachments.filter { it is ChatAttachment.Photo || it is ChatAttachment.Video }
    val voices: List<VoiceContent> get() = attachments.filterIsInstance<ChatAttachment.Voice>().map { it.voice }
    val files: List<FileContent> get() = attachments.filterIsInstance<ChatAttachment.File>().map { it.file }
    val sticker: StickerContent? get() = attachments.filterIsInstance<ChatAttachment.Sticker>().firstOrNull()?.sticker
    val call: CallContent? get() = attachments.filterIsInstance<ChatAttachment.Call>().firstOrNull()?.call

    companion object {
        val empty = MessageContent()
    }
}

/** Отрезок разметки текста (смещения UTF-16, как у сервера). */
data class TextSpan(
    val kind: Kind,
    val from: Int,
    val length: Int,
    val url: String? = null,
    val userId: String? = null,
    val entityId: String? = null,
) {
    enum class Kind { STRONG, EMPHASIZED, UNDERLINE, STRIKETHROUGH, MONOSPACED, HEADING, QUOTE, LINK, MENTION, ANIMOJI }
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
}

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
