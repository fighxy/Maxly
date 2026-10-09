package app.maxly.platform

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import java.awt.Desktop
import java.awt.Toolkit
import java.awt.datatransfer.StringSelection
import java.io.File
import java.util.Properties

/** Каталоги десктоп-клиента: кэш рядом с профилем пользователя, не в папке установки. */
object AppPaths {
    private val userHome = File(System.getProperty("user.home"))

    val home: File = File(userHome, ".maxly").apply { mkdirs() }
    val cacheDir: File = File(home, "cache").apply { mkdirs() }
    val prefsFile: File = File(home, "preferences.properties")
    val downloads: File = File(userHome, "Downloads").apply { mkdirs() }
}

/** Небольшой файл настроек с тем же набором операций, что у Android SharedPreferences в контейнере. */
class FilePrefs(private val file: File) {
    private val map = Properties()

    init {
        if (file.isFile) file.inputStream().use { map.load(it) }
    }

    val all: Map<String, Any>
        get() = map.stringPropertyNames().associateWith { map.getProperty(it) }

    fun getString(key: String, default: String?): String? = map.getProperty(key) ?: default

    fun getLong(key: String, default: Long): Long = map.getProperty(key)?.toLongOrNull() ?: default

    fun getStringSet(key: String, default: Set<String>): Set<String> {
        val raw = map.getProperty(key) ?: return default
        if (raw.isEmpty()) return emptySet()
        return raw.split(SET_SEP).toSet()
    }

    fun edit(): Editor = Editor()

    inner class Editor {
        private val puts = linkedMapOf<String, String?>()

        fun putString(key: String, value: String) = apply { puts[key] = value }
        fun putLong(key: String, value: Long) = apply { puts[key] = value.toString() }
        fun putStringSet(key: String, value: Set<String>) = apply { puts[key] = value.joinToString(SET_SEP) }
        fun remove(key: String) = apply { puts[key] = null }

        fun apply() {
            puts.forEach { (key, value) ->
                if (value == null) map.remove(key) else map.setProperty(key, value)
            }
            file.parentFile?.mkdirs()
            file.outputStream().use { map.store(it, "maxly") }
        }
    }

    private companion object {
        const val SET_SEP = "\u001e"
    }
}

/** Открыть ссылку или файл, скопировать текст. Камеры у окна нет: QR читается из текста или картинки. */
object DesktopActions {
    fun open(uri: String) {
        runCatching { Desktop.getDesktop().browse(java.net.URI(uri)) }
    }

    fun openFile(file: File) {
        val desktop = Desktop.getDesktop()
        if (desktop.isSupported(Desktop.Action.OPEN)) {
            runCatching { desktop.open(file) }.onFailure { playExternal(file) }
        } else {
            playExternal(file)
        }
    }

    fun copy(text: String) {
        Toolkit.getDefaultToolkit().systemClipboard.setContents(StringSelection(text), null)
    }

    private fun playExternal(file: File) {
        runCatching {
            ProcessBuilder("ffplay", "-autoexit", "-loglevel", "quiet", file.absolutePath)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start()
        }
    }
}

/**
 * Escape закрывает верхний обработчик, как системная кнопка «назад» на телефоне.
 * Несколько экранов кладут обработчики стопкой, срабатывает последний, и только один раз.
 */
private val backHandlers = ArrayDeque<() -> Unit>()
private var backDispatcherInstalled = false
private val backDispatcher = java.awt.KeyEventDispatcher { event ->
    if (event.id != java.awt.event.KeyEvent.KEY_PRESSED || event.keyCode != java.awt.event.KeyEvent.VK_ESCAPE) {
        return@KeyEventDispatcher false
    }
    val handler = backHandlers.lastOrNull() ?: return@KeyEventDispatcher false
    handler()
    true
}

@Composable
fun BackHandler(enabled: Boolean = true, onBack: () -> Unit) {
    // Место в стопке не меняется от новой лямбды на перерисовке: иначе экран под листом,
    // перерисовавшись, вставал бы сверху и забирал Esc у листа.
    val current = rememberUpdatedState(onBack)
    val entry = remember { { current.value() } }
    DisposableEffect(enabled) {
        if (enabled) backHandlers.addLast(entry)
        val manager = java.awt.KeyboardFocusManager.getCurrentKeyboardFocusManager()
        if (!backDispatcherInstalled) {
            manager.addKeyEventDispatcher(backDispatcher)
            backDispatcherInstalled = true
        }
        onDispose {
            if (enabled) backHandlers.remove(entry)
            if (backHandlers.isEmpty() && backDispatcherInstalled) {
                manager.removeKeyEventDispatcher(backDispatcher)
                backDispatcherInstalled = false
            }
        }
    }
}
