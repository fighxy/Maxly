package app.orbitle.data

import app.orbitle.domain.Chat
import app.orbitle.domain.ChatSearchResult
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

    /** Выключить уведомления чата насовсем или включить обратно. */
    suspend fun setMuted(chatId: String, muted: Boolean) {}

    /** Прочитать всё в чате: отметка до последнего сообщения. */
    suspend fun markAsRead(chatId: String) {}

    /** Публичные чаты и каналы на сервере по названию или ссылке. Без поиска на сервере — пусто. */
    suspend fun searchPublic(query: String): List<ChatSearchResult> = emptyList()
    /** Забыть всё про аккаунт (выход). */
    fun clear()
}
