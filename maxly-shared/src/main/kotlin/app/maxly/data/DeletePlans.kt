package app.maxly.data

import app.maxly.domain.DeletePlan
import app.maxly.domain.DeleteScope
import app.maxly.domain.Message
import app.maxly.domain.MessageStatus
import com.maxly.core.api.Chat
import com.maxly.core.api.ChatRights
import com.maxly.core.api.DeleteChatKind
import com.maxly.core.api.MessageDeletion
import com.maxly.core.api.DeletePlan as CorePlan
import com.maxly.core.api.DeleteScope as CoreScope

/**
 * Правила удаления — ядра (общие сценарии `test-fixtures/selection/delete`): ушедшие на сервер
 * сообщения судит [serverPlan] (`MaxClient.deletePlan`: вид чата, свои права в нём, `edit-timeout`),
 * ещё не ушедшие — [MessageDeletion.scope] как неотправленные со своими правами [rights]
 * (`MaxClient.chatRights`), подтверждение целиком — [MessageDeletion.summary]. [chat] — чат из
 * стора ядра, по нему вид чата ([DeleteChatKind.of]).
 */
object DeletePlans {
    fun of(
        chatId: String,
        chat: Chat?,
        rights: ChatRights,
        messages: List<Message>,
        serverPlan: (List<Long>) -> CorePlan,
    ): DeletePlan {
        val id = chatId.toLongOrNull() ?: return DeletePlan.NONE
        val kind = DeleteChatKind.of(id, chat)
        val unique = messages.distinctBy { it.id }
        val serverIds = unique.mapNotNull(::serverId)
        val server = if (serverIds.isEmpty()) emptyMap() else serverPlan(serverIds).scopes
        val scopes = LinkedHashMap<String, CoreScope>()
        for (message in unique) {
            // Неотправленному время и edit-timeout не нужны: решают вид чата и права.
            scopes[message.id] = serverId(message)?.let(server::get) ?: MessageDeletion.scope(
                kind = kind,
                own = true,
                sent = false,
                timeMs = message.timeMs,
                nowMs = message.timeMs,
                editTimeoutSeconds = 0L,
                canDeleteAny = rights.canDeleteAnyMessage,
            )
        }
        val summary = MessageDeletion.summary(kind, scopes.values.withIndex().associate { (index, scope) -> index.toLong() to scope })
        return DeletePlan(
            scopes = scopes.mapValues { (_, scope) -> scopeOf(scope) },
            canDelete = summary.canDelete,
            showsForEveryone = summary.showsForEveryone,
            forEveryoneByDefault = summary.forEveryoneByDefault,
            forcesForEveryone = summary.forcesForEveryone,
        )
    }

    /**
     * Без стора ядра (демо, тесты): ни прав, ни известных сообщений — всё как неотправленное, по
     * виду чата из его id.
     */
    fun withoutStore(chatId: String, messages: List<Message>): DeletePlan {
        val empty = com.maxly.core.state.MaxState()
        return of(chatId, null, ChatRights.NONE, messages) { ids -> MessageDeletion.plan(empty, chatId.toLong(), ids, 0L) }
    }

    /** Id сообщения на сервере; у ещё не ушедшего — `null`. */
    private fun serverId(message: Message): Long? = message.id.toLongOrNull()?.takeIf { message.status == MessageStatus.SENT }

    private fun scopeOf(scope: CoreScope): DeleteScope = when (scope) {
        CoreScope.ALL -> DeleteScope.ALL
        CoreScope.SELF -> DeleteScope.SELF
        CoreScope.NONE -> DeleteScope.NONE
    }
}
