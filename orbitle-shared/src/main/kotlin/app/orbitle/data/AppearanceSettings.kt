package app.orbitle.data

import app.orbitle.domain.AppearancePreferences
import app.orbitle.domain.ChatWallpaper
import app.orbitle.domain.TextSizeStep
import app.orbitle.domain.ThemeMode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Где лежат настройки оформления: строки по ключам. */
interface PreferenceStore {
    fun get(key: String): String?
    fun put(key: String, value: String)
}

/** Размер текста, тема и обои: общие для всех аккаунтов на устройстве. */
class AppearanceSettings(private val store: PreferenceStore) {
    private val _state = MutableStateFlow(load())
    val state: StateFlow<AppearancePreferences> = _state.asStateFlow()

    fun setTextSize(step: TextSizeStep) = change { it.copy(textSize = step) }
    fun setTheme(mode: ThemeMode) = change { it.copy(theme = mode) }
    fun setWallpaper(choice: ChatWallpaper) = change { it.copy(wallpaper = choice) }

    private fun change(transform: (AppearancePreferences) -> AppearancePreferences) {
        _state.update(transform)
        val value = _state.value
        store.put(KEY_TEXT, value.textSize.name)
        store.put(KEY_THEME, value.theme.name)
        store.put(KEY_WALLPAPER, value.wallpaper.name)
    }

    private fun load() = AppearancePreferences(
        textSize = store.get(KEY_TEXT)?.let { runCatching { TextSizeStep.valueOf(it) }.getOrNull() } ?: TextSizeStep.STANDARD,
        theme = store.get(KEY_THEME)?.let { runCatching { ThemeMode.valueOf(it) }.getOrNull() } ?: ThemeMode.SYSTEM,
        wallpaper = store.get(KEY_WALLPAPER)?.let { runCatching { ChatWallpaper.valueOf(it) }.getOrNull() } ?: ChatWallpaper.PLAIN,
    )

    private companion object {
        const val KEY_TEXT = "appearance.textSize"
        const val KEY_THEME = "appearance.theme"
        const val KEY_WALLPAPER = "appearance.wallpaper"
    }
}
