package app.orbitle.presentation.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.ChatAdminRepository
import app.orbitle.data.ChatAdminSnapshot
import app.orbitle.data.ChatPerson
import app.orbitle.data.CoreErrors
import app.orbitle.data.GroupOption
import app.orbitle.domain.OrbitleError
import app.orbitle.presentation.common.PresenceText
import app.orbitle.presentation.settings.ProfileLink
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ChatManageState(
    val title: String = "",
    val description: String = "",
    val link: String? = null,
    val qr: List<BooleanArray> = emptyList(),
    val isChannel: Boolean = false,
    val commentsEnabled: Boolean? = null,
    val onlyOwnerRenames: Boolean = false,
    val allCanPin: Boolean = false,
    val onlyAdminAdds: Boolean = false,
    val onlyAdminCalls: Boolean = false,
    val membersSeeLink: Boolean = false,
    val ownerId: String? = null,
    val selfId: String? = null,
    val members: List<ChatPerson> = emptyList(),
    /** «в сети» или «был(а)…» участников по id; без записи — ничего не известно. */
    val memberPresence: Map<String, String> = emptyMap(),
    val requests: List<ChatPerson> = emptyList(),
    val busy: Boolean = false,
    val message: String? = null,
) {
    fun role(id: String): ChatPerson.Role = members.firstOrNull { it.id == id }?.role ?: ChatPerson.Role.MEMBER
}

/**
 * Экран управления группой или каналом. Карточка, фото, участники, админы, ссылка,
 * заявки, права и комментарии канала. Владельца удалить нельзя.
 */
