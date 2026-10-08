package app.orbitle.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.AccountRepository
import app.orbitle.data.CoreErrors
import app.orbitle.domain.Account
import app.orbitle.domain.AccountSettings
import app.orbitle.domain.BlockedUser
import app.orbitle.domain.InactiveTtl
import app.orbitle.domain.PrivacyAccess
import app.orbitle.domain.PrivacyChange
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Свой профиль и приватность: правка имени и «О себе», фото, настройки конфига
 * с мгновенным откликом и откатом при ошибке, чёрный список.
 */
class AccountSettingsViewModel(private val repository: AccountRepository) : ViewModel() {

    data class State(
        val account: Account? = null,
        val settings: AccountSettings = AccountSettings(),
        val saving: Boolean = false,
        val updatingPhoto: Boolean = false,
        /** `null`, пока список не загружен. */
        val blocked: List<BlockedUser>? = null,
        val error: String? = null,
        /** Идёт запрос на удаление профиля. */
        val deleting: Boolean = false,
        /** Отказ сервера в удалении: показывается в окне подтверждения, выхода не будет. */
        val deletionError: String? = null,
        /** Сервер принял удаление; экран сообщает об этом и выходит из аккаунта. */
        val deleted: Deletion? = null,
    )

    /** Принятое удаление: [at] — когда профиль удалится (мс), `null`, если сервер не назвал. */
    data class Deletion(val at: Long?)

    private val _state = MutableStateFlow(State())

    val state: StateFlow<State> = _state.asStateFlow()

    init {
        viewModelScope.launch { repository.account.collect { a -> _state.update { it.copy(account = a) } } }
        viewModelScope.launch { repository.settings.collect { s -> _state.update { it.copy(settings = s) } } }
    }

    fun dismissError() = _state.update { it.copy(error = null) }

    /** Ошибка проверки или `null`, если поля можно отправлять. */
    fun validate(firstName: String, lastName: String, about: String): String? = when {
        firstName.isBlank() -> "Укажите имя"
        firstName.trim().length > NAME_LIMIT || lastName.trim().length > NAME_LIMIT -> "Имя и фамилия — не длиннее $NAME_LIMIT символов"
        about.trim().length > ABOUT_LIMIT -> "«О себе» — не длиннее $ABOUT_LIMIT символов"
        else -> null
    }

