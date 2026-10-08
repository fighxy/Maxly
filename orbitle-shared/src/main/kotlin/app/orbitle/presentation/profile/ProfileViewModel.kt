package app.orbitle.presentation.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.CoreErrors
import app.orbitle.data.MessageRepository
import app.orbitle.data.PeerPresence
import app.orbitle.data.ProfileRepository
import app.orbitle.domain.ChatProfile
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.SharedMediaTab
import app.orbitle.presentation.chat.ChatMedia
import app.orbitle.presentation.chat.MessageFiles
import app.orbitle.presentation.chat.VoicePlayer
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.common.PresenceText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Строка «ключ — значение» в блоке сведений. */
data class InfoRow(val id: String, val title: String, val value: String, val action: Action?, val multiline: Boolean = false) {
    sealed interface Action {
        data class Call(val uri: String) : Action
        data class Open(val url: String) : Action
        data object Copy : Action
    }
}

data class ProfileUiState(
    val profile: ChatProfile,
    val title: String,
    val subtitle: String,
    val subtitleAccent: Boolean,
    val avatar: ChatAvatar,
    val rows: List<InfoRow> = emptyList(),
    val commands: List<ChatProfile.BotCommand> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val shared: SharedMedia = SharedMedia(),
    val tab: SharedMediaTab = SharedMediaTab.MEDIA,
    val loadingShared: Boolean = false,
    /** Собеседник в чёрном списке. `null` — неизвестно или это не человек и не бот. */
    val blocked: Boolean? = null,
    /** Идёт блокировка или разблокировка. */
    val blocking: Boolean = false,
    /** Собеседник в контактах: его можно переименовать и удалить. `null` — не контакт или неизвестно. */
    val contact: app.orbitle.domain.Contact? = null,
)

