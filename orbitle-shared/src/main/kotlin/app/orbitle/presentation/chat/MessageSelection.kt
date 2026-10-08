package app.orbitle.presentation.chat

import app.orbitle.domain.Chat
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import app.orbitle.presentation.common.PresenceText
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Выбор нескольких сообщений в ленте: подписи шапки и диалогов и текст для копирования.
 * Всё здесь — чистые функции, экран и [ChatViewModel] только подставляют данные.
 */
object MessageSelection {
    /** «1 сообщение», «3 сообщения», «11 сообщений». */
    fun countLabel(count: Int): String =
        "$count ${PresenceText.plural(count, "сообщение", "сообщения", "сообщений")}"

    /** Шапка в режиме выбора. */
    fun title(count: Int): String = countLabel(count)

    /** Заголовок подтверждения удаления: одно сообщение — как у меню сообщения. */
    fun deleteTitle(count: Int): String =
        if (count == 1) "Удалить сообщение?" else "Удалить ${countLabel(count)}?"

    /** Снекбар, если сервер удалил не всё: [failed] из [total] остались. */
    fun deleteFailedNotice(failed: Int, total: Int): String =
        if (total == 1) "Не удалось удалить сообщение" else "Не удалось удалить $failed из $total"

    /** Снекбар после пересылки. */
    fun forwardedNotice(count: Int): String =
        if (count == 1) "Сообщение переслано" else "Переслано: ${countLabel(count)}"

    /** Порядок ленты: от старых к новым, при равном времени — по id сервера. */
    val chronological: Comparator<Message> =
        compareBy<Message>({ it.timeMs }, { it.id.toLongOrNull() ?: Long.MAX_VALUE }, { it.id })

    /** Как можно удалить одно сообщение: у всех, только у себя или никак. */
    enum class DeleteScope { ALL, SELF, NONE }

    /** Какой чат для правил удаления. */
    enum class ChatKind { SAVED, DIALOG, GROUP, CHANNEL }

    /**
     * Подтверждение удаления выбранного: [scopes] по id; [canDelete] — нет ни одного [DeleteScope.NONE]
     * (и выбор не пуст); [showsForEveryone] — выбор «у всех» (все [DeleteScope.ALL], не канал), он
     * же включён сразу ([forEveryoneByDefault]); [forcesForEveryone] — канал с правами: только у всех.
     */
    data class DeletePlan(
        val scopes: Map<String, DeleteScope>,
        val canDelete: Boolean,
        val showsForEveryone: Boolean,
        val forEveryoneByDefault: Boolean,
        val forcesForEveryone: Boolean,
    )

    /** Вид чата [chat] для [deletePlan]. */
    fun chatKind(chatId: String, type: ChatType?): ChatKind = when {
        chatId == Chat.SAVED_MESSAGES_ID -> ChatKind.SAVED
        type == ChatType.CHANNEL -> ChatKind.CHANNEL
        type == ChatType.GROUP -> ChatKind.GROUP
        else -> ChatKind.DIALOG
    }

    /**
     * Правила удаления (общие с iOS, `test-fixtures/selection/delete`). «Избранное» — у себя (сервер
     * стирает целиком). Не ушедшее — у себя (в канале без прав — никак). Личный чат — своё моложе
     * [editTimeoutSec] у всех, иначе у себя. Группа — админ у всех; своё моложе [editTimeoutSec] у
     * всех; иначе у себя. Канал — админ у всех (и только так), остальные никак. «Моложе» — строго:
     * `now - time < editTimeout`.
     */
    fun deletePlan(
        messages: List<Message>,
        me: String?,
        nowMs: Long,
        kind: ChatKind,
        admin: Boolean,
        editTimeoutSec: Long,
    ): DeletePlan {
        val scopes = LinkedHashMap<String, DeleteScope>()
        for (message in messages) {
            val own = me != null && message.authorId == me
            val fresh = own && nowMs - message.timeMs < editTimeoutSec * 1_000L
            val unsent = message.status != MessageStatus.SENT
            scopes[message.id] = when {
                kind == ChatKind.SAVED -> DeleteScope.SELF
                unsent -> if (kind == ChatKind.CHANNEL && !admin) DeleteScope.NONE else DeleteScope.SELF
                kind == ChatKind.CHANNEL -> if (admin) DeleteScope.ALL else DeleteScope.NONE
                kind == ChatKind.GROUP && admin -> DeleteScope.ALL
                fresh -> DeleteScope.ALL
                else -> DeleteScope.SELF
            }
        }
        val any = scopes.isNotEmpty()
        val canDelete = any && DeleteScope.NONE !in scopes.values
        val allEveryone = any && scopes.values.all { it == DeleteScope.ALL }
        val shows = allEveryone && kind != ChatKind.CHANNEL
        return DeletePlan(
            scopes = scopes,
            canDelete = canDelete,
            showsForEveryone = shows,
            forEveryoneByDefault = shows,
            forcesForEveryone = allEveryone && kind == ChatKind.CHANNEL,
        )
    }

