package app.maxly.data

import app.maxly.domain.AppFont
import app.maxly.domain.AppearancePreferences
import app.maxly.domain.FontWeightScale
import app.maxly.domain.ChatWallpaper
import app.maxly.domain.TextSizeStep
import app.maxly.domain.ThemeMode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Где лежат настройки оформления: строки по ключам. */
interface PreferenceStore {
    fun get(key: String): String?
    fun put(key: String, value: String)

    /** Убрать ключ. Хранилище без удаления пишет пустую строку: её никто не читает как значение. */
    fun remove(key: String) = put(key, "")
}

/** Размер текста, шрифт, тема и обои: общие для всех аккаунтов на устройстве. */
class AppearanceSettings(private val store: PreferenceStore) {
    private val _state = MutableStateFlow(load())
    val state: StateFlow<AppearancePreferences> = _state.asStateFlow()

    fun setTextSize(step: TextSizeStep) = change { it.copy(textSize = step) }
    fun setTheme(mode: ThemeMode) = change { it.copy(theme = mode) }
    fun setWallpaper(choice: ChatWallpaper) = change { it.copy(wallpaper = choice) }
    fun setFont(font: AppFont) = change { it.copy(font = font) }
    fun setFontWeight(weight: Int) = change { it.copy(fontWeight = FontWeightScale.clamp(weight)) }

    private fun change(transform: (AppearancePreferences) -> AppearancePreferences) {
        _state.update(transform)
        val value = _state.value
        store.put(KEY_TEXT, value.textSize.name)
        store.put(KEY_THEME, value.theme.name)
        store.put(KEY_WALLPAPER, value.wallpaper.name)
        store.put(KEY_FONT, value.font.name)
        store.put(KEY_WEIGHT, value.fontWeight.toString())
    }

    private fun load() = AppearancePreferences(
        textSize = store.get(KEY_TEXT)?.let { runCatching { TextSizeStep.valueOf(it) }.getOrNull() } ?: TextSizeStep.STANDARD,
        theme = store.get(KEY_THEME)?.let { runCatching { ThemeMode.valueOf(it) }.getOrNull() } ?: ThemeMode.SYSTEM,
        wallpaper = store.get(KEY_WALLPAPER)?.let { runCatching { ChatWallpaper.valueOf(it) }.getOrNull() } ?: ChatWallpaper.PLAIN,
        font = store.get(KEY_FONT)?.let { runCatching { AppFont.valueOf(it) }.getOrNull() } ?: AppFont.SYSTEM,
        fontWeight = store.get(KEY_WEIGHT)?.toIntOrNull()?.let(FontWeightScale::clamp) ?: FontWeightScale.DEFAULT,
    )

    private companion object {
        const val KEY_TEXT = "appearance.textSize"
        const val KEY_THEME = "appearance.theme"
        const val KEY_WALLPAPER = "appearance.wallpaper"
        const val KEY_FONT = "appearance.font"
        const val KEY_WEIGHT = "appearance.fontWeight"
    }
}
