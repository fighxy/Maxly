package app.maxly.presentation.chatlist

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.maxly.data.ChatRepository
import app.maxly.data.ContactRepository
import app.maxly.data.CoreFailure
import app.maxly.domain.Contact
import app.maxly.presentation.contacts.ContactsViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Шаг листа «новое сообщение». */
enum class NewChatStep { MENU, CONTACT, PHONE, GROUP, CHANNEL, LINK }

/** Человек, найденный по номеру. В контакты сам не попадает. */
data class NewPerson(val id: String, val title: String, val phone: String, val added: Boolean = false)

/** Чат, который только что создали или открыли. Интерфейс забирает его один раз. */
data class OpenedChat(val id: String, val title: String)

data class NewChatUiState(
    val visible: Boolean = false,
    val step: NewChatStep = NewChatStep.MENU,
    val people: List<Contact> = emptyList(),
    val query: String = "",
    val phone: String = "",
    val title: String = "",
    val selected: List<String> = emptyList(),
    val found: NewPerson? = null,
    /** Имя, с которым записать найденного человека. Пустое на сервер не уходит. */
    val contactName: String = "",
    val link: String = "",
    val busy: Boolean = false,
    val error: String? = null,
    val notice: String? = null,
    val opened: OpenedChat? = null,
)

/**
 * Написать контакту, найти человека по номеру, создать группу или канал.
 * Личный чат — исключающее «или» двух id: сервер создаёт диалог первым сообщением.
 */
