package app.orbitle.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.data.MessageRepository
import app.orbitle.domain.CallContent
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.ChatType
import app.orbitle.domain.FileContent
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageForward
import app.orbitle.domain.MessageReaction
import app.orbitle.domain.MessageReply
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.VoiceContent
import app.orbitle.presentation.chat.ChatViewModel
import app.orbitle.ui.chat.ChatScreen
import app.orbitle.ui.theme.OrbitleTheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import app.orbitle.data.AppearanceSettings
import app.orbitle.data.CallRepository
import app.orbitle.data.ContactRepository
import app.orbitle.data.PreferenceStore
import app.orbitle.domain.Account
import app.orbitle.domain.CallOutcome
import app.orbitle.domain.CallRecord
import app.orbitle.domain.ChatWallpaper
import app.orbitle.domain.Contact
import app.orbitle.presentation.calls.CallsViewModel
import app.orbitle.presentation.contacts.ContactsViewModel
import app.orbitle.ui.calls.CallsScreen
import app.orbitle.ui.components.ChatBackdrop
import app.orbitle.ui.components.LocalChatBackdrop
import app.orbitle.ui.contacts.ContactsScreen
import app.orbitle.ui.settings.AppearanceScreen
import app.orbitle.ui.settings.SettingsScreen
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/**
 * Отладочный экран: `adb shell am start -n app.orbitle.android.debug/app.orbitle.demo.DemoActivity --es screen chat`.
 * Показывает экраны на выдуманных данных, чтобы проверить вёрстку без аккаунта.
 */
class DemoActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val group = intent.getStringExtra("type") == "group"
        val screen = intent.getStringExtra("screen") ?: "chat"
        val appearance = AppearanceSettings(object : PreferenceStore {
            private val map = mutableMapOf<String, String>()
            override fun get(key: String) = map[key]
            override fun put(key: String, value: String) { map[key] = value }
        })
        intent.getStringExtra("wallpaper")?.let { appearance.setWallpaper(ChatWallpaper.valueOf(it)) }
        setContent {
            val prefs by appearance.state.collectAsState()
            val dark = isSystemInDarkTheme()
            OrbitleTheme {
                CompositionLocalProvider(LocalChatBackdrop provides ChatBackdrop(prefs.wallpaper, dark)) {
                    when (screen) {
                        "calls" -> CallsScreen(viewModel { CallsViewModel(DemoCalls()) }, onOpenChat = {})
                        "contacts" -> ContactsScreen(viewModel { ContactsViewModel(DemoContacts(), { "1" }) }, onOpen = {})
                        "appearance" -> AppearanceScreen(appearance, onBack = { finish() })
                        "settings" -> SettingsScreen(Account("1", "Иван", "Петров", "+79001234567", null), onAbout = {}, onLogout = {})
                        else -> {
                            val model = viewModel { ChatViewModel("10", DemoMessages(group)) }
                            ChatScreen(model, onBack = { finish() })
                        }
                    }
                }
            }
        }
    }
}

private class DemoMessages(group: Boolean) : MessageRepository {
    private val now = System.currentTimeMillis()
    private val minute = 60_000L
    override val currentUserId = "1"
    private val chat = Chat(id = "10", title = if (group) "Дача 🌲" else "Анна Смирнова", type = if (group) ChatType.GROUP else ChatType.PRIVATE, updatedAtMs = now, isOnline = true)
    private val header = MutableStateFlow<ChatHeaderInfo?>(ChatHeaderInfo(chat, participants = 12))
    private val list = MutableStateFlow(
        listOf(
            msg("1", "2", now - 26 * 60 * minute, "Привет! Как дела? Посмотри https://max.ru", name = "Анна"),
            msg("2", "1", now - 25 * 60 * minute, "Привет, всё отлично 🙂", read = true),
            msg("3", "3", now - 50 * minute, "", name = "Борис", content = MessageContent(attachments = listOf(ChatAttachment.Voice(VoiceContent("v", null, listOf(10, 40, 90, 160, 220, 120, 60, 30, 80, 200, 150, 70), 14_000))))),
            msg("4", "3", now - 49 * minute, "Это голосовое про выходные. А вот отчёт:", name = "Борис"),
            msg("5", "3", now - 48 * minute, "", name = "Борис", content = MessageContent(attachments = listOf(ChatAttachment.File(FileContent("f", "Отчёт за сентябрь.pdf", 1_536_000))))),
            msg("6", "1", now - 30 * minute, "Отлично, спасибо! Посмотрю вечером и отпишусь", content = MessageContent(reply = MessageReply("4", "Борис", "Это голосовое про выходные. А вот отчёт:", MessageReply.Kind.TEXT), reactions = listOf(MessageReaction("👍", 2, true), MessageReaction("🔥", 1, false))), read = true),
            msg("7", "2", now - 20 * minute, "", name = "Анна", content = MessageContent(attachments = listOf(ChatAttachment.Call(CallContent("c", 0, false, "MISSED"))))),
            msg("8", "2", now - 10 * minute, "Пересылаю важное", name = "Анна", content = MessageContent(forward = MessageForward("Канал новостей", "Пересылаю важное"), edited = true)),
            msg("9", "1", now - 2 * minute, "Уже в пути, буду через 10 минут"),
        ),
    )

