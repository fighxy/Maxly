package app.orbitle

import app.orbitle.data.AccountRepository
import app.orbitle.data.AppearanceSettings
import app.orbitle.data.CallRepository
import app.orbitle.data.ChatRepository
import app.orbitle.data.ContactRepository
import app.orbitle.data.CoreAccountRepository
import app.orbitle.data.CoreCallRepository
import app.orbitle.data.CoreChatRepository
import app.orbitle.data.CoreCommentsRepository
import app.orbitle.data.CoreContactRepository
import app.orbitle.data.CoreFolderRepository
import app.orbitle.data.CoreMessageRepository
import app.orbitle.data.CoreProfileRepository
import app.orbitle.data.CoreSessionRepository
import app.orbitle.data.CoreStickerRepository
import app.orbitle.data.FolderRepository
import app.orbitle.data.MaxCoreGateway
import app.orbitle.data.MessageRepository
import app.orbitle.data.PreferenceStore
import app.orbitle.data.PrivateModeSettings
import app.orbitle.data.ProfileRepository
import app.orbitle.data.RecentStickerStore
import app.orbitle.data.SessionManager
import app.orbitle.data.SessionRepository
import app.orbitle.data.StickerRepository
import app.orbitle.data.UserIdStore
import app.orbitle.domain.ChatDraft
import app.orbitle.domain.Sticker
import app.orbitle.media.CacheStorage
import app.orbitle.media.DesktopVoicePlayer
import app.orbitle.media.DownloadsSaver
import app.orbitle.media.FileDownloader
import app.orbitle.platform.AppPaths
import app.orbitle.platform.FilePrefs
import app.orbitle.presentation.calls.CallMarks
import app.orbitle.presentation.chat.DraftStore
import app.orbitle.presentation.chat.MessageFiles
import app.orbitle.presentation.chat.VoicePlayer
import app.orbitle.presentation.chatlist.ChatLocalMarks
import app.orbitle.presentation.chatlist.PreferenceRecentSearches
import com.max.shared.MaxClient
import com.max.shared.MaxClientConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Зависимости окна: одно ядро, одна сессия, репозитории над стором ядра. Токен хранит само ядро. */
class AppContainer {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * Без догрузки дыр истории после переподключения (`fillGapsOnReconnect`), как на iOS: ядро
     * листало историю всех чатов подряд, до 16 страниц на чат, и сервер отвечал
     * `too.many.requests` — заодно и на историю открытого чата. Открытый чат сам берёт свежую
     * страницу, старое догружается прокруткой.
     */
    val client: MaxClient = MaxClient(
        MaxClientConfig(namespace = CORE_NAMESPACE, messageLimit = MESSAGE_LIMIT, fillGapsOnReconnect = false),
    )

    val chats: ChatRepository = CoreChatRepository(client)
    val chatAdmin: app.orbitle.data.ChatAdminRepository = app.orbitle.data.CoreChatAdminRepository(client)
    val account: AccountRepository = CoreAccountRepository(client)
    val messages: MessageRepository = CoreMessageRepository(client)
    val calls: CallRepository = CoreCallRepository(client)
    val contacts: ContactRepository = CoreContactRepository(client)
    val folders: FolderRepository = CoreFolderRepository(client)
    val sessions: SessionRepository = CoreSessionRepository(client)
    val storage = CacheStorage()
    val profiles: ProfileRepository = CoreProfileRepository(client)

    private val mediaUserAgent: () -> String = { client.config.userAgent.httpUserAgent }
    private val downloader = FileDownloader(mediaUserAgent)

    val voicePlayer: VoicePlayer = DesktopVoicePlayer(scope, downloader)

    val files: MessageFiles = object : MessageFiles {
        override fun cached(fileId: String, name: String): String? = downloader.cached(fileId, name)?.absolutePath
        override suspend fun download(url: String, fileId: String, name: String, progress: (Float) -> Unit): String =
            downloader.download(url, fileId, name, progress).absolutePath
    }

    fun videoSourceUserAgent(): String = mediaUserAgent()

    private val prefs = FilePrefs(AppPaths.prefsFile)

    private val preferenceStore = object : PreferenceStore {
        override fun get(key: String): String? = prefs.getString(key, null)
        override fun put(key: String, value: String) = prefs.edit().putString(key, value).apply()
    }

    val appearance = AppearanceSettings(preferenceStore)
    val keyboard = app.orbitle.ui.keys.KeyboardSettings(preferenceStore)
    val privateMode = PrivateModeSettings(preferenceStore)
    val stickers: StickerRepository = CoreStickerRepository(client)
    val comments = CoreCommentsRepository(client)

    val stories: app.orbitle.data.StoriesRepository = app.orbitle.data.CoreStoriesRepository(client)
    val mediaSaver = DownloadsSaver()

