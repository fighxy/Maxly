package app.orbitle.data

import app.orbitle.domain.Typist
import app.orbitle.domain.TypingKind
import com.max.core.state.MaxState

/**
 * Кто сейчас что-то делает в чате: из `typingUsersWithType` ядра (живёт 8 с после последнего
 * сигнала), без своего аккаунта. Ядро помнит только последний сигнал, а порядок нужен по началу
 * действия, иначе в группе вид действия менялся бы с каждым повтором. Поэтому начало хранится
 * здесь, пока человек не пропадёт из ядра.
 */
internal class TypingTracker {
    private val started = HashMap<Pair<Long, Long>, Long>()

    @Synchronized
    fun typists(state: MaxState, chatId: Long, now: Long, name: (Long) -> String?): List<Typist> {
        val current = state.typingUsersWithType(chatId, now).filterKeys { it != state.me }
        started.keys.removeAll { (chat, user) -> chat == chatId && user !in current }
        return current.map { (user, type) ->
            val since = started.getOrPut(chatId to user) { state.typing[chatId]?.get(user) ?: now }
            Typist(name(user), TypingKind.of(type), since)
        }.sortedBy { it.sinceMs }
    }
}