    /** Шаг пересылки: комментарий в чат или одно сообщение в чат. */
    sealed interface ForwardStep {
        val target: String

        data class Comment(override val target: String, val text: String) : ForwardStep
        data class Forward(override val target: String, val messageId: String) : ForwardStep
    }

    /**
     * Порядок пересылки (общий с iOS, `test-fixtures/selection/forward`): один `MSG_SEND` на
     * сообщение на чат. Сначала комментарий (если он не пустой после обрезки) в каждый чат, затем
     * сообщения от старых к новым (равное время — по id числом), каждое — во все чаты по порядку
     * выбора. Повторы сообщений и чатов выбрасываются.
     */
    fun forwardPlan(messages: List<Message>, targets: List<String>, comment: String?): List<ForwardStep> {
        val chats = targets.distinct()
        if (chats.isEmpty()) return emptyList()
        val note = comment?.trim().orEmpty()
        val ordered = messages.distinctBy { it.id }.sortedWith(chronological)
        return buildList {
            if (note.isNotEmpty()) chats.forEach { add(ForwardStep.Comment(it, note)) }
            for (message in ordered) chats.forEach { add(ForwardStep.Forward(it, message.id)) }
        }
    }

    /** Подпись сообщения без текста при копировании: вид вложения, без него — «Сообщение». */
    fun mediaLabel(message: Message): String {
        val attachments = message.content.attachments
        return when {
            attachments.any { it is ChatAttachment.Voice } -> "Голосовое сообщение"
            attachments.any { it is ChatAttachment.Video && it.video.isRound } -> "Видеосообщение"
            attachments.any { it is ChatAttachment.Video } -> "Видео"
            attachments.any { it is ChatAttachment.Photo } -> "Фото"
            attachments.any { it is ChatAttachment.File } -> "Файл"
            attachments.any { it is ChatAttachment.Sticker } -> "Стикер"
            attachments.any { it is ChatAttachment.Contact } -> "Контакт"
            attachments.any { it is ChatAttachment.Poll } -> "Опрос"
            else -> "Сообщение"
        }
    }

    /** Время блока при копировании: `[дд.мм.гггг чч:мм]` в поясе [zone]. */
    fun copyTime(timeMs: Long, zone: ZoneId): String =
        "[" + COPY_TIME.format(Instant.ofEpochMilli(timeMs).atZone(zone)) + "]"

    private val COPY_TIME: DateTimeFormatter = DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm")

    /** Имя автора для копирования, когда другого нет. */
    const val NO_NAME = "Участник"

    /**
     * Текст выбранных сообщений для буфера обмена (общий с iOS, `test-fixtures/selection/copy`),
     * от старых к новым. Одно сообщение — просто его текст (обрезанный). Несколько — блоки
     * «Имя, [дд.мм.гггг чч:мм]» ([copyTime]) и текст с новой строки, между блоками пустая строка.
     * Без текста — подпись вложения ([mediaLabel]); без имени — «Участник».
     */
    fun copyText(messages: List<Message>, zone: ZoneId, name: (Message) -> String = { it.authorName }): String {
        val ordered = messages.sortedWith(chronological)
        if (ordered.isEmpty()) return ""
        fun body(message: Message) = message.displayText.trim().ifEmpty { mediaLabel(message) }
        if (ordered.size == 1) return body(ordered.single())
        return ordered.joinToString("\n\n") { message ->
            val author = name(message).trim().ifEmpty { NO_NAME }
            "$author, ${copyTime(message.timeMs, zone)}\n${body(message)}"
        }
    }
}
