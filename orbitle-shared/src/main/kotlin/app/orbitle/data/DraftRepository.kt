package app.orbitle.data

import app.orbitle.domain.ChatDraft
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
        MaxCoreGateway.call {
            client.saveDraft(id, draft.text, TextMarks.toElements(draft.text, draft.formatting), draft.replyTo?.toLongOrNull())
        }
    }

    override suspend fun discard(chatId: String) {
        val id = chatId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.discardDraft(id) }
    }

    private fun draft(draft: com.max.core.api.MaxDraft): ChatDraft? {
        if (draft.text.isBlank()) return null
        return ChatDraft(
            text = draft.text,
            updatedAtMs = draft.updateTime,
            formatting = TextMarks.fromElements(draft.elements.filter { it.fits(draft.text.length) }),
            replyTo = draft.replyTo?.toString(),
        )
    }
}
