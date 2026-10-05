package app.orbitle.data

import app.orbitle.domain.Chat
import app.orbitle.domain.ChatSearchResult
import app.orbitle.domain.FoundMessage
import app.orbitle.domain.ServerFolder
import kotlinx.coroutines.flow.Flow

/** Список чатов. Источник правды — стор ядра; репозиторий только переводит модели. */
interface ChatRepository {
    /** Чаты, `null` до первого снимка с сервера. */
    val chats: Flow<List<Chat>?>
    /** Папки сервера без системной «Все». */
    val folders: Flow<List<ServerFolder>>
    /** Кто печатает: id чата → id пользователей. */
    val typing: Flow<Map<String, List<String>>>
    /** Первая загрузка после входа берёт все страницы и папки. */
    suspend fun refresh()
    suspend fun setPinned(chatId: String, pinned: Boolean)

    /**
     * Новый порядок закреплённых сверху вниз. Закреплённые, которых нет в [chatIds], остаются
     * после них в прежнем порядке.
     */
    suspend fun reorderPinned(chatIds: List<String>): Unit =
        throw app.orbitle.domain.OrbitleError.Rejected("Порядок закреплённых здесь не меняется")

    /** Выключить уведомления чата насовсем или включить обратно. */
    suspend fun setMuted(chatId: String, muted: Boolean) {}

    /** Прочитать всё в чате: отметка до последнего сообщения. */
    suspend fun markAsRead(chatId: String) {}

    /** Публичные чаты и каналы на сервере по названию или ссылке. Без поиска на сервере — пусто. */
    suspend fun searchPublic(query: String): List<ChatSearchResult> = emptyList()

    /** Сообщения во всех чатах по тексту, новые сверху. Без поиска — пусто. */
    suspend fun searchMessages(query: String): List<FoundMessage> = emptyList()

    /**
     * Новая группа (`MSG_SEND` 64, вложение CONTROL `event: new`, `chatType: CHAT`).
     * [memberIds] — другие пользователи; пустой список допустим. Возвращает id чата.
     */
    suspend fun createGroup(title: String, memberIds: List<String>): String? = null

    /**
     * Новый канал. Отдельного метода в ядре нет: тот же `MSG_SEND` 64, но `chatType: CHANNEL`
     * и без участников. Возвращает id чата.
     */
    suspend fun createChannel(title: String): String? = null

    /**
     * Личный чат в списке до того, как сервер пришлёт его сам.
     * Диалог на сервере появляется с первым сообщением. Уже существующий чат не перезаписывается.
     */
    suspend fun prepareDialog(chatId: String, peerId: String, title: String) {}

    /** Участники группы или канала, первая страница. */
    suspend fun members(chatId: String): List<ChatMemberRow> = emptyList()

    /** Общие чаты с человеком (`CHAT_SEARCH_COMMON_PARTICIPANTS` 198). */
    suspend fun commonChats(userId: String): List<SharedChat> = emptyList()

    /** Справочник жалоб. Ключ — `typeId`. Подтверждены канал `2` и пользователь `6`. */
    suspend fun complaintReasons(): Map<Int, List<ComplaintChoice>> = emptyMap()

    /**
     * Жалоба. [parentId] — чат сообщения, только если он известен.
     * `true` — сервер ответил `success: true`.
     */
    suspend fun complain(reasonId: Int, typeId: Int, ids: List<String>, parentId: String? = null): Boolean = false

    /**
     * Сигнал личного звонка. Сервер получает запрос, звук и видео не открываются.
     * `null` — сервер не вернул адрес сигналинга.
     */
    suspend fun signalCall(calleeId: String, isVideo: Boolean): SignaledCall? = null

    /** Войти по ссылке-приглашению. Возвращает id чата. */
    suspend fun joinByLink(link: String): String? = null

    /**
     * Удалить чат (`CHAT_DELETE` 52). `forEveryone` — у всех, иначе только у себя.
     * После ответа сервера чат и его сообщения пропадают из списка.
     */
    suspend fun deleteChat(chatId: String, forEveryone: Boolean) {}

    /**
     * Очистить переписку (`CHAT_CLEAR` 54). `forEveryone` — у всех, иначе только у себя.
     * Сам чат остаётся, сообщения и превью пропадают.
     */
    suspend fun clearHistory(chatId: String, forEveryone: Boolean) {}

    /** Команды бота (`BOT_INFO` 145). */
    suspend fun botCommands(botId: String): List<BotCommandRow> = emptyList()

    /**
     * Нажатие inline-кнопки `CALLBACK` бота (`MSG_SEND_CALLBACK` 118). Сам ответ бота обычно
     * приходит сообщением; здесь — короткий текст или адрес, если сервер их прислал.
     */
    suspend fun pressButton(chatId: String, messageId: String, callbackId: String, payload: String?): ButtonAnswer =
        throw app.orbitle.domain.OrbitleError.Rejected("Кнопка не поддерживается")

    /** Забыть всё про аккаунт (выход). */
    fun clear()
}

/** Ответ сервера на нажатие кнопки бота: уведомление и/или адрес для открытия. */
data class ButtonAnswer(val text: String? = null, val url: String? = null)