class NewChatModel(
    private val contacts: ContactRepository,
    private val chats: ChatRepository,
    private val currentUserId: () -> String?,
) : ViewModel() {
    private val _state = MutableStateFlow(NewChatUiState())
    val state: StateFlow<NewChatUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            contacts.contacts.collect { list ->
                val me = currentUserId()
                val people = list.filter { it.id != me }
                    .sortedWith { a, b -> ContactsViewModel.compare(a.displayName, b.displayName) }
                _state.update { it.copy(people = people) }
            }
        }
    }

    fun show() {
        _state.update { NewChatUiState(visible = true, people = it.people) }
    }

    fun dismiss() {
        _state.update { it.copy(visible = false, busy = false) }
    }

    fun back() {
        _state.update { it.copy(step = NewChatStep.MENU, error = null, busy = false) }
    }

    fun open(step: NewChatStep) {
        _state.update { it.copy(step = step, error = null, notice = null) }
    }

    fun setQuery(value: String) = _state.update { it.copy(query = value) }

    fun setContactName(value: String) = _state.update { it.copy(contactName = value.take(TITLE_LIMIT)) }

    fun setLink(value: String) = _state.update { it.copy(link = value, error = null) }

    fun setPhone(value: String) {
        _state.update { it.copy(phone = value, error = null, found = null, notice = null) }
    }

    /** Длина поля, не правило протокола: сервер свой предел не публикует. */
    fun setTitle(value: String) {
        _state.update { it.copy(title = value.take(TITLE_LIMIT), error = null) }
    }

    fun toggleMember(id: String) {
        _state.update { state ->
            val selected = if (id in state.selected) state.selected - id else state.selected + id
            state.copy(selected = selected)
        }
    }

    fun consumeOpened() {
        _state.update { it.copy(opened = null, visible = false, step = NewChatStep.MENU, busy = false) }
    }

    /** Контакт из списка: чат открывается сразу, строка списка ставится локально. */
    fun writeTo(personId: String, title: String) {
        if (_state.value.busy) return
        val chatId = dialogId(currentUserId(), personId)
        if (chatId == null) {
            _state.update { it.copy(error = "Не удалось открыть чат") }
            return
        }
        val name = title.trim().ifEmpty { "Чат" }
        viewModelScope.launch {
            _state.update { it.copy(busy = true, error = null) }
            try {
                try {
                    chats.prepareDialog(chatId, personId, name)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    // Диалог всё равно откроется: сервер создаст его первым сообщением.
                }
                _state.update { it.copy(busy = false, opened = OpenedChat(chatId, name)) }
            } catch (e: CancellationException) {
                throw e
            }
        }
    }

    fun lookup() {
        if (_state.value.busy) return
        val payload = phonePayload(_state.value.phone)
        if (payload == null) {
            _state.update { it.copy(error = "Номер слишком короткий", found = null, notice = null) }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(busy = true, error = null, found = null, notice = null) }
            try {
                val contact = contacts.findByPhone(payload)
                if (contact == null || contact.id.isBlank()) {
                    _state.update { it.copy(busy = false, error = "Человек с таким номером не найден") }
                } else {
                    val phone = contact.phone.ifBlank { payload }
                    _state.update { it.copy(busy = false, found = NewPerson(contact.id, contact.displayName, phone)) }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: CoreFailure) {
                val text = if (isMissingPerson(e)) "Человек с таким номером не найден" else "Не удалось найти человека"
                _state.update { it.copy(busy = false, error = text) }
            } catch (_: Exception) {
                _state.update { it.copy(busy = false, error = "Не удалось найти человека") }
            }
        }
    }

    /** Написать найденному. В контакты это не добавляет. */
    fun writeFound() {
        val person = _state.value.found ?: return
        writeTo(person.id, person.title)
    }

    /** Отдельное действие: записать найденного в контакты. Неудача не мешает написать. */
    fun addFound() {
        val person = _state.value.found ?: return
        if (person.added || _state.value.busy) return
        viewModelScope.launch {
            _state.update { it.copy(busy = true, error = null) }
            try {
                val saved = contacts.add(person.id, _state.value.contactName)
                _state.update { state ->
                    val current = state.found
                    if (saved == null || current?.id != person.id) {
                        state.copy(busy = false, error = "Не удалось добавить в контакты")
                    } else {
                        state.copy(busy = false, found = current.copy(added = true), notice = "Добавлен в контакты")
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _state.update { it.copy(busy = false, error = "Не удалось добавить в контакты") }
            }
        }
    }

    fun createGroup() {
        val name = _state.value.title.trim()
        if (name.isEmpty()) {
            _state.update { it.copy(error = "Введите название") }
            return
        }
        if (_state.value.busy) return
        val me = currentUserId()
        val ids = _state.value.selected.filter { it != me }
        launchCreate("Не удалось создать группу", name) { chats.createGroup(name, ids) }
    }

    fun createChannel() {
        val name = _state.value.title.trim()
        if (name.isEmpty()) {
            _state.update { it.copy(error = "Введите название") }
            return
        }
        if (_state.value.busy) return
        launchCreate("Не удалось создать канал", name) { chats.createChannel(name) }
    }

    /** Войти по ссылке приглашения. Чат открывается, если сервер его вернул. */
    fun joinLink() {
        val link = _state.value.link.trim()
        if (link.isEmpty()) {
            _state.update { it.copy(error = "Вставьте ссылку") }
            return
        }
        if (_state.value.busy) return
        launchCreate("Не удалось открыть ссылку", link) { chats.joinByLink(link) }
    }

    private fun launchCreate(failure: String, title: String, block: suspend () -> String?) {
        viewModelScope.launch {
            _state.update { it.copy(busy = true, error = null) }
            try {
                val id = block()
                if (id.isNullOrBlank()) {
                    _state.update { it.copy(busy = false, error = failure) }
                } else {
                    _state.update { it.copy(busy = false, opened = OpenedChat(id, title)) }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _state.update { it.copy(busy = false, error = failure) }
            }
        }
    }

    companion object {
        /** Сколько символов пускает поле названия. Протокол свою длину не задаёт. */
        const val TITLE_LIMIT = 200

        /** `+` и только цифры. Короче семи цифр запрос не уходит. */
        fun phonePayload(raw: String): String? {
            val digits = raw.filter { it.isDigit() }
            if (digits.length < ContactRepository.MIN_PHONE_DIGITS) return null
            return "+$digits"
        }

        /** Id личного чата: исключающее «или» двух пользователей. Отдельного opcode создания нет. */
        fun dialogId(me: String?, other: String): String? {
            val first = me?.toLongOrNull() ?: return null
            val second = other.toLongOrNull() ?: return null
            return (first xor second).toString()
        }

        /** Сервер не нашёл человека или ответ без контакта. */
        fun isMissingPerson(failure: CoreFailure): Boolean {
            if (failure.kind == "NOT_FOUND" || failure.kind == "MALFORMED_REPLY") return true
            val key = failure.key?.lowercase().orEmpty()
            return "not.found" in key || "not_found" in key
        }
    }
}
