package app.maxly.data

import app.maxly.domain.ChatWallpaperChoice
import app.maxly.domain.ResolvedWallpaper
import app.maxly.domain.WallpaperPhoto
import app.maxly.domain.WallpaperScale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File

/**
 * Своё фото на обоях: общее для всех чатов («Оформление» → «Обои чата») и своё у чата («Обои» в
 * профиле). Хранится только на устройстве: на сервер ничего не уходит. Копии фото лежат в [dir];
 * при замене и сбросе старая копия удаляется. Обои чата — по ключу аккаунт + чат, и они важнее
 * общих.
 */
class WallpaperPhotoSettings(private val store: PreferenceStore, private val dir: File) {
    /** Общие настройки и номер изменения: экраны перечитывают [resolve], когда он меняется. */
    data class State(
        val global: String? = null,
        val dimPercent: Int = 0,
        val blur: Boolean = false,
        val revision: Int = 0,
    ) {
        val globalPhoto: WallpaperPhoto? get() = global?.let { WallpaperPhoto(it, dimPercent, blur) }
    }

    private val _state = MutableStateFlow(load(0))
    val state: StateFlow<State> = _state.asStateFlow()

    /** Новый файл для копии в [dir]: имя уникально, чтобы кэш картинок не отдал старую. */
    fun newFile(): File {
        dir.mkdirs()
        return File(dir, "wallpaper-${System.currentTimeMillis()}-${(Math.random() * 1e6).toLong()}.jpg")
    }

    fun setGlobal(path: String) {
        val old = store.get(KEY_GLOBAL)
        store.put(KEY_GLOBAL, path)
        if (old != path) deleteFile(old)
        publish()
    }

    /** «Сбросить» в «Оформлении»: фото убирается, остаются обои из набора. */
    fun resetGlobal() {
        val old = store.get(KEY_GLOBAL)
        store.remove(KEY_GLOBAL)
        deleteFile(old)
        publish()
    }

    fun setDim(percent: Int) {
        store.put(KEY_DIM, WallpaperScale.clampDim(percent).toString())
        publish()
    }

    fun setBlur(blur: Boolean) {
        store.put(KEY_BLUR, blur.toString())
        publish()
    }

    fun chatChoice(account: String, chatId: String): ChatWallpaperChoice = when (val value = store.get(chatKey(account, chatId))) {
        null, "" -> ChatWallpaperChoice.Global
        PLAIN -> ChatWallpaperChoice.Plain
        else -> ChatWallpaperChoice.Photo(value)
    }

    fun setChat(account: String, chatId: String, choice: ChatWallpaperChoice) {
        val key = chatKey(account, chatId)
        val old = (chatChoice(account, chatId) as? ChatWallpaperChoice.Photo)?.path
        when (choice) {
            ChatWallpaperChoice.Global -> store.remove(key)
            ChatWallpaperChoice.Plain -> store.put(key, PLAIN)
            is ChatWallpaperChoice.Photo -> store.put(key, choice.path)
        }
        if (old != (choice as? ChatWallpaperChoice.Photo)?.path) deleteFile(old)
        publish()
    }

    /** Обои чата: своё фото чата, затем «Без обоев» чата, затем общее фото, иначе набор. */
    fun resolve(account: String, chatId: String?): ResolvedWallpaper {
        val state = _state.value
        val choice = chatId?.let { chatChoice(account, it) } ?: ChatWallpaperChoice.Global
        return when (choice) {
            is ChatWallpaperChoice.Photo -> ResolvedWallpaper.Photo(WallpaperPhoto(choice.path, state.dimPercent, state.blur))
            ChatWallpaperChoice.Plain -> ResolvedWallpaper.Plain
            ChatWallpaperChoice.Global -> state.globalPhoto?.let { ResolvedWallpaper.Photo(it) } ?: ResolvedWallpaper.Preset
        }
    }

    /** Удаляет только свои копии из [dir]: чужой путь в настройках файл пользователя не тронет. */
    private fun deleteFile(path: String?) {
        if (path.isNullOrEmpty()) return
        val file = File(path)
        val inside = runCatching { file.canonicalFile.parentFile == dir.canonicalFile }.getOrDefault(false)
        if (inside) file.delete()
    }

    private fun publish() {
        _state.value = load(_state.value.revision + 1)
    }

    private fun load(revision: Int) = State(
        global = store.get(KEY_GLOBAL)?.takeIf { it.isNotEmpty() },
        dimPercent = store.get(KEY_DIM)?.toIntOrNull()?.let(WallpaperScale::clampDim) ?: 0,
        blur = store.get(KEY_BLUR) == "true",
        revision = revision,
    )

    companion object {
        const val KEY_GLOBAL = "wallpaper.photo.global"
        const val KEY_DIM = "wallpaper.photo.dim"
        const val KEY_BLUR = "wallpaper.photo.blur"
        private const val PLAIN = "plain"

        fun chatKey(account: String, chatId: String) = "wallpaper.photo.chat.$account.$chatId"
    }
}
