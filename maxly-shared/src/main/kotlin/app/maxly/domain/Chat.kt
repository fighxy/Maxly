package app.maxly.domain

/** Тип чата. */
enum class ChatType {
    /** Личная переписка один на один. */
    PRIVATE,
    GROUP,
    CHANNEL;

    companion object {
        /** Тип чата из ядра (`DIALOG`, `CHAT`, `CHANNEL`). */
        fun fromCore(raw: String): ChatType = when (raw.uppercase()) {
            "DIALOG", "PRIVATE" -> PRIVATE
            "CHANNEL" -> CHANNEL
            else -> GROUP
        }
    }
}

/** Судьба своего последнего сообщения: от очереди до прочтения собеседником. */
enum class DeliveryState { SENDING, SENT, READ, FAILED }

/** Вид вложения в последнем сообщении. По нему строка списка пишет «Фотография», «Видео»… */
enum class MessageMediaKind(val raw: String) {
    PHOTO("photo"),
    VIDEO("video"),
    VOICE("voice"),
    VIDEO_MESSAGE("videoMessage"),
    AUDIO("audio"),
    FILE("file"),
    STICKER("sticker"),
    GIF("gif"),
    LOCATION("location"),
    CONTACT("contact"),
    POLL("poll"),
    CALL("call"),
    /** Групповой звонок: у вложения `CALL` есть ссылка для входа. */
    GROUP_CALL("groupCall");

    companion object {
        fun fromRaw(raw: String?): MessageMediaKind? = entries.firstOrNull { it.raw == raw }
    }
}

/** Последнее сообщение чата в том объёме, который нужен строке списка. */
data class ChatLastMessage(
    val authorId: String? = null,
    /** Имя автора для префикса в группах. */
    val authorName: String? = null,
    val isOutgoing: Boolean = false,
    /** Доставка своего сообщения. У входящих `null`. */
    val delivery: DeliveryState? = null,
    val media: MessageMediaKind? = null,
    val thumbnailUrl: String? = null,
    /** Пересланное сообщение: строка показывает стрелку перед текстом. */
    val isForwarded: Boolean = false,
)

/**
 * Черновик, оставленный в поле ввода чата: текст с отметками ([formatting] — разметка, упоминания,
 * анимодзи, смещения в [text]) и id сообщения, на которое начат ответ. Черновик бывает и из одного
 * ответа без текста; без текста и без ответа черновика нет ([isEmpty]). Вложений в черновиках нет.
 */
data class ChatDraft(
    val text: String,
    val updatedAtMs: Long,
    val formatting: List<TextSpan> = emptyList(),
    val replyTo: String? = null,
) {
    /** Ни текста, ни ответа: такой черновик удаляется. */
    val isEmpty: Boolean get() = text.isBlank() && replyTo == null

    /**
     * То же содержимое, время не в счёт: тот же ответ, текст после обрезки краёв и отметки по нему
     * ([TextSpans.serialize]) — так их увидит сервер.
     */
    fun sameContent(other: ChatDraft?): Boolean {
        if (other == null || replyTo != other.replyTo) return false
        val (mine, myMarks) = TextSpans.serialize(text, formatting)
        val (theirs, theirMarks) = TextSpans.serialize(other.text, other.formatting)
        return mine == theirs && myMarks.toSet() == theirMarks.toSet()
    }
}

/** Чат, как его видит UI. Время — миллисекунды Unix. */
data class Chat(
    val id: String,
    val title: String,
    val type: ChatType,
    val lastMessageId: String? = null,
    val unreadCount: Int = 0,
    /** Время последней активности, по нему сортируется список. */
    val updatedAtMs: Long,
    /** Текст последнего сообщения для строки списка. */
    val preview: String? = null,
    val lastMessage: ChatLastMessage? = null,
    val avatarUrl: String? = null,
    /** Место в закреплённых: меньше — выше. `null`, если чат не закреплён. */
    val pinOrder: Int? = null,
    val isMuted: Boolean = false,
    val isMarkedUnread: Boolean = false,
    val isArchived: Boolean = false,
    val isBot: Boolean = false,
    /** Диалог с ботом, у которого есть мини-приложение. Ставит ядро (`Chat.hasWebApp`). */
    val hasWebApp: Boolean = false,
    val isVerified: Boolean = false,
    val isOnline: Boolean = false,
    val unreadMentions: Int = 0,
    val draft: ChatDraft? = null,
    /** Комментарии канала: `null` — сервер не сказал. */
    val commentsEnabled: Boolean? = null,
    /** Можно ли писать в чат. `null` — сервер не сказал. */
    val canWrite: Boolean? = null,
    /** Собеседник личного чата. */
    val peerId: String? = null,
) {
    val isPinned: Boolean get() = pinOrder != null
    val isSavedMessages: Boolean get() = id == SAVED_MESSAGES_ID
    /** Есть что читать: счётчик или ручная пометка. */
    val isUnread: Boolean get() = unreadCount > 0 || isMarkedUnread

    /** Время для сортировки: свежий черновик поднимает чат так же, как новое сообщение. */
    val activityMs: Long get() = draft?.updatedAtMs?.takeIf { it > updatedAtMs } ?: updatedAtMs

    companion object {
        /** id «Избранного» (сохранённые сообщения) в Max. */
        const val SAVED_MESSAGES_ID = "0"

        /** Порядок списка: закреплённые по `pinOrder`, затем остальные по свежести, при равенстве по id. */
        val listOrder: Comparator<Chat> = Comparator { l, r ->
            val lp = l.pinOrder
            val rp = r.pinOrder
            when {
                lp != null && rp != null -> if (lp != rp) lp.compareTo(rp) else l.id.compareTo(r.id)
                lp != null -> -1
                rp != null -> 1
                else -> {
                    val la = l.activityMs
                    val ra = r.activityMs
                    if (la != ra) ra.compareTo(la) else l.id.compareTo(r.id)
                }
            }
        }
    }
}
