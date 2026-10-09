package app.maxly.presentation.chat

import app.maxly.data.MessageRepository
import app.maxly.domain.Message
import app.maxly.domain.MessageReaction
import app.maxly.domain.ReactionUser
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ReactionUsersState(
    val users: List<ReactionUser> = emptyList(),
    val phase: Phase = Phase.Loading,
    /** Показать только поставивших эту реакцию, `null` — всех. */
    val filter: String? = null,
) {
    enum class Phase { Loading, Loaded, Failed }

    val visible: List<ReactionUser> get() = filter?.let { f -> users.filter { it.emoji == f } } ?: users
    val emptyText: String? get() = if (phase == Phase.Loaded && visible.isEmpty()) "Никто не отреагировал" else null
}

/** «Кто отреагировал» для одного сообщения, с отбором по реакции. */
class ReactionUsersModel(
    private val chatId: String,
    val message: Message,
    private val repository: MessageRepository,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow(ReactionUsersState())
    val state: StateFlow<ReactionUsersState> = _state.asStateFlow()

    /** Вкладки отбора: реакции сообщения в его порядке, с числом. */
    val tabs: List<MessageReaction> get() = message.content.reactions

    val title: String
        get() {
            val total = message.content.reactions.sumOf { it.count }
            return if (total > 0) "Реакции: $total" else "Реакции"
        }

    fun load() {
        _state.update { it.copy(phase = ReactionUsersState.Phase.Loading) }
        scope.launch {
            try {
                val users = repository.reactionUsers(chatId, message.id)
                _state.update { it.copy(users = users, phase = ReactionUsersState.Phase.Loaded) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _state.update { it.copy(phase = ReactionUsersState.Phase.Failed) }
            }
        }
    }

    fun select(emoji: String?) = _state.update { it.copy(filter = emoji) }

    companion object {
        /** Имя строки: без профиля — «Пользователь» и id. */
        fun name(user: ReactionUser): String = user.name.trim().ifEmpty { "Пользователь ${user.userId}" }
    }
}
