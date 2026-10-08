package app.orbitle.ui.keys

import androidx.compose.runtime.staticCompositionLocalOf
import app.orbitle.data.PreferenceStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Чем отправлять сообщение из поля ввода. */
enum class SendKey(val title: String, val hint: String) {
    ENTER("Enter", "Shift+Enter — новая строка"),
    CTRL_ENTER("Ctrl+Enter", "Enter — новая строка"),
}

/** Клавиша отправки для полей ввода; задаёт главный экран из [KeyboardSettings]. */
val LocalSendKey = staticCompositionLocalOf { SendKey.ENTER }

/** Настройки клавиатуры на этом компьютере: пока только клавиша отправки. */
class KeyboardSettings(private val store: PreferenceStore) {
    private val _sendKey = MutableStateFlow(SendKey.entries.firstOrNull { it.name == store.get(KEY_SEND) } ?: SendKey.ENTER)
    val sendKey: StateFlow<SendKey> = _sendKey.asStateFlow()

    fun setSendKey(key: SendKey) {
        _sendKey.value = key
        store.put(KEY_SEND, key.name)
    }

    private companion object {
        const val KEY_SEND = "keyboard.send"
    }
}

/** Горячие клавиши для экрана «Клавиатура»: группы, сочетания и что они делают. */
object HotkeyCatalog {
    data class Entry(val keys: List<String>, val title: String)
    data class Group(val title: String, val entries: List<Entry>)

    fun groups(command: String = KeyChords.command, sendKey: SendKey = SendKey.ENTER): List<Group> {
        val send = if (sendKey == SendKey.ENTER) "Enter" else "$command+Enter"
        val newline = if (sendKey == SendKey.ENTER) "Shift+Enter" else "Enter"
        return listOf(
            Group(
                "Общие",
                listOf(
                    Entry(listOf("$command+K"), "Поиск по чатам"),
                    Entry(listOf("$command+F"), "Поиск в открытом чате (без чата — по чатам)"),
                    Entry(listOf("$command+N"), "Новое сообщение"),
                    Entry(listOf("$command+0"), "Избранное"),
                    Entry(listOf("$command+,"), "Настройки"),
                    Entry(listOf("Esc"), "Назад: закрыть окно, поиск, профиль или чат"),
                    Entry(listOf("$command+Q"), "Выйти из Orbitle"),
                ),
            ),
            Group(
                "Список чатов",
                listOf(
                    Entry(listOf("Alt+↓", "Ctrl+Tab", "$command+PageDown"), "Следующий чат"),
                    Entry(listOf("Alt+↑", "Ctrl+Shift+Tab", "$command+PageUp"), "Предыдущий чат"),
                    Entry(listOf("$command+1…9"), "Папка по порядку"),
                ),
            ),
            Group(
                "Чат",
                listOf(
                    Entry(listOf("PageUp", "PageDown"), "Лента на экран вверх или вниз"),
                    Entry(listOf("$command+End"), "К последнему сообщению"),
                    Entry(listOf("$command+↑", "$command+↓"), "Ответить на сообщение выше или ниже"),
                    Entry(listOf("$command+O"), "Прикрепить файл"),
                ),
            ),
            Group(
                "Поле ввода",
                listOf(
                    Entry(listOf(send), "Отправить"),
                    Entry(listOf(newline), "Новая строка"),
                    Entry(listOf("↑"), "Изменить своё последнее сообщение (в пустом поле)"),
                    Entry(listOf("Esc"), "Отменить ответ или правку"),
                ),
            ),
            Group(
                "Форматирование выделенного текста",
                listOf(
                    Entry(listOf("$command+B"), "Жирный"),
                    Entry(listOf("$command+I"), "Курсив"),
                    Entry(listOf("$command+U"), "Подчёркнутый"),
                    Entry(listOf("$command+Shift+X"), "Зачёркнутый"),
                    Entry(listOf("$command+Shift+M"), "Моноширинный"),
                    Entry(listOf("$command+K"), "Ссылка"),
                ),
            ),
            Group(
                "Звонки и запись",
                listOf(
                    Entry(listOf("$command+Shift+A"), "Ответить на входящий звонок"),
                    Entry(listOf("$command+Shift+H"), "Завершить или отклонить звонок"),
                    Entry(listOf("$command+D"), "Микрофон в звонке"),
                    Entry(listOf("$command+E"), "Камера в звонке"),
                    Entry(listOf("$command+Shift+R"), "Записать голосовое или кружок, повторно — отправить"),
                    Entry(listOf("Esc"), "Отменить запись"),
                ),
            ),
            Group(
                "Просмотр фото и видео",
                listOf(
                    Entry(listOf("←", "→"), "Предыдущее или следующее"),
                    Entry(listOf("R"), "Повернуть фото"),
                    Entry(listOf("$command+S"), "Сохранить"),
                    Entry(listOf("Esc"), "Закрыть"),
                ),
            ),
        )
    }
}
