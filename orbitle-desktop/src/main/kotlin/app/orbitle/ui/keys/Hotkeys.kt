package app.orbitle.ui.keys

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import java.awt.KeyEventDispatcher
import java.awt.KeyboardFocusManager
import java.awt.event.KeyEvent

/** Что делает горячая клавиша. Кто её выполнит, решают экраны ([HotkeyHandler]). */
enum class HotkeyAction {
    /** Ctrl+F: поиск в открытом чате, без чата — по чатам. */
    SEARCH,
    /** Ctrl+K: поиск по чатам. */
    SEARCH_CHATS,
    /** Ctrl+Tab, Alt+↓, Ctrl+PageDown: следующий чат списка. */
    NEXT_CHAT,
    /** Ctrl+Shift+Tab, Alt+↑, Ctrl+PageUp: предыдущий чат списка. */
    PREVIOUS_CHAT,
    /** Ctrl+1…9: папка по номеру ([Hotkey.index]). */
    FOLDER,
    /** Ctrl+0: «Избранное». */
    SAVED_MESSAGES,
    /** Ctrl+N: новое сообщение. */
    NEW_MESSAGE,
    /** Ctrl+,: настройки. */
    SETTINGS,
    /** Ctrl+Q: выход из приложения. */
    QUIT,
    /** Ctrl+↑: ответить на сообщение выше. */
    REPLY_OLDER,
    /** Ctrl+↓: ответить на сообщение ниже, у последнего — отменить ответ. */
    REPLY_NEWER,
    /** Ctrl+O: прикрепить файл. */
    ATTACH,
    /** PageUp / PageDown: лента на экран вверх или вниз. */
    PAGE_UP,
    PAGE_DOWN,
    /** Ctrl+End: к последнему сообщению. */
    TO_LATEST,
    /** ← / →: соседнее фото или видео в просмотре. */
    VIEWER_PREVIOUS,
    VIEWER_NEXT,
    /** R: повернуть фото в просмотре. */
    ROTATE,
    /** Ctrl+S: сохранить открытое в просмотре. */
    SAVE,
}

/** Сработавшая горячая клавиша; [index] — номер папки у [HotkeyAction.FOLDER]. */
data class Hotkey(val action: HotkeyAction, val index: Int = 0)

/**
 * Сочетание клавиш → действие, в любой раскладке: Ctrl+F и Ctrl+А на русской — одно и то же,
 * как в Telegram Desktop. На Windows код клавиши у русских букв уже латинский (VK_A у «Ф»); на
 * macOS и Linux приходит сама буква, и она переводится в латинскую по месту на клавиатуре
 * (ЙЦУКЕН поверх QWERTY). На macOS вместо Ctrl — ⌘.
 */
object KeyChords {
    /** Латинский знак клавиши, на которой стоит русская буква. */
    private val russian: Map<Char, Char> = run {
        val ru = "йцукенгшщзхъфывапролджэячсмитьбюё"
        val en = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"
        ru.indices.associate { ru[it] to en[it] }
    }

    /** На macOS команды — на ⌘. */
    val isMac: Boolean = System.getProperty("os.name").orEmpty().startsWith("Mac", ignoreCase = true)

    /** Подпись модификатора команд для экрана настроек. */
    val command: String get() = if (isMac) "⌘" else "Ctrl"

    /**
     * Латинский знак нажатой клавиши: буква a–z, цифра или запятая. [keyCode] — код AWT,
     * [extended] — расширенный код (у нелатинских букв это 0x01000000 + Unicode), [char] —
     * напечатанный знак. `null` — клавиша не буквенная или неизвестна.
     */
    fun base(keyCode: Int, extended: Int, char: Char): Char? {
        if (keyCode in KeyEvent.VK_A..KeyEvent.VK_Z) return 'a' + (keyCode - KeyEvent.VK_A)
        if (keyCode in KeyEvent.VK_0..KeyEvent.VK_9) return '0' + (keyCode - KeyEvent.VK_0)
        if (keyCode == KeyEvent.VK_COMMA) return ','
        val unicode = if (extended >= EXTENDED_UNICODE) (extended - EXTENDED_UNICODE).toChar() else char
        return russian[unicode.lowercaseChar()]
    }

