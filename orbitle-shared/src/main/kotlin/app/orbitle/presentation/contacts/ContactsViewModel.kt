package app.orbitle.presentation.contacts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.ChatRepository
import app.orbitle.data.ContactRepository
import app.orbitle.domain.Contact
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.common.PresenceText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.Normalizer
import java.time.ZoneId

data class ContactRow(
    val id: String,
    val title: String,
    val status: String,
    val isOnline: Boolean,
    val avatar: ChatAvatar,
    /** Опция `OFFICIAL`: рядом с именем галочка. */
    val isOfficial: Boolean = false,
)

data class ContactSection(val letter: String, val rows: List<ContactRow>)

data class ContactsUiState(
    val sections: List<ContactSection> = emptyList(),
    val searchResults: List<ContactRow> = emptyList(),
    val query: String = "",
    val isSearching: Boolean = false,
    val isSyncing: Boolean = false,
    val count: Int = 0,
    val content: Content = Content.LOADING,
) {
    enum class Content { LOADING, EMPTY, READY }
    val isFiltering: Boolean get() = query.isNotBlank()
}

/** Вкладка «Контакты»: разделы по буквам, поиск по имени и номеру, статус «в сети». */
class ContactsViewModel(
    private val repository: ContactRepository,
    private val currentUserId: () -> String?,
    zone: ZoneId = ZoneId.systemDefault(),
    private val now: () -> Long = System::currentTimeMillis,
    private val chats: ChatRepository? = null,
) : ViewModel() {
    private val presence = PresenceText(zone)
    private val _state = MutableStateFlow(ContactsUiState())
    val state: StateFlow<ContactsUiState> = _state.asStateFlow()
    private var contacts: List<Contact> = emptyList()
    private var received = false
    private var synced = false

    /** «Переименовать», «Удалить из контактов» и «Добавить по номеру». */
    val actions = ContactActions(viewModelScope, repository)

    fun askRename(contactId: String) {
        contact(contactId)?.let(actions::askRename)
    }

    fun askRemove(contactId: String) {
        contact(contactId)?.let(actions::askRemove)
    }

    init {
        viewModelScope.launch {
            repository.contacts.collect { list ->
                val me = currentUserId()
                contacts = list.filter { it.id != me }
                received = received || list.isNotEmpty()
                rebuild()
            }
        }
        // «Был(а) 5 минут назад» стареет.
        viewModelScope.launch {
            while (true) {
                delay(60_000)
                rebuild()
            }
        }
    }

    /** Вкладка открылась: один раз за запуск сверить список с сервером. */
    fun appeared() {
        if (!synced) sync()
    }

    fun sync() {
        if (_state.value.isSyncing) return
        _state.update { it.copy(isSyncing = true) }
        viewModelScope.launch {
            try {
                repository.sync()
                synced = true
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Неудача синхронизации не мешает: показывается прежний список.
            } finally {
                received = true
                _state.update { it.copy(isSyncing = false) }
                rebuild()
            }
        }
    }

    fun setSearching(active: Boolean) = _state.update { it.copy(isSearching = active, query = if (active) it.query else "") }.also { rebuild() }

    fun setQuery(query: String) {
        _state.update { it.copy(query = query) }
        rebuild()
    }

    /** Id личного чата в Max — исключающее «или» двух id пользователей. */
    fun chatId(contactId: String): String? {
        val me = currentUserId()?.toLongOrNull() ?: return null
        val other = contactId.toLongOrNull() ?: return null
        return (me xor other).toString()
    }

    /**
     * Открыть диалог с контактом. Id возвращается сразу, а строка списка ставится локально:
     * сервер создаёт чат только первым сообщением.
     */
    fun prepare(contactId: String, title: String): String? {
        val id = chatId(contactId) ?: return null
        val repo = chats ?: return id
        viewModelScope.launch {
            try {
                repo.prepareDialog(id, contactId, title)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            }
        }
        return id
    }

    fun contact(id: String): Contact? = contacts.firstOrNull { it.id == id }

    private fun rebuild() {
        val nowMs = now()
        val sorted = contacts.sortedWith { a, b -> compare(a.displayName, b.displayName) }
        val query = _state.value.query
        val results = if (query.isNotBlank()) search(sorted, query).map { row(it, nowMs) } else emptyList()
        val sections = sorted.groupBy { indexTitle(it.displayName) }
            .let { grouped -> INDEX.mapNotNull { letter -> grouped[letter]?.let { ContactSection(letter, it.map { c -> row(c, nowMs) }) } } }
        val content = when {
            sorted.isNotEmpty() -> ContactsUiState.Content.READY
            received -> ContactsUiState.Content.EMPTY
            else -> ContactsUiState.Content.LOADING
        }
        _state.update { it.copy(sections = sections, searchResults = results, count = sorted.size, content = content) }
    }

    private fun row(contact: Contact, nowMs: Long): ContactRow {
        val name = contact.displayName
        // О присутствии ничего не известно: строки нет.
        val seen = presence.status(contact.isOnline, contact.lastSeenMs, nowMs, contact.presence)?.replaceFirstChar { it.uppercase() }.orEmpty()
        val status = when {
            contact.isOnline -> seen
            contact.isServiceAccount -> "Служебный аккаунт"
            contact.isBot -> "Бот"
            else -> seen
        }
        return ContactRow(
            id = contact.id,
            title = name,
            status = status,
            isOnline = contact.isOnline,
            avatar = ChatAvatar(
                contact.avatarUrl?.let { ChatAvatar.Kind.Photo(it, ChatAvatar.initials(name)) } ?: ChatAvatar.Kind.Initials(ChatAvatar.initials(name)),
                ChatAvatar.colorIndex(contact.id),
            ),
            isOfficial = contact.isOfficial,
        )
    }

    companion object {
        val CYRILLIC = "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЭЮЯ".map { it.toString() }
        val LATIN = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { it.toString() }
        const val OTHER = "#"
        val INDEX = CYRILLIC + LATIN + OTHER

        /** Буква указателя: «Ё» вместе с «Е», латиница без диакритики, остальное — «#». */
        fun indexTitle(name: String): String {
            val first = name.trim().firstOrNull() ?: return OTHER
            var letter = first.uppercase()
            if (letter == "Ё") letter = "Е"
            if (letter in CYRILLIC || letter in LATIN) return letter
            val plain = Normalizer.normalize(letter, Normalizer.Form.NFD).replace(Regex("\\p{M}"), "")
            return if (plain in LATIN) plain else OTHER
        }

        private fun rank(name: String): Int = when (indexTitle(name)) {
            in CYRILLIC -> 0
            in LATIN -> 1
            else -> 2
        }

        /** Кириллица раньше латиницы, остальное в конце; внутри — по алфавиту без учёта регистра. */
        fun compare(lhs: String, rhs: String): Int {
            val byRank = rank(lhs).compareTo(rank(rhs))
            if (byRank != 0) return byRank
            val byName = normalize(lhs).compareTo(normalize(rhs))
            return if (byName != 0) byName else lhs.compareTo(rhs)
        }

        /** Нижний регистр, «ё» как «е», латиница без диакритики («é» → «e»); «й» остаётся собой. */
        fun normalize(text: String): String = buildString {
            for (char in text.lowercase().replace('ё', 'е')) {
                if (char in '\u0400'..'\u04FF') append(char)
                else append(Normalizer.normalize(char.toString(), Normalizer.Form.NFD).replace(MARKS, ""))
            }
        }.trim()

        private val MARKS = Regex("\\p{M}")

        /** По имени (начало слова или внутри) и по цифрам номера. */
        fun search(contacts: List<Contact>, query: String): List<Contact> {
            val needle = normalize(query)
            if (needle.isEmpty()) return contacts
            val digits = query.filter { it.isDigit() }
            return contacts.filter { contact ->
                normalize(contact.displayName).contains(needle) || (digits.length >= 3 && contact.phone.contains(digits))
            }
        }
    }
}
