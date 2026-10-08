package app.orbitle.data

import app.orbitle.domain.ChatDraft
import app.orbitle.domain.TextSpans
import com.max.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Черновики на сервере: видны на всех устройствах аккаунта. */
interface DraftRepository {
    /** Черновики по id чата. */
    val drafts: Flow<Map<String, ChatDraft>>

    /** Черновик чата сейчас. */
    fun current(chatId: String): ChatDraft?

    suspend fun save(chatId: String, draft: ChatDraft)

    suspend fun discard(chatId: String)
}

/** Черновики ядра ([MaxClient.drafts]): приходят с `LOGIN`, меняются через [MaxClient.saveDraft]. */
class CoreDraftRepository(private val client: MaxClient) : DraftRepository {
    override val drafts: Flow<Map<String, ChatDraft>> = client.store.state
        .map { state -> state.drafts }
        .distinctUntilChanged()
        .map { drafts -> drafts.entries.mapNotNull { (id, draft) -> draft(draft)?.let { id.toString() to it } }.toMap() }

    override fun current(chatId: String): ChatDraft? {
        val id = chatId.toLongOrNull() ?: return null
        return client.drafts[id]?.let(::draft)
    }

    override suspend fun save(chatId: String, draft: ChatDraft) {
        val id = chatId.toLongOrNull() ?: return
        val request = request(draft)
        MaxCoreGateway.call { client.saveDraft(id, request.text, request.elements, request.replyTo) }
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
