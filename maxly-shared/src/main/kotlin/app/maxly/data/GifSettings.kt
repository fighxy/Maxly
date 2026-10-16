package app.maxly.data

import app.maxly.domain.GifAutoplay
import app.maxly.domain.GifPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Настройки гифок устройства. Поиск gifka.me включается только явно. */
class GifSettings(private val store: PreferenceStore) {
    private val _state = MutableStateFlow(load())
    val state: StateFlow<GifPreferences> = _state.asStateFlow()

    fun setAutoplay(mode: GifAutoplay) = change { it.copy(autoplay = mode) }
    fun setGifkaSearch(enabled: Boolean) = change { it.copy(gifkaSearch = enabled) }

    private fun change(transform: (GifPreferences) -> GifPreferences) {
        _state.update(transform)
        val value = _state.value
        store.put(KEY_AUTOPLAY, value.autoplay.raw)
        store.put(KEY_GIFKA, value.gifkaSearch.toString())
    }

    private fun load() = GifPreferences(
        autoplay = GifAutoplay.entries.firstOrNull { it.raw == store.get(KEY_AUTOPLAY) } ?: GifAutoplay.ALWAYS,
        gifkaSearch = store.get(KEY_GIFKA) == "true",
    )

    companion object {
        const val KEY_AUTOPLAY = "gifs.autoplay"
        const val KEY_GIFKA = "gifs.gifkaSearch"

        private val GifAutoplay.raw: String
            get() = when (this) {
                GifAutoplay.ALWAYS -> "always"
                GifAutoplay.WIFI_ONLY -> "wifi"
                GifAutoplay.NEVER -> "never"
            }

        /** Играть ли гифку сама: «Только по Wi‑Fi» без безлимитной сети — нет. */
        fun shouldAutoplay(mode: GifAutoplay, unmetered: Boolean): Boolean = when (mode) {
            GifAutoplay.ALWAYS -> true
            GifAutoplay.WIFI_ONLY -> unmetered
            GifAutoplay.NEVER -> false
        }

        /** Показывать ли вкладку поиска: только если пользователь включил gifka.me. */
        fun searchAvailable(prefs: GifPreferences): Boolean = prefs.gifkaSearch

        /** Отправка результата gifka.me требует ключа API: без него GIF-файл не скачать. */
        fun canSendFromGifka(apiKey: String): Boolean = apiKey.isNotBlank()
    }
}