class ChatManageViewModel(
    private val chatId: String,
    val isChannel: Boolean,
    private val selfId: String?,
    private val repository: ChatAdminRepository,
    private val now: () -> Long = System::currentTimeMillis,
    private val presenceText: PresenceText = PresenceText(),
) : ViewModel() {
    private val _state = MutableStateFlow(ChatManageState(isChannel = isChannel, selfId = selfId))
    val state: StateFlow<ChatManageState> = _state.asStateFlow()

    /** Участники постранично и поиск; загруженные страницы — и в [ChatManageState.members]. */
    val memberList = MemberList(viewModelScope, repository, chatId)

    init {
        viewModelScope.launch {
            memberList.state.collect { list -> _state.update { it.copy(members = list.members, memberPresence = presenceOf(list.members)) } }
        }
    }

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(busy = true) }
            try {
                val card = repository.snapshot(chatId)
                val requests = runCatching { repository.joinRequests(chatId) }.getOrDefault(emptyList())
                _state.value = stateOf(card, memberList.state.value.members, requests)
                memberList.load()
            } catch (e: Throwable) {
                fail(e, "Не удалось открыть управление")
                _state.update { it.copy(busy = false) }
            }
        }
    }

    fun editTitle(value: String) = _state.update { it.copy(title = value) }
    fun editDescription(value: String) = _state.update { it.copy(description = value) }
    fun dismissMessage() = _state.update { it.copy(message = null) }

    fun saveCard() = work("Не удалось сохранить") {
        val current = _state.value
        repository.saveCard(chatId, current.title.trim(), current.description.trim())
        "Сохранено"
    }

    fun setPhoto(jpeg: ByteArray) = work("Не удалось загрузить фото") {
        repository.setPhoto(chatId, jpeg)
        "Фото обновлено"
    }

    fun revokeLink() = work("Не удалось обновить ссылку") {
        val link = repository.revokeInviteLink(chatId)
        if (link != null) _state.update { it.copy(link = link, qr = qr(link)) }
        "Ссылка обновлена"
    }

    fun setComments(enabled: Boolean) = work("Не удалось изменить комментарии") {
        repository.setComments(chatId, enabled)
        _state.update { it.copy(commentsEnabled = enabled) }
        if (enabled) "Комментарии включены" else "Комментарии выключены"
    }

    fun setOption(option: GroupOption, enabled: Boolean) = work("Не удалось изменить права") {
        repository.setOption(chatId, option, enabled)
        _state.update { it.withOption(option, enabled) }
        "Права обновлены"
    }

    fun addMember(userId: String) = work("Не удалось добавить") {
        repository.addMembers(chatId, listOf(userId))
        reloadPeople()
        "Участник добавлен"
    }

    fun removeMember(userId: String) = work("Не удалось удалить") {
        if (userId == _state.value.ownerId) {
            "Владельца удалить нельзя"
        } else {
            repository.removeMember(chatId, userId)
            reloadPeople()
            "Участник удалён"
        }
    }

    fun setAdmin(userId: String, admin: Boolean) = work("Не удалось изменить права") {
        if (userId == _state.value.ownerId) {
            "Владелец уже управляет чатом"
        } else {
            repository.setAdmin(chatId, userId, admin)
            reloadPeople()
            if (admin) "Назначен админ" else "Админ снят"
        }
    }

    fun decideRequest(userId: String, accept: Boolean) = work("Не удалось разобрать заявку") {
        repository.decideJoinRequest(chatId, userId, accept)
        reloadPeople()
        if (accept) "Заявка принята" else "Заявка отклонена"
    }

    fun blockCommentAuthor(postId: String, userId: String, messageId: String) = work("Не удалось заблокировать") {
        repository.blockCommentAuthor(chatId, postId, userId, messageId)
        "Автор комментария заблокирован"
    }

    private fun work(fallback: String, body: suspend () -> String) {
        if (_state.value.busy) return
        viewModelScope.launch {
            _state.update { it.copy(busy = true, message = null) }
            try {
                val text = body()
                _state.update { it.copy(busy = false, message = text) }
            } catch (e: Throwable) {
                fail(e, fallback)
                _state.update { it.copy(busy = false) }
            }
        }
    }

    private suspend fun reloadPeople() {
        memberList.load()
        val requests = runCatching { repository.joinRequests(chatId) }.getOrDefault(_state.value.requests)
        _state.update { it.copy(requests = requests) }
    }

    private fun stateOf(card: ChatAdminSnapshot, members: List<ChatPerson>, requests: List<ChatPerson>) = ChatManageState(
        title = card.title,
        description = card.description,
        link = card.link,
        qr = card.link?.let(::qr).orEmpty(),
        isChannel = isChannel,
        commentsEnabled = card.commentsEnabled,
        onlyOwnerRenames = card.onlyOwnerCanChangeIconTitle,
        allCanPin = card.allCanPinMessage,
        onlyAdminAdds = card.onlyAdminCanAddMember,
        onlyAdminCalls = card.onlyAdminCanCall,
        membersSeeLink = card.membersCanSeePrivateLink,
        ownerId = card.ownerId,
        selfId = selfId,
        members = members,
        memberPresence = presenceOf(members),
        requests = requests,
    )

    private fun presenceOf(members: List<ChatPerson>): Map<String, String> {
        val at = now()
        return members.mapNotNull { m -> presenceText.status(m.isOnline, m.lastSeenMs, at, m.presence)?.let { m.id to it } }.toMap()
    }

    private fun fail(error: Throwable, fallback: String) {
        val mapped = CoreErrors.map(error)
        if (mapped == OrbitleError.Cancelled) return
        val text = if (mapped == OrbitleError.Unknown) fallback else mapped.message ?: fallback
        _state.update { it.copy(message = text) }
    }

    private fun qr(link: String) = runCatching { ProfileLink.qr(absolute(link)) }.getOrDefault(emptyList())

    companion object {
        /** Относительный `join/...` становится адресом, который можно показать кодом. */
        fun absolute(link: String): String {
            val trimmed = link.trim()
            if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) return trimmed
            return "https://max.ru/" + trimmed.removePrefix("/")
        }
    }
}

private fun ChatManageState.withOption(option: GroupOption, enabled: Boolean) = when (option) {
    GroupOption.ONLY_OWNER_RENAMES -> copy(onlyOwnerRenames = enabled)
    GroupOption.ALL_CAN_PIN -> copy(allCanPin = enabled)
    GroupOption.ONLY_ADMIN_ADDS -> copy(onlyAdminAdds = enabled)
    GroupOption.ONLY_ADMIN_CALLS -> copy(onlyAdminCalls = enabled)
    GroupOption.MEMBERS_SEE_LINK -> copy(membersSeeLink = enabled)
}
