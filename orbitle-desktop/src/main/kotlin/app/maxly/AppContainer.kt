package app.maxly

import app.maxly.data.AccountRepository
import app.maxly.data.AppearanceSettings
import app.maxly.data.CallRepository
import app.maxly.data.ChatRepository
import app.maxly.data.ContactRepository
import app.maxly.data.CoreAccountRepository
import app.maxly.data.CoreCallRepository
import app.maxly.data.CoreChatRepository
import app.maxly.data.CoreCommentsRepository
import app.maxly.data.CoreContactRepository
import app.maxly.data.CoreFolderRepository
import app.maxly.data.CoreMessageRepository
import app.maxly.data.CoreProfileRepository
import app.maxly.data.CoreSessionRepository
import app.maxly.data.CoreStickerRepository
import app.maxly.data.FolderRepository
import app.maxly.data.MaxCoreGateway
import app.maxly.data.MessageRepository
import app.maxly.data.PreferenceStore
import app.maxly.data.PrivateModeSettings
import app.maxly.data.ProfileRepository
import app.maxly.data.RecentStickerStore
import app.maxly.data.SessionManager
import app.maxly.data.SessionRepository
import app.maxly.data.StickerRepository
import app.maxly.data.UserIdStore
import app.maxly.domain.ChatDraft
import app.maxly.domain.Sticker
import app.maxly.media.CacheStorage
import app.maxly.media.DesktopVoicePlayer
import app.maxly.media.DownloadsSaver
import app.maxly.media.FileDownloader
import app.maxly.platform.AppPaths
import app.maxly.platform.FilePrefs
import app.maxly.presentation.calls.CallMarks
import app.maxly.presentation.chat.DraftStore
import app.maxly.presentation.chat.MessageFiles
import app.maxly.presentation.chat.VoicePlayer
import app.maxly.presentation.chatlist.ChatLocalMarks
import app.maxly.presentation.chatlist.PreferenceRecentSearches
import com.maxly.shared.MaxClient
import com.maxly.shared.MaxClientConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map

/** Зависимости окна: одно ядро, одна сессия, репозитории над стором ядра. Токен хранит само ядро. */
class AppContainer {
    /** Исключение в корутине приложения пишется в журнал и отчёт, но не роняет процесс. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate + app.maxly.diagnostics.DesktopDiagnostics.coroutineHandler)

    /**
     * Без догрузки дыр истории после переподключения (`fillGapsOnReconnect`), как на iOS: ядро
     * листало историю всех чатов подряд, до 16 страниц на чат, и сервер отвечал
     * `too.many.requests` — заодно и на историю открытого чата. Открытый чат сам берёт свежую
     * страницу, старое догружается прокруткой. Диагностика ядра (пуши черновиков, уже без
     * текста) пишется в журнал приложения.
     */
    val client: MaxClient = MaxClient(
        MaxClientConfig(namespace = CORE_NAMESPACE, messageLimit = MESSAGE_LIMIT, fillGapsOnReconnect = false),
    ).apply { onDiagnostic = { line -> app.maxly.data.diagnostics.AppLog.i("core", line) } }

