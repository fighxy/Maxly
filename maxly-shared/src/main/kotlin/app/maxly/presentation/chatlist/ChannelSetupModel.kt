package app.maxly.presentation.chatlist

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.maxly.data.ChatAdminRepository
import app.maxly.data.ContactRepository
import app.maxly.data.CoreErrors
import app.maxly.data.MessageRepository
import app.maxly.domain.Contact
import app.maxly.presentation.contacts.ContactsViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Шаг настройки нового канала, как в Max: тип и ссылка, затем подписчики. */
enum class ChannelSetupStep { TYPE, SUBSCRIBERS }

/** Почему публичный канал не сделать здесь: нужен Цифровой ID из мобильного приложения MAX. */
enum class ChannelPublicNotice { PUBLIC, BUSINESS }

data class ChannelSetupState(
    val step: ChannelSetupStep = ChannelSetupStep.TYPE,
    /** Ссылка-приглашение (`https://max.ru/join/…`); `null` — ещё не пришла. */
    val link: String? = null,
    val people: List<Contact> = emptyList(),
    val query: String = "",
    val selected: List<String> = emptyList(),
    val busy: Boolean = false,
    val notice: String? = null,
    /** Окно «Для создания публичного канала нужен Цифровой ID». */
    val publicNotice: ChannelPublicNotice? = null,
    /** Настройка закончена: экран открывает канал. */
    val done: Boolean = false,
) {
    /** Ссылка без схемы, как её пишет Max: `max.ru/join/…`. */
    val shortLink: String? get() = link?.removePrefix("https://")?.removePrefix("http://")

    /** Контакты под строкой поиска «Найти по имени». */
    val shown: List<Contact>
        get() {
            val text = query.trim()
            return if (text.isEmpty()) people else people.filter { it.displayName.contains(text, ignoreCase = true) }
        }
}

/**
 * Настройка только что созданного канала [chatId] — экраны Max «Приватный канал создан» и
 * «Выберите подписчиков». Канал создаётся приватным; публичный требует Цифровой ID, который
 * оформляется только в официальном мобильном приложении, поэтому здесь — лишь объяснение.
 */
class ChannelSetupModel(
    val chatId: String,
    private val admin: ChatAdminRepository,
    private val messages: MessageRepository,
    contacts: ContactRepository,
    private val currentUserId: () -> String?,
) : ViewModel() {
    private val _state = MutableStateFlow(ChannelSetupState())
    val state: StateFlow<ChannelSetupState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            try {
                val link = admin.snapshot(chatId).link
                _state.update { it.copy(link = link) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Без ссылки остаются «Продолжить» и подписчики; ссылку можно сбросить заново.
            }
        }
        viewModelScope.launch {
            contacts.contacts.collect { list ->
                val me = currentUserId()
                val people = list.filter { it.id != me && !it.isBot && !it.isServiceAccount }
                    .sortedWith { a, b -> ContactsViewModel.compare(a.displayName, b.displayName) }
                _state.update { it.copy(people = people) }
            }
        }
    }

    /** «Публичный» или «Публичный для бизнеса»: показать, почему здесь их не включить. */
    fun askPublic(kind: ChannelPublicNotice = ChannelPublicNotice.PUBLIC) = _state.update { it.copy(publicNotice = kind) }

    fun dismissPublic() = _state.update { it.copy(publicNotice = null) }

    /** Ссылка скопирована экраном. */
    fun linkCopied() = notify("Ссылка скопирована")

    /** «Сбросить ссылку»: старая перестаёт работать. */
    fun revokeLink() {
        if (_state.value.busy) return
        launch("Не удалось сбросить ссылку") {
            val link = admin.revokeInviteLink(chatId)
            _state.update { it.copy(link = link ?: it.link, notice = "Ссылка обновлена") }
        }
    }

    /** «Отправить в MAX»: ссылка уходит сообщением в выбранный чат. */
    fun sendLink(targetChatId: String) {
        val link = _state.value.link ?: return
        launch("Не удалось отправить ссылку") {
            messages.send(targetChatId, link, null)
            notify("Ссылка отправлена")
        }
    }

    /** «Продолжить»: к выбору подписчиков. */
    fun next() = _state.update { it.copy(step = ChannelSetupStep.SUBSCRIBERS, notice = null) }

    fun setQuery(value: String) = _state.update { it.copy(query = value) }

    fun toggle(id: String) = _state.update { state ->
        state.copy(selected = if (id in state.selected) state.selected - id else state.selected + id)
    }

    /** «Добавить»: выбранные становятся подписчиками, канал открывается. */
    fun addSubscribers() {
        val ids = _state.value.selected
        if (ids.isEmpty() || _state.value.busy) return
        launch("Не удалось добавить подписчиков") {
            admin.addMembers(chatId, ids)
            _state.update { it.copy(done = true) }
        }
    }

    /** «Отменить»: канал открывается без подписчиков. */
    fun skip() = _state.update { it.copy(done = true) }

    fun consumeNotice() = _state.update { it.copy(notice = null) }

    private fun notify(text: String) = _state.update { it.copy(notice = text) }

    private fun launch(failure: String, block: suspend () -> Unit) {
        viewModelScope.launch {
            _state.update { it.copy(busy = true) }
            try {
                block()
                _state.update { it.copy(busy = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(busy = false, notice = CoreErrors.text(e, failure)) }
            }
        }
    }
}
