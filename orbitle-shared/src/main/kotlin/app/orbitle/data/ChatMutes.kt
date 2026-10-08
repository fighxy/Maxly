package app.orbitle.data

import app.orbitle.domain.Chat
import com.max.core.api.AccountConfig
import com.max.core.state.MaxState
import com.max.shared.MaxClient
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.transformLatest
import java.util.WeakHashMap
import java.util.concurrent.ConcurrentHashMap

/**
 * Последний известный `dontDisturbUntil` каждого чата. Конфиг аккаунта может прийти без записи
 * о чате (или вовсе без `chats`): тогда звук чата остаётся прежним, а не включается. Чат, о
 * котором конфиг не говорил ни разу, со звуком.
 */
class ChatMutes {
    private val known = ConcurrentHashMap<Long, Long>()

    /** Без звука ли [chatId] в [nowMs]: по [config], а если он молчит — по последнему известному. */
    fun isMuted(chatId: Long, config: AccountConfig?, nowMs: Long): Boolean {
        val until = untilOf(chatId, config) ?: return false
        return until < 0 || until > nowMs
    }

    /** Ближайший момент после [nowMs], когда у одного из [chatIds] кончится выключенный звук. */
    fun nextExpiry(chatIds: Iterable<Long>, config: AccountConfig?, nowMs: Long): Long? {
        var next: Long? = null
        for (id in chatIds) {
            val until = untilOf(id, config) ?: continue
            if (until > nowMs && (next == null || until < next)) next = until
        }
        return next
    }

    /** Аккаунт вышел: чужие настройки не переносятся на следующий. */
    fun clear() = known.clear()

    private fun untilOf(chatId: Long, config: AccountConfig?): Long? {
        val fresh = config?.dontDisturbUntil(chatId)
        if (fresh != null) {
            known[chatId] = fresh
            return fresh
        }
        return known[chatId]
    }

    companion object {
        private val byClient = WeakHashMap<MaxClient, ChatMutes>()

        /** Одна память на клиента: список чатов и шапка чата видят один и тот же звук. */
        fun of(client: MaxClient): ChatMutes = synchronized(byClient) { byClient.getOrPut(client) { ChatMutes() } }

        /**
         * Список чатов из стора и конфига. Пересобирается и от одного нового конфига, и в момент,
         * когда кончается выключенный на время звук какого-либо чата. `null` — снимка ещё нет.
         */
        @OptIn(ExperimentalCoroutinesApi::class)
        fun chatList(
            states: Flow<MaxState>,
            configs: Flow<AccountConfig?>,
            loaded: Flow<Boolean>,
            mutes: ChatMutes,
            clock: () -> Long,
        ): Flow<List<Chat>?> = combine(states, configs, loaded) { state, config, ready -> Triple(state, config, ready) }
            .transformLatest { (state, config, ready) ->
                if (!ready && state.chats.isEmpty()) {
                    emit(null)
                    return@transformLatest
                }
                while (true) {
                    val now = clock()
                    emit(ChatMapping.chats(state, config, now, mutes))
                    val next = mutes.nextExpiry(state.chats.keys, config, now) ?: break
                    delay((next - now).coerceAtLeast(0) + 1)
                }
            }
            .distinctUntilChanged()
    }
}
