package app.orbitle

import android.content.Context
import app.orbitle.data.AccountRepository
import app.orbitle.data.AppearanceSettings
import app.orbitle.data.CallRepository
import app.orbitle.data.ContactRepository
import app.orbitle.data.CoreCallRepository
import app.orbitle.data.CoreContactRepository
import app.orbitle.data.CoreSessionRepository
import app.orbitle.data.CoreProfileRepository
import app.orbitle.data.ProfileRepository
import app.orbitle.data.PreferenceStore
import app.orbitle.data.SessionRepository
import app.orbitle.presentation.calls.CallMarks
import app.orbitle.presentation.chat.MessageFiles
import app.orbitle.presentation.chat.DraftStore
import app.orbitle.presentation.chatlist.ChatLocalMarks
import app.orbitle.domain.ChatDraft
import app.orbitle.data.CoreStickerRepository
import app.orbitle.data.RecentStickerStore
import app.orbitle.data.StickerRepository
import app.orbitle.domain.Sticker
import app.orbitle.presentation.chat.VoicePlayer
import app.orbitle.media.ExoVoicePlayer
import app.orbitle.media.FileDownloader
import app.orbitle.data.ChatRepository
import app.orbitle.data.CoreAccountRepository
import app.orbitle.data.CoreChatRepository
import app.orbitle.data.CoreMessageRepository
import app.orbitle.data.MessageRepository
import app.orbitle.data.MaxCoreGateway
import app.orbitle.data.SessionManager
import app.orbitle.data.UserIdStore
import com.max.shared.MaxClient
import com.max.shared.MaxClientConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Зависимости приложения: одно ядро, одна сессия, репозитории над стором ядра. */
class AppContainer(context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    val client: MaxClient = MaxClient(MaxClientConfig(namespace = CORE_NAMESPACE, messageLimit = MESSAGE_LIMIT))

    val chats: ChatRepository = CoreChatRepository(client)

    val account: AccountRepository = CoreAccountRepository(client)

    val messages: MessageRepository = CoreMessageRepository(client)

    val calls: CallRepository = CoreCallRepository(client)

    val contacts: ContactRepository = CoreContactRepository(client)

    val folders: app.orbitle.data.FolderRepository = app.orbitle.data.CoreFolderRepository(client)

    val sessions: SessionRepository = CoreSessionRepository(client)
    val storage: app.orbitle.data.StorageRepository = app.orbitle.media.CacheStorage(context.applicationContext)

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

    private val prefs = context.getSharedPreferences("orbitle", Context.MODE_PRIVATE)

    val appearance = AppearanceSettings(object : PreferenceStore {
        override fun get(key: String): String? = prefs.getString(key, null)
        override fun put(key: String, value: String) = prefs.edit().putString(key, value).apply()
    })

    val stickers: StickerRepository = CoreStickerRepository(client)

    val comments: app.orbitle.data.CommentsRepository = app.orbitle.data.CoreCommentsRepository(client)
    val mediaSaver: app.orbitle.presentation.chat.MediaSaver = app.orbitle.media.MediaStoreSaver(context)

    /** Черновики чатов и ручные пометки «непрочитано»: свои у каждого аккаунта. */
    private val localMarks = object : DraftStore, ChatLocalMarks {
        private fun account() = client.store.state.value.me ?: 0
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
            get() = prefs.getStringSet("unread.${account()}", emptySet()).orEmpty().toSet()
            set(value) = prefs.edit().putStringSet("unread.${account()}", value).apply()
    }

    val drafts: DraftStore = localMarks
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
        },
    )

    private companion object {
        const val CORE_NAMESPACE = "orbitle"
        const val KEY_LAST_USER = "lastUserId"
        /** Сколько сообщений одного чата держит стор ядра: хватает на долгую прокрутку истории. */
        const val MESSAGE_LIMIT = 3_000
    }
}