    /** Действие сочетания или `null`, если сочетание ничего не значит. */
    fun resolve(keyCode: Int, extended: Int, char: Char, ctrl: Boolean, shift: Boolean, alt: Boolean): Hotkey? {
        val plain = !ctrl && !alt && !shift
        val action = when (keyCode) {
            KeyEvent.VK_TAB -> if (ctrl && !alt) (if (shift) HotkeyAction.PREVIOUS_CHAT else HotkeyAction.NEXT_CHAT) else null
            KeyEvent.VK_UP -> when {
                alt && !ctrl -> HotkeyAction.PREVIOUS_CHAT
                ctrl && !alt -> HotkeyAction.REPLY_OLDER
                else -> null
            }
            KeyEvent.VK_DOWN -> when {
                alt && !ctrl -> HotkeyAction.NEXT_CHAT
                ctrl && !alt -> HotkeyAction.REPLY_NEWER
                else -> null
            }
            KeyEvent.VK_PAGE_UP -> when {
                ctrl -> HotkeyAction.PREVIOUS_CHAT
                plain -> HotkeyAction.PAGE_UP
                else -> null
            }
            KeyEvent.VK_PAGE_DOWN -> when {
                ctrl -> HotkeyAction.NEXT_CHAT
                plain -> HotkeyAction.PAGE_DOWN
                else -> null
            }
            KeyEvent.VK_END -> if (ctrl) HotkeyAction.TO_LATEST else null
            KeyEvent.VK_LEFT -> if (plain) HotkeyAction.VIEWER_PREVIOUS else null
            KeyEvent.VK_RIGHT -> if (plain) HotkeyAction.VIEWER_NEXT else null
            else -> null
        }
        if (action != null) return Hotkey(action)
        val key = base(keyCode, extended, char) ?: return null
        if (ctrl && !alt) {
            return when (key) {
                'f' -> Hotkey(HotkeyAction.SEARCH)
                'k' -> Hotkey(HotkeyAction.SEARCH_CHATS)
                'n' -> Hotkey(HotkeyAction.NEW_MESSAGE)
                ',' -> Hotkey(HotkeyAction.SETTINGS)
                'q' -> Hotkey(HotkeyAction.QUIT)
                'o' -> Hotkey(HotkeyAction.ATTACH)
                's' -> Hotkey(HotkeyAction.SAVE)
                '0' -> Hotkey(HotkeyAction.SAVED_MESSAGES)
                in '1'..'9' -> Hotkey(HotkeyAction.FOLDER, key - '1')
                else -> null
            }
        }
        if (plain && key == 'r') return Hotkey(HotkeyAction.ROTATE)
        return null
    }

    /** Сочетание из события AWT. */
    fun resolve(event: KeyEvent): Hotkey? {
        val ctrl = event.isControlDown || (isMac && event.isMetaDown)
        return resolve(event.keyCode, event.extendedKeyCode, event.keyChar, ctrl, event.isShiftDown, event.isAltDown)
    }

    private const val EXTENDED_UNICODE = 0x01000000
}

/**
 * Горячие клавиши всего окна. Экраны кладут обработчики стопкой ([HotkeyHandler]): сочетание
 * получает сначала верхний (просмотр фото поверх чата, чат поверх списка), пока кто-нибудь
 * его не выполнит. Невыполненное сочетание идёт дальше как обычный ввод — буква «R» в поле
 * ввода остаётся буквой, если просмотр фото закрыт. Слушает AWT до Compose, поэтому работает
 * и в диалогах.
 */
object HotkeyDispatcher {
    private val handlers = ArrayList<(Hotkey) -> Boolean>()
    private var installed = false
    /** Нажатие выполнено: напечатанный за ним знак в поле ввода не попадает. */
    private var swallowTyped = false

    private val dispatcher = KeyEventDispatcher { event ->
        when (event.id) {
            KeyEvent.KEY_TYPED -> {
                val swallow = swallowTyped
                swallowTyped = false
                swallow
            }
            KeyEvent.KEY_PRESSED -> {
                val hotkey = KeyChords.resolve(event) ?: return@KeyEventDispatcher false
                val handled = handlers.asReversed().toList().any { it(hotkey) }
                swallowTyped = handled
                handled
            }
            else -> false
        }
    }

    fun add(handler: (Hotkey) -> Boolean) {
        handlers += handler
        if (!installed) {
            KeyboardFocusManager.getCurrentKeyboardFocusManager().addKeyEventDispatcher(dispatcher)
            installed = true
        }
    }

    fun remove(handler: (Hotkey) -> Boolean) {
        handlers -= handler
        if (handlers.isEmpty() && installed) {
            KeyboardFocusManager.getCurrentKeyboardFocusManager().removeKeyEventDispatcher(dispatcher)
            installed = false
        }
    }
}

/**
 * Обработчик горячих клавиш экрана, пока экран на месте и [enabled]. [onHotkey] возвращает
 * `true`, если выполнил сочетание; `false` — пусть его получит экран ниже или обычный ввод.
 */
@Composable
fun HotkeyHandler(enabled: Boolean = true, onHotkey: (Hotkey) -> Boolean) {
    val current by rememberUpdatedState(onHotkey)
    DisposableEffect(enabled) {
        if (!enabled) return@DisposableEffect onDispose {}
        val handler: (Hotkey) -> Boolean = { current(it) }
        HotkeyDispatcher.add(handler)
        onDispose { HotkeyDispatcher.remove(handler) }
    }
}
