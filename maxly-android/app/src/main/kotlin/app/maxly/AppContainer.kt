package app.maxly

import android.content.Context
import app.maxly.data.AccountRepository
import app.maxly.data.AppearanceSettings
import app.maxly.data.CallRepository
import app.maxly.data.ContactRepository
import app.maxly.data.CoreCallRepository
import app.maxly.data.CoreContactRepository
import app.maxly.data.CoreSessionRepository
import app.maxly.data.CoreProfileRepository
import app.maxly.data.ProfileRepository
import app.maxly.data.PreferenceStore
import app.maxly.data.SessionRepository
import app.maxly.presentation.calls.CallMarks
import app.maxly.presentation.chat.MessageFiles
import app.maxly.presentation.chat.DraftStore
import app.maxly.presentation.chatlist.ChatLocalMarks
import app.maxly.presentation.chatlist.PreferenceRecentSearches
import app.maxly.domain.ChatDraft
import app.maxly.data.CoreStickerRepository
import app.maxly.data.RecentStickerStore
import app.maxly.data.StickerRepository
import app.maxly.domain.Sticker
import app.maxly.presentation.chat.VoicePlayer
import app.maxly.media.ExoVoicePlayer
import app.maxly.media.FileDownloader
import app.maxly.data.ChatRepository
import app.maxly.data.CoreAccountRepository
import app.maxly.data.CoreChatRepository
import app.maxly.data.CoreMessageRepository
import app.maxly.data.MessageRepository
import app.maxly.data.MaxCoreGateway
import app.maxly.data.SessionManager
import app.maxly.data.UserIdStore
import com.maxly.shared.MaxClient
import com.maxly.shared.MaxClientConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** Зависимости приложения: одно ядро, одна сессия, репозитории над стором ядра. */
class AppContainer(context: Context) {
    /** Корутины приложения; исключение в них пишется в журнал и отчёт, а не роняет процесс. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate + app.maxly.diagnostics.Diagnostics.coroutineHandler)

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

    val folders: app.maxly.data.FolderRepository = app.maxly.data.CoreFolderRepository(client)

    val sessions: SessionRepository = CoreSessionRepository(client)
    val storage: app.maxly.data.StorageRepository = app.maxly.media.CacheStorage(context.applicationContext)

    val profiles: ProfileRepository = CoreProfileRepository(client)

    /** User-Agent сессии для CDN: адреса медиа выданы под Android-клиента. */
    private val mediaUserAgent: () -> String = { client.config.userAgent.httpUserAgent }

    val voicePlayer: VoicePlayer = ExoVoicePlayer(context.applicationContext, scope, mediaUserAgent)

    private val downloader = FileDownloader(context.applicationContext, mediaUserAgent)

    val files: MessageFiles = object : MessageFiles {
        override fun cached(fileId: String, name: String): String? = downloader.cached(fileId, name)?.absolutePath
        override suspend fun download(url: String, fileId: String, name: String, progress: (Float) -> Unit): String =
            downloader.download(url, fileId, name, progress).absolutePath
    }

    /** Источник Media3 для видео с тем же User-Agent. */
    fun videoSourceUserAgent(): String = mediaUserAgent()

    private val prefs = context.getSharedPreferences("maxly", Context.MODE_PRIVATE)

    private val preferenceStore = object : PreferenceStore {
        override fun get(key: String): String? = prefs.getString(key, null)
        override fun put(key: String, value: String) = prefs.edit().putString(key, value).apply()
        override fun remove(key: String) = prefs.edit().remove(key).apply()
    }

    val appearance = AppearanceSettings(preferenceStore)

    /** Телефонная книга устройства: только чтение, по нажатию на экране контактов. */
    val addressBook: app.maxly.data.AddressBook = app.maxly.contacts.AndroidAddressBook(context.applicationContext)

    /** Модель доступа к телефонной книге; помнит в настройках, что системный запрос уже был. */
    /** Книга устройства — ядру, для имён людей из неё. */
    val addressBookSink: app.maxly.data.AddressBookSink = app.maxly.data.CoreAddressBookSink(client)

    fun phoneBookModel(): app.maxly.presentation.contacts.PhoneBookViewModel =
        app.maxly.presentation.contacts.PhoneBookViewModel(addressBook, contacts, { messages.currentUserId }, preferenceStore, addressBookSink)

    /** Разрешение на книгу при прошлой сверке; `null` — сверки ещё не было. */
    private var bookGranted: Boolean? = null

