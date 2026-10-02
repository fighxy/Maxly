package app.orbitle.data

import app.orbitle.domain.PrivateModeDisplay
import app.orbitle.domain.PrivateModePreferences
import app.orbitle.domain.PrivateModeStyle
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Приватный режим: общий для всех аккаунтов устройства, выход его не сбрасывает. */
class PrivateModeSettings(private val store: PreferenceStore) {
    private val _state = MutableStateFlow(load())
    val state: StateFlow<PrivateModePreferences> = _state.asStateFlow()

    fun setEnabled(enabled: Boolean) = change { it.copy(enabled = enabled) }
    fun toggle() = change { it.copy(enabled = !it.enabled) }
    fun setStyle(style: PrivateModeStyle) = change { it.copy(style = style) }
    fun setQuickToggle(shown: Boolean) = change { it.copy(quickToggle = shown) }

    private fun change(transform: (PrivateModePreferences) -> PrivateModePreferences) {
        _state.update(transform)
        val value = _state.value
        store.put(KEY_ENABLED, value.enabled.toString())
        store.put(KEY_STYLE, value.style.raw)
        store.put(KEY_QUICK, value.quickToggle.toString())
    }

    private fun load() = PrivateModePreferences(
        enabled = store.get(KEY_ENABLED) == "true",
        // Незнакомое значение вида читается как «Заглушки».
        style = PrivateModeStyle.entries.firstOrNull { it.raw == store.get(KEY_STYLE) } ?: PrivateModeStyle.PLACEHOLDER,
        // Нет ключа — кнопка показывается.
        quickToggle = store.get(KEY_QUICK) != "false",
    )

    companion object {
        const val KEY_ENABLED = "privateMode.enabled"
        const val KEY_STYLE = "privateMode.style"
        const val KEY_QUICK = "privateMode.quickToggle"

        private val PrivateModeStyle.raw: String
            get() = when (this) {
                PrivateModeStyle.PLACEHOLDER -> "placeholder"
                PrivateModeStyle.BLUR -> "blur"
            }

        /** Что рисовать вне настроек. Без размытия в системе ([canBlur]) остаются заглушки. */
        fun display(prefs: PrivateModePreferences, canBlur: Boolean = true): PrivateModeDisplay = when {
            !prefs.enabled -> PrivateModeDisplay.VISIBLE
            prefs.style == PrivateModeStyle.BLUR && canBlur -> PrivateModeDisplay.BLUR
            else -> PrivateModeDisplay.PLACEHOLDER
        }
    }
}
