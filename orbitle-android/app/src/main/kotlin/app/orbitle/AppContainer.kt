package app.orbitle

import android.content.Context
import app.orbitle.data.AccountRepository
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

    private val prefs = context.getSharedPreferences("orbitle", Context.MODE_PRIVATE)

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
        onSignedOut = { chats.clear() },
    )

    private companion object {
        const val CORE_NAMESPACE = "orbitle"
        const val KEY_LAST_USER = "lastUserId"
        /** Сколько сообщений одного чата держит стор ядра: хватает на долгую прокрутку истории. */
        const val MESSAGE_LIMIT = 3_000
    }
}
