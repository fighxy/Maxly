package app.maxly.data

import app.maxly.domain.Chat
import com.maxly.core.api.AccountConfig
import com.maxly.core.events.MaxEvent
import com.maxly.core.state.MaxState
import com.maxly.shared.MaxClient
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.transformLatest
import java.util.WeakHashMap
import java.util.concurrent.ConcurrentHashMap

/**
 * Звук чатов по конфигу аккаунта ([AccountConfig.chatMuteState] и [AccountConfig.chatMuteUntil]).
 * Когда конфиг о чате не знает (`null`: конфига нет или он неполный), остаётся последний
 * известный `dontDisturbUntil` чата, а не включается звук. Чат, о котором не было известно
 * ничего, со звуком.
 */
class ChatMutes {
    private val known = ConcurrentHashMap<Long, Long>()

    /** Без звука ли [chatId] в [nowMs]: по [config], а если он не знает — по последнему известному. */
    fun isMuted(chatId: Long, config: AccountConfig?, nowMs: Long): Boolean {
        config?.chatMuteState(chatId, nowMs)?.let { muted ->
            config.chatMuteUntil(chatId)?.let { known[chatId] = it }
            return muted
        }
        val until = known[chatId] ?: return false
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
        val fresh = config?.chatMuteUntil(chatId)
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
         * Пуши `NOTIF_CONFIG` 134 клиента из `appliedEvents`: событие приходит, когда ядро уже
         * влило пуш в `accountConfig`, так что по сигналу читается новый конфиг.
         */
        fun configPushes(client: MaxClient): Flow<Unit> =
            client.appliedEvents.filterIsInstance<MaxEvent.ConfigUpdated>().map { }

        /**
         * Список чатов из стора и конфига. Пересобирается от нового конфига, от пуша настроек
         * [pushes] и в момент, когда кончается выключенный на время звук какого-либо чата
         * (конец ядро событием не присылает). `null` — снимка ещё нет.
         */
        @OptIn(ExperimentalCoroutinesApi::class)
        fun chatList(
            states: Flow<MaxState>,
            configs: Flow<AccountConfig?>,
            loaded: Flow<Boolean>,
            mutes: ChatMutes,
            clock: () -> Long,
            pushes: Flow<Unit> = emptyFlow(),
        ): Flow<List<Chat>?> = combine(states, configs, loaded, pushes.onStart { emit(Unit) }) { state, config, ready, _ -> Triple(state, config, ready) }
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
