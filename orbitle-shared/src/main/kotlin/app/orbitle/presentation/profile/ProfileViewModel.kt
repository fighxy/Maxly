package app.orbitle.presentation.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.MessageRepository
import app.orbitle.data.ProfileRepository
import app.orbitle.domain.ChatProfile
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.SharedMediaTab
import app.orbitle.presentation.chat.ChatMedia
import app.orbitle.presentation.chat.MessageFiles
import app.orbitle.presentation.chat.VoicePlayer
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.common.PresenceText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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
) : ViewModel() {

    private val _state = MutableStateFlow(build(profiles.cached(chatId) ?: ChatProfile(ChatProfile.Kind.USER, chatId, title.orEmpty()), loading = true))
    val state: StateFlow<ProfileUiState> = _state.asStateFlow()

    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    val media = ChatMedia(chatId, messages, viewModelScope, player, files, onError = { show(it) })

    private var window: List<Message> = emptyList()
    private val remote = mutableMapOf<String, Message>()
    private val cursors = mutableMapOf<SharedMediaTab, String>()
    private val finished = mutableSetOf<SharedMediaTab>()
    private val loadingTabs = mutableSetOf<SharedMediaTab>()
    private var remoteStarted = false
    private var tabChosen = false

    init {
        viewModelScope.launch {
            try {
                val fresh = profiles.profile(chatId)
                _state.update { current -> build(fresh, loading = false).copy(shared = current.shared, tab = current.tab) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val text = (e as? OrbitleError)?.userMessage ?: "Не удалось загрузить профиль"
                _state.update { it.copy(isLoading = false, error = if (it.rows.isEmpty() && it.profile.title.isBlank()) text else null) }
            }
        }
        viewModelScope.launch {
            messages.messages(chatId).collect {
                window = it
                rebuildShared()
                if (!remoteStarted && window.any { m -> m.id.toLongOrNull() != null }) {
                    remoteStarted = true
                    SharedMediaTab.entries.forEach(::loadMore)
                }
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
        val anchor = cursors[tab] ?: window.lastOrNull { it.status == MessageStatus.SENT && it.id.toLongOrNull() != null }?.id ?: return
        loadingTabs += tab
        _state.update { it.copy(loadingShared = true) }
        viewModelScope.launch {
            try {
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

    private fun show(error: Exception) {
        _notice.value = (error as? OrbitleError)?.userMessage ?: OrbitleError.Unknown.userMessage
    }

    private fun build(profile: ChatProfile, loading: Boolean): ProfileUiState {
        val title = title(profile)
        val (subtitle, accent) = subtitle(profile)
        val avatar = when {
            profile.kind == ChatProfile.Kind.SAVED -> ChatAvatar(ChatAvatar.Kind.SavedMessages, 0)
            profile.avatarUrl != null -> ChatAvatar(ChatAvatar.Kind.Photo(profile.avatarUrl, ChatAvatar.initials(title)), ChatAvatar.colorIndex(chatId))
            else -> ChatAvatar(ChatAvatar.Kind.Initials(ChatAvatar.initials(title)), ChatAvatar.colorIndex(chatId))
        }
        return ProfileUiState(profile, title, subtitle, accent, avatar, rows(profile), profile.commands, isLoading = loading)
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
        ChatProfile.Kind.USER -> presence.status(profile.isOnline, profile.lastSeenMs, now()) to profile.isOnline
        ChatProfile.Kind.BOT -> "бот" to false
        ChatProfile.Kind.SAVED -> "ваши сообщения и заметки" to false
        ChatProfile.Kind.CHANNEL -> (profile.participants?.let { "${grouped(it)} ${PresenceText.plural(it, "подписчик", "подписчика", "подписчиков")}" }
            ?: if (profile.isPublic) "публичный канал" else "канал") to false
        ChatProfile.Kind.GROUP -> (profile.participants?.let { "${grouped(it)} ${PresenceText.plural(it, "участник", "участника", "участников")}" } ?: "группа") to false
    }
}