    val chats: ChatRepository = CoreChatRepository(client)
    val chatAdmin: app.maxly.data.ChatAdminRepository = app.maxly.data.CoreChatAdminRepository(client)
    val account: AccountRepository = CoreAccountRepository(client)
    val messages: MessageRepository = CoreMessageRepository(client)
    val calls: CallRepository = CoreCallRepository(client, scope)
    val contacts: ContactRepository = CoreContactRepository(client)
    /** Телефонной книги на компьютере нет: вход «Найти друзей из контактов» не показывается. */
    val addressBook: app.maxly.data.AddressBook = app.maxly.platform.DesktopAddressBook
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
        override fun remove(key: String) = prefs.edit().remove(key).apply()
    }

    val appearance = AppearanceSettings(preferenceStore)
    /** Где было окно, когда его закрыли. */
    val windowPlacement = app.maxly.platform.WindowPlacementStore(preferenceStore)
    val keyboard = app.maxly.ui.keys.KeyboardSettings(preferenceStore)
    val privateMode = PrivateModeSettings(preferenceStore)

    /**
     * Режим призрака и отметки о прочтении — флаги ядра; глушит активность ядро, не приложение.
     * Флаги прежней локальной заглушки один раз переносятся в ядро.
     */
    val ghostMode: app.maxly.data.GhostModeRepository = app.maxly.data.CoreGhostModeRepository(client, scope, preferenceStore)

    /** «Показывать мой онлайн» в своём профиле: только на этом устройстве. */
    val ownPresence = app.maxly.data.OwnPresenceSettings(preferenceStore)

    /** Свёрнуто ли окно, в фокусе ли и был ли в нём ввод. Пишет Main.kt. */
    val window = app.maxly.platform.WindowActivity()

    /** Окно не свёрнуто: пока свёрнуто, свой статус не опрашивается. */
    val windowShown: kotlinx.coroutines.flow.StateFlow<Boolean> get() = window.shown
    val stickers: StickerRepository = CoreStickerRepository(client)
    val comments = CoreCommentsRepository(client)

    val stories: app.maxly.data.StoriesRepository = app.maxly.data.CoreStoriesRepository(client)
    val mediaSaver = DownloadsSaver()

    private val localMarks = object : DraftStore, ChatLocalMarks {
        private fun account() = client.store.state.value.me ?: 0L
        private fun key(chatId: String) = "draft.${account()}.$chatId"
        override fun get(chatId: String): String? = load(chatId)?.text
        override fun put(chatId: String, text: String) = save(chatId, text.takeIf { it.isNotBlank() }?.let { ChatDraft(it, System.currentTimeMillis()) })
        override fun load(chatId: String): ChatDraft? = prefs.getString(key(chatId), null)?.let(app.maxly.data.DraftCodec::decode)
        override fun save(chatId: String, draft: ChatDraft?) {
            prefs.edit().apply {
                if (draft == null || draft.isEmpty) remove(key(chatId)) else putString(key(chatId), app.maxly.data.DraftCodec.encode(draft))
            }.apply()
        }
        override fun drafts(): Map<String, ChatDraft> {
            val prefix = "draft.${account()}."
            return prefs.all.mapNotNull { (k, v) ->
                if (!k.startsWith(prefix) || v !is String) return@mapNotNull null
                app.maxly.data.DraftCodec.decode(v)?.let { k.removePrefix(prefix) to it }
            }.toMap()
        }
        override var markedUnread: Set<String>
            get() = prefs.getStringSet("unread.${account()}", emptySet())
            set(value) { prefs.edit().putStringSet("unread.${account()}", value).apply() }
    }

    val drafts: DraftStore = localMarks
    /** Черновики на сервере: отложенная отправка переживает закрытие чата. */
    val draftSync = app.maxly.presentation.chat.DraftSync(scope, app.maxly.data.CoreDraftRepository(client))
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

    /** Звонки: один на приложение. Разговор — webrtc-java, сигналы — ws2 сервера звонков. */
    val callCenter = app.maxly.presentation.calls.CallCenter(
        service = app.maxly.data.calls.CoreCallService(client),
        engine = { connection, role, isGroup, expiresAtMs ->
            app.maxly.data.calls.CallSession(
                connection, role, isGroup,
                media = app.maxly.calls.DesktopCallMedia(),
                connector = { app.maxly.data.calls.OkHttpWs2Socket.connect(it) },
                scope = scope,
                expiresAtMs = expiresAtMs,
            )
        },
        scope = scope,
        lookup = ::callPeer,
    ).also { center ->
        app.maxly.data.calls.CallLog.sink = { level, message -> System.err.println("[calls] $level $message") }
        // Журнал звонков читается заново, когда сервер успел записать звонок.
        center.onCallEnded = {
            scope.launch {
                delay(2_000)
                runCatching { calls.refresh() }
            }
        }
    }

    /** Имя и аватар пользователя Max для экрана звонка: из стора ядра или с сервера. */
    private suspend fun callPeer(userId: String): app.maxly.presentation.calls.CallPeerInfo? {
        val id = userId.toLongOrNull() ?: return null
        val user = client.store.state.value.users[id]
            ?: runCatching { MaxCoreGateway.read { client.loadUsers(listOf(id)) } }.getOrNull()?.firstOrNull()
            ?: return null
        return app.maxly.presentation.calls.CallPeerInfo(userId, user.displayName.orEmpty(), user.baseUrl?.takeIf { it.isNotBlank() })
    }

    /** Ограничения нового сеанса: отметка входа для панели на главном экране и строки в настройках. */
    val accountLimits = app.maxly.data.AccountLimitsStore(preferenceStore)

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
            scope.launch { callCenter.deactivate() }
            // Места в лентах и куски истории — прежнего аккаунта (выход, отказ токена, смена аккаунта).
            app.maxly.presentation.chat.HistoryRanges.clear()
            app.maxly.presentation.chat.ScrollMemory.clear()
            chats.clear()
            calls.clear()
            recentSearches.clear()
            accountLimits.clear()
        },
        onFreshSession = { accountLimits.grant(it) },
    )

    init {
        // Состояние соединения — в журнал: по нему видно, был ли клиент в сети в момент беды.
        scope.launch { session.connection.collect { app.maxly.data.diagnostics.AppLog.i("net", "Соединение: $it") } }
        // Профиль поменяли на другом устройстве (пуш 159): перечитать свой профиль.
        scope.launch { account.profileChanges.collect { runCatching { account.reload() } } }
    }

    init {
        // Флаг активности для ядра: окно видно, в фокусе и в нём недавно был ввод, или идёт звонок
        // (тогда и в свёрнутом окне). Режим призрака ядро сводит с ним само.
        val active = combine(
            window.active,
            callCenter.state.map(app.maxly.presentation.common.AppActivity::inCall),
            app.maxly.presentation.common.AppActivity::desktop,
        )
        app.maxly.presentation.common.AppActivity.report(scope, active) { client.setInteractive(it) }
    }

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