    private val localMarks = object : DraftStore, ChatLocalMarks {
        private fun account() = client.store.state.value.me ?: 0L
        private fun key(chatId: String) = "draft.${account()}.$chatId"
        override fun get(chatId: String): String? = prefs.getString(key(chatId), null)?.substringAfter('\t')
        override fun put(chatId: String, text: String) {
            prefs.edit().apply {
                if (text.isBlank()) remove(key(chatId)) else putString(key(chatId), "${System.currentTimeMillis()}\t$text")
            }.apply()
        }
        override fun drafts(): Map<String, ChatDraft> {
            val prefix = "draft.${account()}."
            return prefs.all.mapNotNull { (k, v) ->
                if (!k.startsWith(prefix) || v !is String) return@mapNotNull null
                val time = v.substringBefore('\t').toLongOrNull() ?: 0L
                val text = v.substringAfter('\t').trim()
                if (text.isEmpty()) null else k.removePrefix(prefix) to ChatDraft(text, time)
            }.toMap()
        }
        override var markedUnread: Set<String>
            get() = prefs.getStringSet("unread.${account()}", emptySet())
            set(value) { prefs.edit().putStringSet("unread.${account()}", value).apply() }
    }

    val drafts: DraftStore = localMarks
    val chatMarks: ChatLocalMarks = localMarks

    val stickerRecents = object : RecentStickerStore {
        override var recentEmoji: List<String>
            get() = prefs.getString("recent.emoji", null)?.split('\n')?.filter { it.isNotEmpty() }.orEmpty()
            set(value) { prefs.edit().putString("recent.emoji", value.joinToString("\n")).apply() }
        override var recentStickers: List<Sticker>
            get() = prefs.getString("recent.stickers", null)?.lines()?.mapNotNull(::decodeSticker).orEmpty()
            set(value) { prefs.edit().putString("recent.stickers", value.joinToString("\n", transform = ::encodeSticker)).apply() }

        private fun encodeSticker(s: Sticker) = listOf(s.id, s.url, s.lottieUrl.orEmpty(), s.width?.toString().orEmpty(), s.height?.toString().orEmpty()).joinToString("\t")
        private fun decodeSticker(line: String): Sticker? {
            val p = line.split('\t')
            if (p.size < 2 || p[0].isEmpty()) return null
            return Sticker(p[0], p[1], p.getOrNull(2)?.takeIf { it.isNotEmpty() }, null, p.getOrNull(3)?.toIntOrNull(), p.getOrNull(4)?.toIntOrNull())
        }
    }

    val callMarks = object : CallMarks {
        private fun key(name: String) = "calls.${client.store.state.value.me ?: 0}.$name"
        override var lastSeenMs: Long?
            get() = prefs.getLong(key("lastSeen"), -1).takeIf { it >= 0 }
            set(value) {
                prefs.edit().apply { if (value == null) remove(key("lastSeen")) else putLong(key("lastSeen"), value) }.apply()
            }
        override var hiddenIds: Set<String>
            get() = prefs.getStringSet(key("hidden"), emptySet())
            set(value) { prefs.edit().putStringSet(key("hidden"), value).apply() }
    }

    val recentSearches = PreferenceRecentSearches(preferenceStore)

    /** Ограничения нового сеанса: отметка входа для панели на главном экране и строки в настройках. */
    val accountLimits = app.orbitle.data.AccountLimitsStore(preferenceStore)

    private val userIds = object : UserIdStore {
        override var lastUserId: String?
            get() = prefs.getString(KEY_LAST_USER, null)
            set(value) {
                prefs.edit().apply { if (value == null) remove(KEY_LAST_USER) else putString(KEY_LAST_USER, value) }.apply()
            }
    }

    val session = SessionManager(
        core = MaxCoreGateway(client),
        scope = scope,
        userIds = userIds,
        onSignedIn = {
            runCatching { chats.refresh() }
            runCatching { account.reload() }
        },
        onSignedOut = {
            chats.clear()
            calls.clear()
            recentSearches.clear()
            accountLimits.clear()
        },
        onFreshSession = { accountLimits.grant(it) },
    )

    private companion object {
        const val CORE_NAMESPACE = "orbitle-desktop"
        const val KEY_LAST_USER = "lastUserId"
        /**
         * Сообщений одного чата в сторе ядра: `0` — без предела. Стор при переполнении выбрасывает
         * самые старые, то есть как раз страницы, до которых долистал читатель, — с пределом лента
         * упиралась в него и дальше не листалась, а окно перехода к далёкому сообщению пропадало
         * сразу после загрузки. Стор живёт только в памяти, до выхода из приложения.
         */
        const val MESSAGE_LIMIT = 0
    }
}
