package app.maxly.presentation.contacts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.maxly.data.AddressBook
import app.maxly.data.ContactRepository
import app.maxly.data.PreferenceStore
import app.maxly.domain.Contact
import app.maxly.domain.PhoneBookEntry
import com.max.core.api.PhoneNumbers
import app.maxly.presentation.common.PresenceText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Разрешение на телефонную книгу глазами экрана. */
enum class PhoneBookPermission {
    /** Ещё не спрашивали: сначала пояснение, потом системный запрос. */
    NOT_ASKED,
    GRANTED,
    /** Отказали, но системный запрос можно показать снова. */
    DENIED,
    /** Отказали насовсем: система больше не спросит, остаются настройки приложения. */
    BLOCKED;

    companion object {
        /**
         * Состояние по фактам системы: [granted] — разрешение есть, [canAskAgain] — система
         * советует пояснить и спросить снова (на Android — `shouldShowRequestPermissionRationale`),
         * [askedBefore] — системный запрос уже показывали. Без пояснения и после запроса — это
         * отказ насовсем; до первого запроса — ещё не спрашивали.
         */
        fun resolve(granted: Boolean, canAskAgain: Boolean, askedBefore: Boolean): PhoneBookPermission = when {
            granted -> GRANTED
            canAskAgain -> DENIED
            askedBefore -> BLOCKED
            else -> NOT_ASKED
        }
    }
}

/** Что показать поверх экрана контактов. */
enum class PhoneBookPrompt {
    /** Зачем доступ — перед системным запросом. */
    RATIONALE,
    /** Отказали: можно спросить ещё раз. */
    DENIED,
    /** Отказали насовсем: кнопка в настройки приложения. */
    BLOCKED,
}

/** Запись телефонной книги, чей номер совпал с номером контакта. */
data class PhoneBookMatch(val entry: PhoneBookEntry, val contact: Contact, val phone: String)

object PhoneBookMatcher {
    /**
     * Записи книги, чьи номера ([PhoneNumbers.normalize]) совпали с номерами [contacts].
     * Каждый контакт — один раз, за первой записью с его номером; у записи с несколькими
     * номерами может быть несколько контактов. Порядок — как в книге.
     */
    fun match(entries: List<PhoneBookEntry>, contacts: List<Contact>): List<PhoneBookMatch> {
        val byPhone = HashMap<String, Contact>()
        for (contact in contacts) {
            val phone = PhoneNumbers.normalize(contact.phone) ?: continue
            byPhone.putIfAbsent(phone, contact)
        }
        if (byPhone.isEmpty()) return emptyList()
        val matched = HashSet<String>()
        val result = ArrayList<PhoneBookMatch>()
        for (entry in entries) {
            for (phone in entry.phones) {
                val contact = byPhone[phone] ?: continue
                if (matched.add(contact.id)) result += PhoneBookMatch(entry, contact, phone)
            }
        }
        return result
    }
}

data class PhoneBookUiState(
    /** Книга есть на устройстве; нет — вход не показывается. */
    val isAvailable: Boolean = false,
    val permission: PhoneBookPermission = PhoneBookPermission.NOT_ASKED,
    val prompt: PhoneBookPrompt? = null,
    val isLoading: Boolean = false,
    /** Записей с номерами; `null` — книгу ещё не читали. */
    val entryCount: Int? = null,
    /** Сколько записей совпало с контактами аккаунта. */
    val matchCount: Int = 0,
    val error: String? = null,
) {
    /** Подпись под «Найти друзей из контактов». */
    val summary: String
        get() = when {
            isLoading -> "Читаем телефонную книгу…"
            error != null -> error
            entryCount != null -> {
                val book = "$entryCount ${PresenceText.plural(entryCount, "контакт", "контакта", "контактов")} в телефонной книге"
                if (matchCount > 0) "$book · уже в ваших контактах: $matchCount" else book
            }
            permission == PhoneBookPermission.BLOCKED -> "Доступ к контактам запрещён в настройках"
            else -> "Знакомые из телефонной книги"
        }
}

/**
 * Доступ к телефонной книге с экрана контактов: пояснение, системный запрос (его показывает
 * экран), отказ и отказ насовсем, чтение книги. Прочитанное живёт только в памяти (модели и
 * ядра — для имён людей из книги) и пропадает, если разрешение отозвали; на сервер ничего не уходит.
 */