    /** Сохраняет профиль; [onSaved] вызывается, только если сервер принял изменения. */
    fun saveProfile(firstName: String, lastName: String, about: String, onSaved: () -> Unit) {
        validate(firstName, lastName, about)?.let { message ->
            _state.update { it.copy(error = message) }
            return
        }
        if (_state.value.saving) return
        _state.update { it.copy(saving = true) }
        viewModelScope.launch {
            try {
                repository.updateProfile(firstName.trim(), lastName.trim(), about.trim())
                _state.update { it.copy(saving = false) }
                onSaved()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(saving = false, error = message(e)) }
            }
        }
    }

    fun uploadPhoto(jpeg: ByteArray) = photo("Не удалось загрузить фото") { repository.uploadAvatar(jpeg) }

    fun removePhoto() = photo("Не удалось удалить фото") { repository.removeAvatar() }

    /** Картинку не удалось прочитать или сжать. */
    fun photoUnreadable() = _state.update { it.copy(error = "Не удалось открыть изображение") }

    private fun photo(failure: String, action: suspend () -> Unit) {
        if (_state.value.updatingPhoto) return
        _state.update { it.copy(updatingPhoto = true) }
        viewModelScope.launch {
            try {
                action()
                _state.update { it.copy(updatingPhoto = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(updatingPhoto = false, error = "$failure. ${message(e)}") }
            }
        }
    }

    /**
     * Удаляет профиль, как в приложении для iOS: только если введено слово [DELETE_KEYWORD].
     * Принятый запрос попадает в [State.deleted] с моментом удаления, после чего экран выходит
     * из аккаунта; при ошибке остаётся [State.deletionError], а выхода нет.
     */
    fun deleteAccount(word: String) {
        val now = _state.value
        if (!isDeleteKeyword(word) || now.deleting || now.deleted != null) return
        _state.update { it.copy(deleting = true, deletionError = null) }
        viewModelScope.launch {
            try {
                val at = repository.requestDeletion()
                _state.update { it.copy(deleting = false, deleted = Deletion(at)) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(deleting = false, deletionError = "Не удалось удалить профиль. ${message(e)}") }
            }
        }
    }

    fun dismissDeletionError() = _state.update { it.copy(deletionError = null) }

    /**
     * Сообщение об удалении закрыто: модель живёт дольше сеанса, поэтому после следующего
     * входа окно не должно появиться снова. Затем [logout] завершает сеанс.
     */
    fun finishDeletion(logout: () -> Unit) {
        if (_state.value.deleted == null) return
        _state.update { it.copy(deleted = null) }
        logout()
    }

    fun setPhonePrivacy(access: PrivacyAccess) = change(PrivacyChange.PhonePrivacy(access))
    fun setOnlineHidden(hidden: Boolean) = change(PrivacyChange.OnlineHidden(hidden))
    /** Под семейной защитой безопасный режим не переключается: им управляет тот, кто защищает. */
    fun setSafeMode(enabled: Boolean) {
        val settings = _state.value.settings
        if (settings.safeModeLocked) return
        change(PrivacyChange.SafeMode(enabled))
    }
    fun setSearchByPhone(access: PrivacyAccess) = changeUnlocked(PrivacyChange.SearchByPhone(access))
    fun setIncomingCalls(access: PrivacyAccess) = changeUnlocked(PrivacyChange.IncomingCalls(access))
    fun setChatInvites(access: PrivacyAccess) = changeUnlocked(PrivacyChange.ChatInvites(access))
    fun setSafeContentOnly(safeOnly: Boolean) = changeUnlocked(PrivacyChange.SafeContent(safeOnly))
    fun setInactiveTtl(ttl: InactiveTtl) = change(PrivacyChange.Inactive(ttl))

    /** Быстрая реакция двойного нажатия. Пустую строку сервер не получает. */
    fun setQuickReaction(emoji: String) {
        val clean = emoji.trim()
        if (clean.isEmpty() || clean.length > 32) return
        change(PrivacyChange.QuickReaction(clean))
    }

    /**
     * Пункт, запертый безопасным режимом или семейной защитой: пока замок стоит или конфиг
     * не пришёл, ничего не уходит.
     */
    private fun changeUnlocked(change: PrivacyChange) {
        val settings = _state.value.settings
        if (!settings.known || settings.privacyLocked) return
        change(change)
    }

    /** Сразу показывает новое значение; при ошибке откатывает только его поле. */
    private fun change(change: PrivacyChange) {
        val before = _state.value.settings
        val next = before.applying(change)
        if (next == before) return
        _state.update { it.copy(settings = next) }
        viewModelScope.launch {
            try {
                val saved = repository.change(change)
                _state.update { it.copy(settings = saved) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Только своё поле: остальные могли за это время прийти с сервера.
                _state.update { it.copy(settings = it.settings.restoring(change, before), error = "Не удалось сохранить настройку. ${message(e)}") }
            }
        }
    }

    fun loadBlocked() {
        viewModelScope.launch {
            try {
                val users = repository.blockedUsers()
                _state.update { it.copy(blocked = users) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(blocked = it.blocked ?: emptyList(), error = message(e)) }
            }
        }
    }

    /** Счётчик чёрного списка в «Конфиденциальности»: без окна ошибки, если список не загрузился. */
    fun countBlocked() {
        viewModelScope.launch {
            try {
                val users = repository.blockedUsers()
                _state.update { it.copy(blocked = users) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Без счётчика: строка «Чёрный список» остаётся, список откроется по нажатию.
            }
        }
    }

    /** Убирает из списка сразу и возвращает обратно, если сервер отказал. */
    fun unblock(user: BlockedUser) {
        val before = _state.value.blocked ?: return
        _state.update { it.copy(blocked = before.filterNot { b -> b.id == user.id }) }
        viewModelScope.launch {
            try {
                repository.unblock(user.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { s ->
                    val list = s.blocked.orEmpty()
                    val restored = if (list.any { it.id == user.id }) list else before.filter { b -> b.id == user.id || list.any { it.id == b.id } }
                    s.copy(blocked = restored, error = "Не удалось разблокировать. ${message(e)}")
                }
            }
        }
    }

    private fun message(e: Throwable): String = CoreErrors.map(e).userMessage ?: "Что-то пошло не так"

    companion object {
        const val NAME_LIMIT = 59
        const val ABOUT_LIMIT = 400
        const val DELETE_KEYWORD = "УДАЛИТЬ"

        private val deletionDate = DateTimeFormatter.ofPattern("d MMMM yyyy", Locale.forLanguageTag("ru"))

        /** Введённое слово подтверждает удаление: без учёта регистра и пробелов по краям. */
        fun isDeleteKeyword(word: String): Boolean = word.trim().uppercase() == DELETE_KEYWORD

        /** Текст после принятого удаления: с датой, если сервер её назвал. */
        fun deletionMessage(at: Long?, zone: ZoneId = ZoneId.systemDefault()): String {
            val head = at?.let { "Профиль и переписка удалятся ${deletionDate.format(Instant.ofEpochMilli(it).atZone(zone))}." }
                ?: "Через 30 дней профиль и переписка удалятся навсегда."
            return "$head Если войти раньше, удаление отменится. Сейчас вы выйдете из аккаунта."
        }
    }
}