/** Профиль собеседника, бота, группы или канала с общими медиа. */
class ProfileViewModel(
    val chatId: String,
    title: String?,
    private val profiles: ProfileRepository,
    private val messages: MessageRepository,
    player: VoicePlayer? = null,
    files: MessageFiles? = null,
    private val now: () -> Long = System::currentTimeMillis,
    private val presence: PresenceText = PresenceText(),
    /**
     * Пауза между страницами общих медиа (`CHAT_MEDIA`), мс. Без неё профиль слал запросы всех
     * вкладок разом, и сервер отвечал `too.many.requests` заодно и истории открытого чата.
     */
    private val sharedPauseMs: Long = 400,
    /** Чёрный список: «Заблокировать» и «Разблокировать» собеседника. `null` — без них. */
    private val account: app.orbitle.data.AccountRepository? = null,
    /** Контакты: переименовать, удалить, добавить собеседника. `null` — без этих пунктов. */
    private val contacts: app.orbitle.data.ContactRepository? = null,
) : ViewModel() {

    private val _state = MutableStateFlow(build(profiles.cached(chatId) ?: ChatProfile(ChatProfile.Kind.USER, chatId, title.orEmpty()), loading = true))
    val state: StateFlow<ProfileUiState> = _state.asStateFlow()

    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    val media = ChatMedia(chatId, messages, viewModelScope, player, files, onError = { show(it) })

    /** Диалоги действий с контактом; `null` — без контактов. */
    val contactActions: app.orbitle.presentation.contacts.ContactActions? =
        contacts?.let { app.orbitle.presentation.contacts.ContactActions(viewModelScope, it) }

    private var window: List<Message> = emptyList()
    private val remote = mutableMapOf<String, Message>()
    private val cursors = mutableMapOf<SharedMediaTab, String>()
    private val finished = mutableSetOf<SharedMediaTab>()
    private val loadingTabs = mutableSetOf<SharedMediaTab>()
    private var remoteStarted = false
    private var tabChosen = false
    /** Когда ушёл последний запрос общих медиа. */
    private var lastSharedAt = Long.MIN_VALUE

    init {
        viewModelScope.launch {
            try {
                val fresh = profiles.profile(chatId)
                _state.update { current -> build(fresh, loading = false).copy(shared = current.shared, tab = current.tab, blocked = current.blocked, contact = current.contact) }
                if (_state.value.contact == null) contacts?.let { repo -> findContact(repo, fresh) }
                askBlocked(fresh)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val text = CoreErrors.text(e, "Не удалось загрузить профиль")
                _state.update { it.copy(isLoading = false, error = if (it.rows.isEmpty() && it.profile.title.isBlank()) text else null) }
            }
        }
        // Присутствие собеседника из стора: пуши меняют «в сети» и «был(а)…» на открытом профиле.
        viewModelScope.launch {
            _state.map { s -> s.profile.peerId?.takeIf { s.profile.kind == ChatProfile.Kind.USER } }
                .distinctUntilChanged()
                .collectLatest { peer -> if (peer != null) profiles.presence(peer).collect(::applyPresence) }
        }
        // «был(а) 5 минут назад» стареет: подпись пересчитывается, когда должна смениться.
        viewModelScope.launch {
            _state.map { listOf(it.profile.kind, it.profile.isOnline, it.profile.lastSeenMs, it.profile.presence) }
                .distinctUntilChanged()
                .collectLatest { tickPresence() }
        }
        contacts?.let { repo ->
            viewModelScope.launch {
                repo.contacts.collect { list ->
                    val peer = _state.value.profile.peerId ?: return@collect
                    val contact = list.firstOrNull { it.id == peer }
                    if (contact != _state.value.contact) {
                        _state.update { it.copy(contact = contact) }
                        refreshTitle()
                    }
                }
            }
            viewModelScope.launch {
                // Переименовали на другом устройстве: имя в шапке профиля новое.
                repo.changes.collect { changed -> if (changed.id == _state.value.profile.peerId) refreshTitle() }
            }
        }
        viewModelScope.launch {
            messages.messages(chatId).collect {
                window = it
                rebuildShared()
                if (!remoteStarted && window.any { m -> m.id.toLongOrNull() != null }) {
                    remoteStarted = true
                    // Первые страницы вкладок по очереди, с паузой между ними.
                    viewModelScope.launch { SharedMediaTab.entries.forEach { fetchPage(it) } }
                }
            }
        }
    }

    /** Профиль пришёл позже списка контактов: собеседник мог в нём уже быть. */
    private fun findContact(repo: app.orbitle.data.ContactRepository, card: ChatProfile) {
        val peer = card.peerId ?: return
        viewModelScope.launch {
            val list = repo.contacts.first()
            list.firstOrNull { it.id == peer }?.let { contact -> _state.update { it.copy(contact = contact) } }
        }
    }

    /** Имя из стора после правки контакта. */
    private fun refreshTitle() {
        val fresh = profiles.cached(chatId) ?: return
        if (fresh.kind != ChatProfile.Kind.USER && fresh.kind != ChatProfile.Kind.BOT) return
        _state.update { current ->
            val profile = current.profile.copy(title = fresh.title)
            val title = title(profile)
            current.copy(profile = profile, title = title, avatar = avatarOf(profile, title))
        }
    }

    /** «Удалить из контактов» и «Переименовать» в меню профиля. */
    fun askRenameContact() {
        _state.value.contact?.let { contactActions?.askRename(it) }
    }

    fun askRemoveContact() {
        _state.value.contact?.let { contactActions?.askRemove(it) }
    }

    /** Место собеседника в чёрном списке: список спрашивается один раз на профиль. */
    private fun askBlocked(card: ChatProfile) {
        val repo = account ?: return
        val peer = card.peerId ?: return
        if (card.kind != ChatProfile.Kind.USER && card.kind != ChatProfile.Kind.BOT) return
        viewModelScope.launch {
            try {
                val blocked = repo.blockedUsers().any { it.id == peer }
                _state.update { it.copy(blocked = blocked) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Без списка пункта нет: неизвестно, блокировать или разблокировать.
            }
        }
    }

    /** Заблокировать или разблокировать собеседника. */
    fun toggleBlocked() {
        val repo = account ?: return
        val current = _state.value
        val peer = current.profile.peerId ?: return
        if (current.blocking) return
        val block = current.blocked != true
        _state.update { it.copy(blocking = true) }
        viewModelScope.launch {
            try {
                if (block) repo.block(peer) else repo.unblock(peer)
                _state.update { it.copy(blocked = block, blocking = false) }
                notify(if (block) "Пользователь заблокирован" else "Пользователь разблокирован")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(blocking = false) }
                show(e)
            }
        }
    }

    fun selectTab(tab: SharedMediaTab) {
        tabChosen = true
        _state.update { it.copy(tab = tab) }
        loadMore(tab)
    }

    /** Следующая страница вкладки с сервера: от самого старого уже полученного сообщения. */
    fun loadMore(tab: SharedMediaTab = _state.value.tab) {
        if (tab in finished || tab in loadingTabs) return
        viewModelScope.launch { fetchPage(tab) }
    }

    private suspend fun fetchPage(tab: SharedMediaTab) {
        if (tab in finished || tab in loadingTabs) return
        val anchor = cursors[tab] ?: window.lastOrNull { it.status == MessageStatus.SENT && it.id.toLongOrNull() != null }?.id ?: return
        loadingTabs += tab
        _state.update { it.copy(loadingShared = true) }
        try {
            if (lastSharedAt != Long.MIN_VALUE) {
                val wait = lastSharedAt + sharedPauseMs - now()
                if (wait > 0) delay(wait)
            }
            lastSharedAt = now()
            val page = profiles.sharedPage(chatId, tab, anchor)
            val fresh = page.filter { it.id !in remote && window.none { w -> w.id == it.id } }
            page.forEach { remote[it.id] = it }
            val oldest = page.minByOrNull { it.timeMs }?.id
            if (fresh.isEmpty() || oldest == null || oldest == anchor) finished += tab else cursors[tab] = oldest
            rebuildShared()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Общие медиа с сервера — дополнение: окно чата уже показано.
            finished += tab
        } finally {
            loadingTabs -= tab
            _state.update { it.copy(loadingShared = loadingTabs.isNotEmpty()) }
        }
    }

    fun consumeNotice() {
        _notice.value = null
    }

    fun notify(text: String) {
        _notice.value = text
    }

    private fun rebuildShared() {
        val shared = SharedMedia.collect(window + remote.values, messages.currentUserId)
        _state.update {
            val tab = if (!tabChosen && shared.count(it.tab) == 0) shared.tabs.firstOrNull() ?: it.tab else it.tab
            it.copy(shared = shared, tab = tab)
        }
    }

    private fun applyPresence(presence: PeerPresence?) {
        presence ?: return
        _state.update { s ->
            if (s.profile.kind != ChatProfile.Kind.USER) return@update s
            val profile = s.profile.copy(isOnline = presence.isOnline, lastSeenMs = presence.lastSeenMs, presence = presence.presence)
            val (subtitle, accent) = subtitle(profile)
            s.copy(profile = profile, subtitle = subtitle, subtitleAccent = accent)
        }
    }

    private suspend fun tickPresence() {
        var last = Long.MIN_VALUE
        while (true) {
            val at = now()
            // Часы стоят (тесты): пересчитывать нечего.
            if (at == last) return
            last = at
            val profile = _state.value.profile
            if (profile.kind != ChatProfile.Kind.USER) return
            val next = presence.nextChange(profile.isOnline, profile.lastSeenMs, at, profile.presence) ?: return
            delay(next - at + 1)
            _state.update { s ->
                val (subtitle, accent) = subtitle(s.profile)
                s.copy(subtitle = subtitle, subtitleAccent = accent)
            }
        }
    }

    private fun show(error: Exception) {
        _notice.value = CoreErrors.text(error)
    }

    private fun build(profile: ChatProfile, loading: Boolean): ProfileUiState {
        val title = title(profile)
        val (subtitle, accent) = subtitle(profile)
        return ProfileUiState(profile, title, subtitle, accent, avatarOf(profile, title), rows(profile), profile.commands, isLoading = loading)
    }

    private fun avatarOf(profile: ChatProfile, title: String): ChatAvatar = when {
        profile.kind == ChatProfile.Kind.SAVED -> ChatAvatar(ChatAvatar.Kind.SavedMessages, 0)
        profile.avatarUrl != null -> ChatAvatar(ChatAvatar.Kind.Photo(profile.avatarUrl, ChatAvatar.initials(title)), ChatAvatar.colorIndex(chatId))
        else -> ChatAvatar(ChatAvatar.Kind.Initials(ChatAvatar.initials(title)), ChatAvatar.colorIndex(chatId))
    }

    companion object {
        fun title(profile: ChatProfile): String = profile.title.trim().ifEmpty {
            when (profile.kind) {
                ChatProfile.Kind.SAVED -> "Избранное"
                ChatProfile.Kind.BOT -> "Бот"
                ChatProfile.Kind.CHANNEL -> "Канал"
                ChatProfile.Kind.GROUP -> "Группа"
                ChatProfile.Kind.USER -> "Пользователь"
            }
        }

        /** `12500` → `12 500` с узким неразрывным пробелом. */
        fun grouped(count: Int): String = "%,d".format(java.util.Locale.US, count).replace(",", "\u202F")

        /** `https://max.ru/name` → `max.ru/name`. */
        fun shortLink(url: String): String = url.removePrefix("https://").removePrefix("http://")

        /** `79001234567` → `+7 900 123-45-67`. */
        fun phone(raw: String): String {
            val digits = raw.filter(Char::isDigit)
            if (digits.length == 11 && (digits[0] == '7' || digits[0] == '8')) {
                return "+7 ${digits.substring(1, 4)} ${digits.substring(4, 7)}-${digits.substring(7, 9)}-${digits.substring(9)}"
            }
            return if (digits.isEmpty()) raw else "+$digits"
        }

        fun rows(profile: ChatProfile): List<InfoRow> {
            val rows = mutableListOf<InfoRow>()
            if (profile.kind == ChatProfile.Kind.USER) profile.phone?.let {
                rows += InfoRow("phone", "телефон", phone(it), InfoRow.Action.Call("tel:+" + it.filter(Char::isDigit)))
            }
            profile.description?.let {
                val title = if (profile.kind == ChatProfile.Kind.USER || profile.kind == ChatProfile.Kind.SAVED) "о себе" else "описание"
                rows += InfoRow("description", title, it, InfoRow.Action.Copy, multiline = true)
            }
            profile.link?.let {
                val title = if (profile.kind == ChatProfile.Kind.CHANNEL || profile.kind == ChatProfile.Kind.GROUP) "ссылка" else "имя пользователя"
                rows += InfoRow("link", title, shortLink(it), InfoRow.Action.Open(it))
            }
            return rows
        }
    }

    private fun subtitle(profile: ChatProfile): Pair<String, Boolean> = when (profile.kind) {
        // О присутствии ничего не известно: строки нет.
        ChatProfile.Kind.USER -> (presence.status(profile.isOnline, profile.lastSeenMs, now(), profile.presence) ?: "") to profile.isOnline
        ChatProfile.Kind.BOT -> "бот" to false
        ChatProfile.Kind.SAVED -> "ваши сообщения и заметки" to false
        ChatProfile.Kind.CHANNEL -> (profile.participants?.let { "${grouped(it)} ${PresenceText.plural(it, "подписчик", "подписчика", "подписчиков")}" }
            ?: if (profile.isPublic) "публичный канал" else "канал") to false
        ChatProfile.Kind.GROUP -> (profile.participants?.let { "${grouped(it)} ${PresenceText.plural(it, "участник", "участника", "участников")}" } ?: "группа") to false
    }
}
