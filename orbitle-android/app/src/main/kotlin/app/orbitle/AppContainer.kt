package app.orbitle

import android.content.Context
import app.orbitle.data.AccountRepository
import app.orbitle.data.AppearanceSettings
import app.orbitle.data.CallRepository
import app.orbitle.data.ContactRepository
import app.orbitle.data.CoreCallRepository
import app.orbitle.data.CoreContactRepository
import app.orbitle.data.CoreSessionRepository
import app.orbitle.data.PreferenceStore
import app.orbitle.data.SessionRepository
import app.orbitle.presentation.calls.CallMarks
import app.orbitle.presentation.chat.MessageFiles
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

    val sessions: SessionRepository = CoreSessionRepository(client)

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
