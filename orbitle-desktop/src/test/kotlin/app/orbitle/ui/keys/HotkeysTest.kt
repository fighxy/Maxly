package app.orbitle.ui.keys

import app.orbitle.data.PreferenceStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.awt.event.KeyEvent

class HotkeysTest {
    private fun chord(code: Int, char: Char = KeyEvent.CHAR_UNDEFINED, extended: Int = code, ctrl: Boolean = false, shift: Boolean = false, alt: Boolean = false) =
        KeyChords.resolve(code, extended, char, ctrl, shift, alt)

    /** Нелатинская буква: AWT на macOS и Linux даёт расширенный код 0x01000000 + Unicode. */
    private fun russian(letter: Char, ctrl: Boolean = false) =
        chord(KeyEvent.VK_UNDEFINED, letter, extended = 0x01000000 + letter.code, ctrl = ctrl)

    @Test
    fun commandsWorkInEnglishAndRussianLayouts() {
        assertEquals(Hotkey(HotkeyAction.SEARCH), chord(KeyEvent.VK_F, ctrl = true))
        // Та же клавиша в русской раскладке — «А».
        assertEquals(Hotkey(HotkeyAction.SEARCH), russian('а', ctrl = true))
        assertEquals(Hotkey(HotkeyAction.SEARCH_CHATS), russian('л', ctrl = true))
        assertEquals(Hotkey(HotkeyAction.NEW_MESSAGE), russian('т', ctrl = true))
        assertEquals(Hotkey(HotkeyAction.SETTINGS), russian('б', ctrl = true))
        assertEquals(Hotkey(HotkeyAction.QUIT), chord(KeyEvent.VK_Q, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.ATTACH), russian('щ', ctrl = true))
        assertEquals(Hotkey(HotkeyAction.SAVE), chord(KeyEvent.VK_S, ctrl = true))
        // Заглавная буква (Shift или Caps Lock) — та же клавиша.
        assertEquals(Hotkey(HotkeyAction.SEARCH), russian('А', ctrl = true))
        // На Windows у русских букв код клавиши уже латинский.
        assertEquals(Hotkey(HotkeyAction.SEARCH), chord(KeyEvent.VK_F, 'а', ctrl = true))
    }

    @Test
    fun foldersSavedMessagesAndChatNavigation() {
        assertEquals(Hotkey(HotkeyAction.FOLDER, 0), chord(KeyEvent.VK_1, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.FOLDER, 8), chord(KeyEvent.VK_9, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.SAVED_MESSAGES), chord(KeyEvent.VK_0, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.NEXT_CHAT), chord(KeyEvent.VK_TAB, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.PREVIOUS_CHAT), chord(KeyEvent.VK_TAB, ctrl = true, shift = true))
        assertEquals(Hotkey(HotkeyAction.PREVIOUS_CHAT), chord(KeyEvent.VK_UP, alt = true))
        assertEquals(Hotkey(HotkeyAction.NEXT_CHAT), chord(KeyEvent.VK_DOWN, alt = true))
        assertEquals(Hotkey(HotkeyAction.PREVIOUS_CHAT), chord(KeyEvent.VK_PAGE_UP, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.NEXT_CHAT), chord(KeyEvent.VK_PAGE_DOWN, ctrl = true))
    }

    @Test
    fun chatAndViewerKeys() {
        assertEquals(Hotkey(HotkeyAction.REPLY_OLDER), chord(KeyEvent.VK_UP, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.REPLY_NEWER), chord(KeyEvent.VK_DOWN, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.PAGE_UP), chord(KeyEvent.VK_PAGE_UP))
        assertEquals(Hotkey(HotkeyAction.PAGE_DOWN), chord(KeyEvent.VK_PAGE_DOWN))
        assertEquals(Hotkey(HotkeyAction.TO_LATEST), chord(KeyEvent.VK_END, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.VIEWER_PREVIOUS), chord(KeyEvent.VK_LEFT))
        assertEquals(Hotkey(HotkeyAction.VIEWER_NEXT), chord(KeyEvent.VK_RIGHT))
        assertEquals(Hotkey(HotkeyAction.ROTATE), chord(KeyEvent.VK_R, 'r'))
        assertEquals(Hotkey(HotkeyAction.ROTATE), russian('к'))
    }

    @Test
    fun formattingKeysInBothLayouts() {
        assertEquals(Hotkey(HotkeyAction.FORMAT_BOLD), chord(KeyEvent.VK_B, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.FORMAT_BOLD), russian('и', ctrl = true))
        assertEquals(Hotkey(HotkeyAction.FORMAT_ITALIC), chord(KeyEvent.VK_I, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.FORMAT_ITALIC), russian('ш', ctrl = true))
        assertEquals(Hotkey(HotkeyAction.FORMAT_UNDERLINE), chord(KeyEvent.VK_U, ctrl = true))
        assertEquals(Hotkey(HotkeyAction.FORMAT_UNDERLINE), russian('г', ctrl = true))
        assertEquals(Hotkey(HotkeyAction.FORMAT_STRIKE), chord(KeyEvent.VK_X, ctrl = true, shift = true))
        assertEquals(Hotkey(HotkeyAction.FORMAT_MONO), chord(KeyEvent.VK_M, ctrl = true, shift = true))
        // Без Shift это обычные вырезать и ничего.
        assertNull(chord(KeyEvent.VK_X, ctrl = true))
        assertNull(chord(KeyEvent.VK_M, ctrl = true))
        // Буквы без Ctrl — просто ввод.
        assertNull(chord(KeyEvent.VK_B, 'b'))
        assertNull(chord(KeyEvent.VK_X, 'X', shift = true))
        val formatting = HotkeyCatalog.groups("Ctrl").first { it.title == "Форматирование выделенного текста" }
        assertEquals(listOf("Ctrl+Shift+X"), formatting.entries.first { it.title == "Зачёркнутый" }.keys)
    }

    @Test
    fun ordinaryTypingIsNotAHotkey() {
        assertNull(chord(KeyEvent.VK_A, 'a'))
        assertNull(russian('ф'))
        assertNull(chord(KeyEvent.VK_UP))
        assertNull(chord(KeyEvent.VK_END))
        assertNull(chord(KeyEvent.VK_LEFT, shift = true))
        assertNull(chord(KeyEvent.VK_F, ctrl = true, alt = true))
    }

    @Test
    fun sendKeyIsRememberedAndShownInTheCatalog() {
        val saved = HashMap<String, String>()
        val store = object : PreferenceStore {
            override fun get(key: String) = saved[key]
            override fun put(key: String, value: String) { saved[key] = value }
        }
        val settings = KeyboardSettings(store)
        assertEquals(SendKey.ENTER, settings.sendKey.value)
        settings.setSendKey(SendKey.CTRL_ENTER)
        assertEquals(SendKey.CTRL_ENTER, KeyboardSettings(store).sendKey.value)
        val input = HotkeyCatalog.groups("Ctrl", SendKey.CTRL_ENTER).first { it.title == "Поле ввода" }
        assertEquals(listOf("Ctrl+Enter"), input.entries.first { it.title == "Отправить" }.keys)
        assertEquals(listOf("Enter"), input.entries.first { it.title == "Новая строка" }.keys)
        assertTrue(HotkeyCatalog.groups().all { it.entries.isNotEmpty() })
    }
}