    /**
     * Сверка с разрешением при возврате в приложение: появилось — книга читается и уходит ядру,
     * отозвали — ядру уходит пустая книга. Без перемен книга заново не читается (это делает
     * «обновить» на экране контактов), если только ядро её не забыло.
     */
    fun syncAddressBook(granted: Boolean) {
        // Выход из аккаунта стирает книгу в ядре: тогда её надо отдать снова.
        if (bookGranted == granted && (!granted || client.store.state.value.addressBook.isNotEmpty())) return
        bookGranted = granted
        if (!granted) {
            addressBookSink.publish(emptyList())
            return
        }
        scope.launch {
            try {
                addressBookSink.publish(addressBook.entries())
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (_: Exception) {
                bookGranted = null
            }
        }
    }

    /** Приватный режим: только на этом устройстве. */
    val privateMode = app.maxly.data.PrivateModeSettings(preferenceStore)

    /**
     * Режим призрака и отметки о прочтении — флаги ядра; глушит активность ядро, не приложение.
     * Флаги прежней локальной заглушки один раз переносятся в ядро.
     */
    val ghostMode: app.maxly.data.GhostModeRepository = app.maxly.data.CoreGhostModeRepository(client, scope, preferenceStore)

    /** «Показывать мой онлайн» в своём профиле: только на этом устройстве. */
    val ownPresence = app.maxly.data.OwnPresenceSettings(preferenceStore)

    val stickers: StickerRepository = CoreStickerRepository(client)

    val comments: app.maxly.data.CommentsRepository = app.maxly.data.CoreCommentsRepository(client)

    val stories: app.maxly.data.StoriesRepository = app.maxly.data.CoreStoriesRepository(client)
    val mediaSaver: app.maxly.presentation.chat.MediaSaver = app.maxly.media.MediaStoreSaver(context)

    /** Черновики чатов и ручные пометки «непрочитано»: свои у каждого аккаунта. */
    private val localMarks = object : DraftStore, ChatLocalMarks {
        private fun account() = client.store.state.value.me ?: 0
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
            get() = prefs.getStringSet("unread.${account()}", emptySet()).orEmpty().toSet()
            set(value) = prefs.edit().putStringSet("unread.${account()}", value).apply()
    }

    val drafts: DraftStore = localMarks
    /** Черновики на сервере: отложенная отправка переживает закрытие чата. */
    val draftSync = app.maxly.presentation.chat.DraftSync(scope, app.maxly.data.CoreDraftRepository(client))
    val chatMarks: ChatLocalMarks = localMarks

    /** Недавние эмодзи и стикеры панели. */
    val stickerRecents = object : RecentStickerStore {
        override var recentEmoji: List<String>
            get() = prefs.getString("recent.emoji", null)?.split('\n')?.filter { it.isNotEmpty() }.orEmpty()
            set(value) = prefs.edit().putString("recent.emoji", value.joinToString("\n")).apply()
        override var recentStickers: List<Sticker>
            get() = prefs.getString("recent.stickers", null)?.lines()?.mapNotNull(::decodeSticker).orEmpty()
            set(value) = prefs.edit().putString("recent.stickers", value.joinToString("\n", transform = ::encodeSticker)).apply()

        private fun encodeSticker(s: Sticker) = listOf(s.id, s.url, s.lottieUrl.orEmpty(), s.width?.toString().orEmpty(), s.height?.toString().orEmpty()).joinToString("\t")
        private fun decodeSticker(line: String): Sticker? {
            val p = line.split('\t')
            if (p.size < 2 || p[0].isEmpty()) return null
            return Sticker(p[0], p[1], p.getOrNull(2)?.takeIf { it.isNotEmpty() }, null, p.getOrNull(3)?.toIntOrNull(), p.getOrNull(4)?.toIntOrNull())
        }
    }

    /** Просмотренные и скрытые звонки: свои у каждого аккаунта. */
    val callMarks = object : CallMarks {
        private fun key(name: String) = "calls.${client.store.state.value.me ?: 0}.$name"
        override var lastSeenMs: Long?
            get() = prefs.getLong(key("lastSeen"), -1).takeIf { it >= 0 }
            set(value) {
                prefs.edit().apply { if (value == null) remove(key("lastSeen")) else putLong(key("lastSeen"), value) }.apply()
            }
        override var hiddenIds: Set<String>
            get() = prefs.getStringSet(key("hidden"), emptySet()).orEmpty().toSet()
            set(value) = prefs.edit().putStringSet(key("hidden"), value).apply()
    }

    val recentSearches = PreferenceRecentSearches(preferenceStore)

    /** Звонки: один на приложение. Разговор — WebRTC, сигналы — ws2 сервера звонков. */
    val callCenter = app.maxly.presentation.calls.CallCenter(
        service = app.maxly.data.calls.CoreCallService(client),
        engine = { connection, role, isGroup, expiresAtMs ->
            app.maxly.data.calls.CallSession(
                connection, role, isGroup,
                media = app.maxly.calls.AndroidCallMedia(context.applicationContext),
                connector = { app.maxly.data.calls.OkHttpWs2Socket.connect(it) },
                scope = scope,
                expiresAtMs = expiresAtMs,
            )
        },
        scope = scope,
        lookup = ::callPeer,
    ).also { center ->
        app.maxly.calls.AndroidWebRtc.init(context.applicationContext)
        app.maxly.calls.CallPermissions.init(context.applicationContext)
        // Журнал звонков (CallLog) пишет в общий журнал приложения: файл и logcat «Maxly/calls».
        // Журнал звонков читается заново, когда сервер успел записать звонок.
        center.onCallEnded = {
            scope.launch {
                kotlinx.coroutines.delay(2_000)
                runCatching { calls.refresh() }
            }
        }
    }

    /** Уведомление входящего, служба идущего звонка и датчик приближения. */
    val callSystem = app.maxly.calls.AndroidCallSystem(context.applicationContext, callCenter, scope)

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
        // Профиль поменяли на другом устройстве (пуш 159): перечитать свой профиль.
        scope.launch { account.profileChanges.collect { runCatching { account.reload() } } }
    }

    init {
        // Флаг активности для ядра: приложение на переднем плане при разблокированном экране или
        // идёт звонок. Режим призрака ядро сводит с ним само.
        val foreground = androidx.lifecycle.ProcessLifecycleOwner.get().lifecycle.currentStateFlow
            .map { it.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED) }
        val active = combine(
            foreground,
            screenUnlocked(context.applicationContext),
            callCenter.state.map(app.maxly.presentation.common.AppActivity::inCall),
            app.maxly.presentation.common.AppActivity::android,
        )
        app.maxly.presentation.common.AppActivity.report(scope, active) { client.setInteractive(it) }
    }

    private companion object {
        const val CORE_NAMESPACE = "maxly"
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
