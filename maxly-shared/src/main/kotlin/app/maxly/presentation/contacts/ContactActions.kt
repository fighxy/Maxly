package app.maxly.presentation.contacts

import app.maxly.data.ContactRepository
import app.maxly.data.CoreErrors
import app.maxly.domain.Contact
import com.maxly.core.api.PhoneNumbers
import com.maxly.core.api.UsersApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Открытый диалог действий с контактом. */
sealed interface ContactDialog {
    /**
     * «Изменить контакт»: своё имя контакта (`CUSTOM`), а не имя, которое указал человек.
     * Нет своего имени — поля пустые. Два пустых поля возвращают имя человека.
     */
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
    /** Контакт только что удалён: снекбар «Контакт удалён» с «Отменить». Один за раз. */
    val undo: PendingUndo? = null,
)

/**
 * Удалённый контакт, который ещё можно вернуть. [token] отличает одно удаление от другого.
 * [customFirstName] и [customLastName] — своё имя контакта до удаления (не показанное имя).
 */
data class PendingUndo(
    val token: Long,
    val userId: String,
    val name: String,
    val customFirstName: String,
    val customLastName: String,
) {
    val hasCustomName: Boolean get() = customFirstName.isNotBlank() || customLastName.isNotBlank()

    companion object {
        const val TEXT = "Контакт удалён"
        const val ACTION = "Отменить"
    }
}

/** Какие действия с контактом показать в профиле. */
enum class ProfileContactAction {
    /** Ничего: сам пользователь, бот, группа, канал, «Избранное». */
    NONE,
    /** «Изменить» в шапке и «Удалить из контактов» внизу. */
    EDIT,
    /** «Добавить в контакты». */
    ADD;

    companion object {
        /**
         * [kind] — вид профиля, [isContact] — человек в контактах, [isSelf] — свой профиль,
         * [isBot] — бот или служебный аккаунт, [loaded] — карточка уже пришла с сервера.
         */
        fun of(
            kind: app.maxly.domain.ChatProfile.Kind,
            isContact: Boolean,
            isSelf: Boolean = false,
            isBot: Boolean = false,
            loaded: Boolean = true,
        ): ProfileContactAction = when {
            kind != app.maxly.domain.ChatProfile.Kind.USER || isSelf || isBot -> NONE
            isContact -> EDIT
            loaded -> ADD
            else -> NONE
        }
    }
}

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

    private var nextToken = 0L

    /** Удаление, которое ещё можно отменить: имя контакта до удаления. */
    private val removing = mutableMapOf<String, Contact>()

    fun askRename(contact: Contact) = open(ContactDialog.Rename(contact.id, contact.customFirstName, contact.customLastName))

    fun askRemove(contact: Contact) {
        removing[contact.id] = contact
        open(ContactDialog.Remove(contact.id, contact.displayName))
    }

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
        val before = removing[dialog.userId]
        run("Не удалось удалить контакт") {
            if (!repository.remove(dialog.userId)) throw unsupported()
            removing.remove(dialog.userId)
            // Новое удаление закрывает прошлое: его уже не отменить, снекбар меняется на новый.
            val undo = PendingUndo(
                token = ++nextToken,
                userId = dialog.userId,
                name = dialog.name,
                customFirstName = before?.customFirstName.orEmpty(),
                customLastName = before?.customLastName.orEmpty(),
            )
            _state.update { it.copy(undo = undo) }
            null
        }
    }

    /** Снекбар удаления скрылся без «Отменить»: удаление окончательное. */
    fun finishUndo(token: Long) {
        _state.update { if (it.undo?.token == token) it.copy(undo = null) else it }
    }

    /**
     * «Отменить» в снекбаре: контакт снова в списке, со своим именем, если оно было. Без своего
     * имени — только добавление, без переименования. Ошибка — в снекбар.
     */
    fun undo(token: Long) {
        val pending = _state.value.undo?.takeIf { it.token == token } ?: return
        _state.update { it.copy(undo = null) }
        scope.launch {
            try {
                repository.add(pending.userId) ?: throw unsupported()
                if (pending.hasCustomName) {
                    repository.rename(pending.userId, pending.customFirstName, pending.customLastName.ifEmpty { null }) ?: throw unsupported()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(notice = errorText(e, "Не удалось вернуть контакт")) }
            }
        }
    }

    /** «Добавить в контакты» из профиля человека, которого в контактах нет. */
    fun add(userId: String) {
        run("Не удалось добавить контакт") {
            val added = repository.add(userId) ?: throw unsupported()
            "${added.displayName} в контактах"
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

    private fun run(fallback: String, body: suspend () -> String?) {
        if (_state.value.busy) return
        _state.update { it.copy(busy = true, error = null) }
        scope.launch {
            try {
                val notice = body()
                _state.update { it.copy(busy = false, dialog = null, notice = notice ?: it.notice) }
            } catch (e: CancellationException) {
                _state.update { it.copy(busy = false) }
                throw e
            } catch (e: Exception) {
                val text = errorText(e, fallback)
                // Без диалога (добавление из профиля) ошибку показывает снекбар.
                _state.update { if (it.dialog == null) it.copy(busy = false, notice = text) else it.copy(busy = false, error = text) }
            }
        }
    }

    private fun errorText(e: Exception, fallback: String): String {
        val mapped = CoreErrors.map(e)
        return if (mapped == app.maxly.domain.MaxlyError.Unknown) fallback else mapped.userMessage?.takeIf { it.isNotBlank() } ?: fallback
    }

    private fun unsupported() = app.maxly.domain.MaxlyError.Rejected("Действие недоступно")
}
