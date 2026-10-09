package app.maxly.data

import app.maxly.domain.Typist
import app.maxly.domain.TypingKind
import com.maxly.core.state.MaxState

/**
 * Кто сейчас что-то делает в чате: из `typingUsersWithType` ядра (живёт 8 с после последнего
 * сигнала, сообщение человека снимает его отметку), без своего аккаунта. Ядро помнит только
 * последний сигнал, а порядок нужен по началу действия (`test-fixtures/typing`, `expiry-order`):
 * повтор место не меняет, сигнал после истечения — новое начало. Поэтому начало хранится здесь.
 */
internal class TypingTracker(private val ttlMs: Long = MaxState.DEFAULT_TYPING_TTL_MS) {
    private class Mark(val since: Long, var last: Long)

    private val marks = HashMap<Pair<Long, Long>, Mark>()

    @Synchronized
    fun typists(state: MaxState, chatId: Long, now: Long, name: (Long) -> String?): List<Typist> {
        val current = state.typingUsersWithType(chatId, now, ttlMs).filterKeys { it != state.me }
        marks.keys.removeAll { (chat, user) -> chat == chatId && user !in current }
        return current.map { (user, type) ->
            val last = state.typing[chatId]?.get(user) ?: now
            val key = chatId to user
            val mark = marks[key]?.takeIf { last - it.last <= ttlMs } ?: Mark(last, last).also { marks[key] = it }
            mark.last = last
            Typist(name(user), TypingKind.of(type), mark.since, user.toString())
        }.sortedWith(Typist.ORDER)
    }
}
