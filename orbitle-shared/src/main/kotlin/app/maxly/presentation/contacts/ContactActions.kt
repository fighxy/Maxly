package app.maxly.presentation.contacts

import app.maxly.data.ContactRepository
import app.maxly.data.CoreErrors
import app.maxly.domain.Contact
import com.max.core.api.PhoneNumbers
import com.max.core.api.UsersApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Открытый диалог действий с контактом. */
sealed interface ContactDialog {
    /** Своё имя контакта: имя и фамилия. */
    data class Rename(val userId: String, val firstName: String, val lastName: String) : ContactDialog

    /** Подтверждение удаления из контактов. */
    data class Remove(val userId: String, val name: String) : ContactDialog

    /** Новый контакт по номеру. */
    data object AddByPhone : ContactDialog
}

data class ContactActionsState(
    val dialog: ContactDialog? = null,
    val busy: Boolean = false,
    /** Ошибка в открытом диалоге. */
    val error: String? = null,
    /** Итог для снекбара. */
    val notice: String? = null,
)

/**
 * Проверка имени контакта до запроса: те же правила, что у сервера. Пустое имя допустимо, как в
 * веб-клиенте: с фамилией сервер показывает собственное имя человека, без обоих — исходное имя.
 */
object ContactNameRules {
    const val MAX = UsersApi.CONTACT_NAME_MAX

    /** Текст ошибки или `null`, если имя годится. */
    fun error(firstName: String, lastName: String): String? = when {
        firstName.trim().length > MAX || lastName.trim().length > MAX -> "Имя и фамилия — не длиннее $MAX символов"
        else -> null
    }

    /** Номер для сервера (`+` и цифры) или `null`, если на телефон не похоже. */
    fun phone(input: String): String? = PhoneNumbers.normalize(input)
}

/**
 * Переименование, удаление и добавление контактов по номеру — общее для списка контактов и
 * профиля. Диалог закрывается, когда сервер ответил успехом; ошибка остаётся в диалоге.
 */
class ContactActions(
    private val scope: CoroutineScope,
    private val repository: ContactRepository,
) {
    private val _state = MutableStateFlow(ContactActionsState())
    val state: StateFlow<ContactActionsState> = _state.asStateFlow()

    fun askRename(contact: Contact) = open(ContactDialog.Rename(contact.id, contact.firstName, contact.lastName))

    fun askRemove(contact: Contact) = open(ContactDialog.Remove(contact.id, contact.displayName))

    fun askAddByPhone() = open(ContactDialog.AddByPhone)

    fun dismiss() {
        if (_state.value.busy) return
        _state.update { it.copy(dialog = null, error = null) }
    }

    fun consumeNotice() = _state.update { it.copy(notice = null) }

    fun rename(firstName: String, lastName: String) {
        val dialog = _state.value.dialog as? ContactDialog.Rename ?: return
        ContactNameRules.error(firstName, lastName)?.let { text -> return _state.update { it.copy(error = text) } }
        run("Не удалось переименовать") {
            repository.rename(dialog.userId, firstName.trim(), lastName.trim().ifEmpty { null }) ?: throw unsupported()
            "Имя контакта изменено"
        }
    }

    fun remove() {
        val dialog = _state.value.dialog as? ContactDialog.Remove ?: return
        run("Не удалось удалить контакт") {
            if (!repository.remove(dialog.userId)) throw unsupported()
            "Контакт удалён"
        }
    }

    fun addByPhone(phone: String, firstName: String, lastName: String) {
        if (_state.value.dialog != ContactDialog.AddByPhone) return
        val number = ContactNameRules.phone(phone) ?: return _state.update { it.copy(error = "Номер не похож на телефон") }
        if (firstName.isNotBlank() || lastName.isNotBlank()) {
            ContactNameRules.error(firstName, lastName)?.let { text -> return _state.update { it.copy(error = text) } }
        }
        run("Не удалось добавить контакт") {
            val added = repository.addByPhone(number, firstName.trim().ifEmpty { null }, lastName.trim().ifEmpty { null }) ?: throw unsupported()
            if (added.isNew) "${added.contact.displayName} в контактах" else "${added.contact.displayName} уже в контактах"
        }
    }

    private fun open(dialog: ContactDialog) {
        if (_state.value.busy) return
        _state.update { it.copy(dialog = dialog, error = null) }
    }

    private fun run(fallback: String, body: suspend () -> String) {
        if (_state.value.busy) return
        _state.update { it.copy(busy = true, error = null) }
        scope.launch {
            try {
                val notice = body()
                _state.update { it.copy(busy = false, dialog = null, notice = notice) }
            } catch (e: CancellationException) {
                _state.update { it.copy(busy = false) }
                throw e
            } catch (e: Exception) {
                val mapped = CoreErrors.map(e)
                val text = if (mapped == app.maxly.domain.OrbitleError.Unknown) fallback else mapped.userMessage?.takeIf { it.isNotBlank() } ?: fallback
                _state.update { it.copy(busy = false, error = text) }
            }
        }
    }

    private fun unsupported() = app.maxly.domain.OrbitleError.Rejected("Действие недоступно")
}
