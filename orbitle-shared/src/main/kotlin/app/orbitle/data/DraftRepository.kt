package app.orbitle.data

import app.orbitle.domain.ChatDraft
import app.orbitle.domain.TextSpans
import com.max.core.api.DraftSupersededException
import com.max.core.api.MaxDraft
import com.max.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Черновики на сервере глазами экрана: сами черновики и что из них показать в поле ввода. */
interface ServerDrafts {
    /**
     * Черновики по id чата. Новое значение приходит и тогда, когда сменилась только отметка
     * стирания черновика: от неё зависит [reconcile].
     */
    val drafts: Flow<Map<String, ChatDraft>>

    /** Черновик чата сейчас. */
    fun current(chatId: String): ChatDraft?

    /**
     * Что показать в поле ввода [chatId], если на устройстве лежит [local]: правило ядра
     * (`MaxClient.reconcileDraft`, общие сценарии `test-fixtures/drafts`). Пустой черновик — всё
     * равно что его нет; из двух побеждает более поздний, при равном времени — [local];
     * стирание в то же время или позже убирает победителя. `null` — поле пустое.
     */
    fun reconcile(chatId: String, local: ChatDraft?): ChatDraft?

    companion object {
        /** Нет серверных черновиков: всегда остаётся [local]. */
        val NONE = object : ServerDrafts {
            override val drafts: Flow<Map<String, ChatDraft>> = kotlinx.coroutines.flow.flowOf(emptyMap())
            override fun current(chatId: String): ChatDraft? = null
            override fun reconcile(chatId: String, local: ChatDraft?): ChatDraft? = local?.takeUnless { it.isEmpty }
        }
    }
}

/** Черновики на сервере: видны на всех устройствах аккаунта. */
interface DraftRepository : ServerDrafts {
    suspend fun save(chatId: String, draft: ChatDraft)

    suspend fun discard(chatId: String)
}

/**
 * Черновики ядра ([MaxClient.drafts]): приходят с `LOGIN` и пушами, меняются через
 * [MaxClient.saveDraft]. Отметки стирания ([MaxClient.draftDiscards]) и выбор между черновиком
 * устройства и сервера ([MaxClient.reconcileDraft]) — тоже в ядре.
 */
class CoreDraftRepository(private val client: MaxClient) : DraftRepository {
    override val drafts: Flow<Map<String, ChatDraft>> = client.store.state
        .map { state -> state.drafts to state.draftDiscards }
        .distinctUntilChanged()
        .map { (drafts, _) -> drafts.entries.mapNotNull { (id, draft) -> draft(draft)?.let { id.toString() to it } }.toMap() }

    override fun current(chatId: String): ChatDraft? {
        val id = chatId.toLongOrNull() ?: return null
        return client.drafts[id]?.let(::draft)
    }

    override fun reconcile(chatId: String, local: ChatDraft?): ChatDraft? {
        val id = chatId.toLongOrNull() ?: return local?.takeUnless { it.isEmpty }
        return reconcile(id, local) { client.reconcileDraft(id, it) }
    }

    override suspend fun save(chatId: String, draft: ChatDraft) {
        val id = chatId.toLongOrNull() ?: return
        val request = request(draft)
        MaxCoreGateway.call {
            try {
                client.saveDraft(id, request.text, request.elements, request.replyTo)
            } catch (_: DraftSupersededException) {
                // Сохранение опоздало к отправке сообщения в этот чат: ядро его отбросило, а
                // черновик сервера сотрёт после отправки само. Это не ошибка.
            }
        }
    }

    override suspend fun discard(chatId: String) {
        val id = chatId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.discardDraft(id) }
    }

    /** Что уходит в [MaxClient.saveDraft]: текст без краёв, элементы по нему, ответ. */
    data class Request(val text: String, val elements: List<com.max.core.api.TextElement>, val replyTo: Long?)

    companion object {
        /**
         * Черновик поля для [MaxClient.saveDraft]: текст обрезан по краям, отметки сдвинуты и слиты
         * ([TextSpans.serialize], как при отправке сообщения), вложений нет.
         */
        fun request(draft: ChatDraft): Request {
            val (text, spans) = TextSpans.serialize(draft.text, draft.formatting)
            return Request(text, TextMarks.toElements(text, spans), draft.replyTo?.toLongOrNull())
        }

        /** Черновик устройства так, как его видит ядро: [request] со временем черновика. */
        fun maxDraft(chatId: Long, draft: ChatDraft): MaxDraft {
            val request = request(draft)
            return MaxDraft(chatId, request.text, request.elements, request.replyTo, draft.updatedAtMs)
        }

        /**
         * [local] против черновика сервера по правилу ядра [rule] (`MaxClient.reconcileDraft` или
         * `Drafts.reconcile`). Победил черновик устройства — он и возвращается как есть.
         */
        fun reconcile(chatId: Long, local: ChatDraft?, rule: (MaxDraft?) -> MaxDraft?): ChatDraft? {
            val mine = local?.takeUnless { it.isEmpty }?.let { maxDraft(chatId, it) }
            val winner = rule(mine) ?: return null
            return if (winner === mine) local else draft(winner)
        }

        /** Черновик ядра для экрана; `null` — ни текста, ни ответа. */
        fun draft(draft: com.max.core.api.MaxDraft): ChatDraft? {
            // Ответ без текста — черновик (так сохраняет и веб). Вложения сервера ядро держит только в `raw`.
            if (draft.text.isBlank() && draft.replyTo == null) return null
            return ChatDraft(
                text = draft.text,
                updatedAtMs = draft.updateTime,
                formatting = TextMarks.fromElements(draft.elements, draft.text.length),
                replyTo = draft.replyTo?.toString(),
            )
        }
    }
}