    private fun msg(id: String, author: String, at: Long, text: String, name: String = "Я", content: MessageContent = MessageContent.empty, read: Boolean = false) =
        Message(id, "10", author, text, at, MessageStatus.SENT, content, name, null, read)

    override fun messages(chatId: String): Flow<List<Message>> = list
    override fun header(chatId: String): Flow<ChatHeaderInfo?> = header
    override suspend fun loadLatest(chatId: String) = Unit
    override suspend fun loadOlder(chatId: String) = false
    override suspend fun send(chatId: String, text: String, replyTo: String?) {
        list.update { it + msg("${it.size + 100}", "1", System.currentTimeMillis(), text) }
    }
    override suspend fun retry(chatId: String, localId: String) = Unit
    override fun discard(chatId: String, localId: String) = Unit
    override suspend fun edit(chatId: String, messageId: String, text: String) {
        list.update { all -> all.map { if (it.id == messageId) it.copy(text = text, content = it.content.copy(edited = true)) else it } }
    }
    override suspend fun delete(chatId: String, messageIds: List<String>, forEveryone: Boolean) {
        list.update { all -> all.filterNot { it.id in messageIds } }
    }
    override suspend fun markRead(chatId: String, messageId: String) = Unit
    override suspend fun react(chatId: String, messageId: String, emoji: String?) {
        list.update { all ->
            all.map { m ->
                if (m.id != messageId) return@map m
                val others = m.content.reactions.filterNot { it.mine }
                val next = if (emoji == null) others else others + MessageReaction(emoji, 1, true)
                m.copy(content = m.content.copy(reactions = next))
            }
        }
    }
    override suspend fun reactionCatalog() = listOf("👍", "❤️", "🔥", "🤣", "😭", "😍", "👏")
}

private class DemoCalls : CallRepository {
    private val now = System.currentTimeMillis()
    private val hour = 3_600_000L
    override val calls = MutableStateFlow<List<CallRecord>?>(
        listOf(
            CallRecord("1", "2", "Анна Смирнова", outgoing = false, outcome = CallOutcome.MISSED, timeMs = now - hour),
            CallRecord("2", "2", "Анна Смирнова", outgoing = false, outcome = CallOutcome.MISSED, timeMs = now - 2 * hour),
            CallRecord("3", "3", "Борис", outgoing = true, outcome = CallOutcome.ANSWERED, timeMs = now - 5 * hour, durationMs = 42_000),
            CallRecord("4", "4", "Мама", outgoing = false, outcome = CallOutcome.ANSWERED, isVideo = true, timeMs = now - 30 * hour),
            CallRecord("5", "5", "Групповой звонок", isGroup = true, outgoing = true, outcome = CallOutcome.CANCELLED, timeMs = now - 80 * hour),
        ),
    )
    override suspend fun refresh() = Unit
    override fun clear() = Unit
}

private class DemoContacts : ContactRepository {
    private val now = System.currentTimeMillis()
    override val contacts = MutableStateFlow(
        listOf(
            Contact("2", "Анна", "Смирнова", "79001112233", isOnline = true),
            Contact("3", "Борис", "Иванов", "79002223344", lastSeenMs = now - 5 * 60_000),
            Contact("4", "Вера", lastSeenMs = now - 26 * 3_600_000),
            Contact("5", "Alex", "Brown"),
            Contact("6", "Ёлка", "Новогодняя"),
            Contact("7", "Мама", isOnline = true),
        ),
    )
    override suspend fun sync() = Unit
}