class PhoneBookViewModel(
    private val addressBook: AddressBook,
    contacts: ContactRepository,
    private val currentUserId: () -> String? = { null },
    /** Здесь помнится, что системный запрос уже показывали: иначе отказ насовсем не отличить. */
    private val prefs: PreferenceStore? = null,
    /** Прочитанная книга — ядру для имён; отозвали разрешение — пустая книга. */
    private val sink: app.maxly.data.AddressBookSink? = null,
) : ViewModel() {
    private val _state = MutableStateFlow(PhoneBookUiState(isAvailable = addressBook.isAvailable))
    val state: StateFlow<PhoneBookUiState> = _state.asStateFlow()

    private var cached: List<PhoneBookEntry>? = null
    private var known: List<Contact> = emptyList()
    private var matched: List<PhoneBookMatch> = emptyList()
    /** Пользователь ушёл в настройки разрешить доступ: по возвращении с разрешением — прочитать. */
    private var awaitingSettings = false
    private var loading: Job? = null

    /** Прочитанная книга; пусто, пока не читали. */
    val entries: List<PhoneBookEntry> get() = cached.orEmpty()

    /** Совпадения книги с контактами аккаунта. */
    val matches: List<PhoneBookMatch> get() = matched

    init {
        viewModelScope.launch {
            contacts.contacts.collect { list ->
                val me = currentUserId()
                known = list.filter { it.id != me }
                rematch()
            }
        }
    }

    private var askedBefore: Boolean
        get() = prefs?.get(KEY_ASKED) == "1" || askedInMemory
        set(value) {
            askedInMemory = value
            if (value) prefs?.put(KEY_ASKED, "1")
        }
    private var askedInMemory = false

    /** Нажали «Найти друзей из контактов». */
    fun findFriends() {
        if (!_state.value.isAvailable) return
        when (_state.value.permission) {
            PhoneBookPermission.GRANTED -> load()
            PhoneBookPermission.BLOCKED -> _state.update { it.copy(prompt = PhoneBookPrompt.BLOCKED) }
            PhoneBookPermission.NOT_ASKED, PhoneBookPermission.DENIED -> _state.update { it.copy(prompt = PhoneBookPrompt.RATIONALE) }
        }
    }

    /** Пояснение или отказ закрыли без действия. */
    fun dismissPrompt() = _state.update { it.copy(prompt = null) }

    /** Экран показывает системный запрос. */
    fun systemPromptShown() {
        askedBefore = true
        _state.update { it.copy(prompt = null) }
    }

    /** Ответ на системный запрос. */
    fun permissionResult(granted: Boolean, canAskAgain: Boolean) {
        askedBefore = true
        val permission = PhoneBookPermission.resolve(granted, canAskAgain, askedBefore = true)
        _state.update {
            it.copy(
                permission = permission,
                prompt = when (permission) {
                    PhoneBookPermission.GRANTED -> null
                    PhoneBookPermission.DENIED -> PhoneBookPrompt.DENIED
                    else -> PhoneBookPrompt.BLOCKED
                },
            )
        }
        if (granted) load() else forget()
    }

    /** Ушли в настройки приложения за разрешением. */
    fun openedSettings() {
        awaitingSettings = true
        _state.update { it.copy(prompt = null) }
    }

    /**
     * Сверка с системой: при показе экрана и при возврате в приложение (разрешение могли дать
     * или отозвать в настройках). Отозвали — прочитанное забывается.
     */
    fun permissionChecked(granted: Boolean, canAskAgain: Boolean) {
        val permission = PhoneBookPermission.resolve(granted, canAskAgain, askedBefore)
        _state.update { it.copy(permission = permission) }
        if (!granted) {
            forget()
            return
        }
        if (awaitingSettings) {
            awaitingSettings = false
            load()
        }
    }

    /** Прочитать книгу заново (разрешение уже есть). */
    fun refresh() {
        if (_state.value.permission == PhoneBookPermission.GRANTED) load()
    }

    private fun load() {
        if (loading?.isActive == true) return
        _state.update { it.copy(isLoading = true, error = null) }
        loading = viewModelScope.launch {
            try {
                val entries = addressBook.entries()
                cached = entries
                sink?.publish(entries)
                rematch()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _state.update { it.copy(error = "Не удалось прочитать контакты телефона") }
            } finally {
                _state.update { it.copy(isLoading = false) }
            }
        }
    }

    private fun forget() {
        loading?.cancel()
        sink?.publish(emptyList())
        cached = null
        matched = emptyList()
        _state.update { it.copy(entryCount = null, matchCount = 0, isLoading = false, error = null) }
    }

    private fun rematch() {
        val entries = cached ?: return
        matched = PhoneBookMatcher.match(entries, known)
        _state.update { it.copy(entryCount = entries.size, matchCount = matched.size) }
    }

    private companion object {
        const val KEY_ASKED = "phonebook.asked"
    }
}
