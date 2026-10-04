package app.orbitle.data

import app.orbitle.domain.AccountLimits
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Отметка о новом сеансе на устройстве: как и когда вошли и показана ли панель.
 *
 * Лежит в настройках устройства, поэтому панель всплывёт и после перезапуска, если приложение
 * закрыли раньше, чем открылся главный экран. Выход стирает отметку: она про прежний сеанс.
 */
class AccountLimitsStore(
    private val store: PreferenceStore,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val _state = MutableStateFlow(decode(store.get(KEY)))
    val state: StateFlow<AccountLimits?> = _state.asStateFlow()

    /** Вход по коду, паролю или регистрация: новая отметка, панель ещё не показана. */
    fun grant(entry: AccountLimits.Entry) = save(AccountLimits(entry, clock()))

    /** Панель закрыли: повторно сама она не всплывёт. Строка в настройках остаётся, пока срок не вышел. */
    fun markShown() {
        val current = _state.value ?: return
        if (!current.shown) save(current.copy(shown = true))
    }

    fun clear() = save(null)

    private fun save(limits: AccountLimits?) {
        _state.value = limits
        store.put(KEY, encode(limits))
    }

    companion object {
        const val KEY = "accountLimits"

        /** `login 1790000000000 0`: способ входа, время входа в мс, показана ли панель. */
        fun encode(limits: AccountLimits?): String = when (limits) {
            null -> ""
            else -> "${limits.entry.raw} ${limits.grantedAtMs} ${if (limits.shown) 1 else 0}"
        }

        /** Пустое или незнакомое значение — отметки нет. */
        fun decode(value: String?): AccountLimits? {
            val parts = value?.trim()?.split(' ') ?: return null
            if (parts.size != 3) return null
            val entry = AccountLimits.Entry.entries.firstOrNull { it.raw == parts[0] } ?: return null
            val time = parts[1].toLongOrNull() ?: return null
            return AccountLimits(entry, time, shown = parts[2] == "1")
        }

        private val AccountLimits.Entry.raw: String
            get() = when (this) {
                AccountLimits.Entry.LOGIN -> "login"
                AccountLimits.Entry.REGISTRATION -> "registration"
            }
    }
}
