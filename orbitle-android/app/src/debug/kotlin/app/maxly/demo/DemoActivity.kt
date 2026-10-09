package app.maxly.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import app.maxly.data.ChatHeaderInfo
import app.maxly.data.MessageRepository
import app.maxly.domain.CallContent
import app.maxly.domain.Chat
import app.maxly.domain.ChatAttachment
import app.maxly.domain.ChatType
import app.maxly.domain.FileContent
import app.maxly.domain.PhotoContent
import app.maxly.media.ExoVoicePlayer
import app.maxly.presentation.profile.ProfileViewModel
import app.maxly.ui.profile.ProfileScreen
import androidx.compose.runtime.remember
import app.maxly.presentation.chat.MessageFiles
import androidx.lifecycle.lifecycleScope
import app.maxly.domain.Message
import app.maxly.domain.MessageContent
import app.maxly.domain.MessageForward
import app.maxly.domain.MessageReaction
import app.maxly.domain.MessageReply
import app.maxly.domain.MessageStatus
import app.maxly.domain.VoiceContent
import app.maxly.domain.VideoContent
import app.maxly.presentation.chat.ChatViewModel
import app.maxly.ui.chat.ChatScreen
import app.maxly.ui.chatlist.ChatListScreen
import app.maxly.presentation.chatlist.ChatListViewModel
import app.maxly.ui.theme.MaxlyTheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import app.maxly.data.AppearanceSettings
import app.maxly.data.CallRepository
import app.maxly.data.ContactRepository
import app.maxly.data.PreferenceStore
import app.maxly.domain.Account
import app.maxly.domain.CallOutcome
import app.maxly.domain.CallRecord
import app.maxly.domain.ChatWallpaper
import app.maxly.domain.Contact
import app.maxly.presentation.calls.CallsViewModel
import app.maxly.presentation.contacts.ContactsViewModel
import app.maxly.ui.calls.CallsScreen
import app.maxly.ui.components.ChatBackdrop
import app.maxly.ui.components.LocalChatBackdrop
import app.maxly.ui.contacts.ContactsScreen
import app.maxly.ui.settings.AppearanceScreen
import app.maxly.ui.settings.SettingsScreen
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/**
 * Отладочный экран: `adb shell am start -n app.orbitle.android.debug/app.maxly.demo.DemoActivity --es screen chat`.
 * Показывает экраны на выдуманных данных, чтобы проверить вёрстку без аккаунта.
 */
class DemoActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val group = intent.getStringExtra("type") == "group"
        val channel = intent.getStringExtra("type") == "channel"
        val screen = intent.getStringExtra("screen") ?: "chat"
        val appearance = AppearanceSettings(object : PreferenceStore {
            private val map = mutableMapOf<String, String>()
            override fun get(key: String) = map[key]
            override fun put(key: String, value: String) { map[key] = value }
        })
        intent.getStringExtra("wallpaper")?.let { appearance.setWallpaper(ChatWallpaper.valueOf(it)) }
        val player = ExoVoicePlayer(applicationContext, lifecycleScope, { "Orbitle demo" })
        val demoRecents = object : app.maxly.data.RecentStickerStore {
            override var recentEmoji: List<String> = listOf("🔥", "👍", "😂")
            override var recentStickers: List<app.maxly.domain.Sticker> = emptyList()
        }
        setContent {
            val prefs by appearance.state.collectAsState()
            val dark = isSystemInDarkTheme()
            MaxlyTheme {
                CompositionLocalProvider(LocalChatBackdrop provides ChatBackdrop(prefs.wallpaper, dark)) {
                    when (screen) {
                        "chats" -> ChatListScreen(viewModel { ChatListViewModel(DemoChats(), local = DemoMarks()) }, onOpenChat = {})
                        "calls" -> CallsScreen(viewModel { CallsViewModel(DemoCalls()) }, onOpenChat = {})
                        "contacts" -> ContactsScreen(viewModel { ContactsViewModel(DemoContacts(), { "1" }) }, onOpen = {})
                        "appearance" -> AppearanceScreen(appearance, onBack = { finish() })
                        "profile" -> {
                            val messages = remember { DemoMessages(group) }
                            val model = viewModel { ProfileViewModel("10", "Анна Смирнова", DemoProfiles(group), messages, player, DemoFiles(applicationContext)) }
                            ProfileScreen(model, onBack = { finish() }, onWrite = {})
                        }
                        "settings" -> {
                            val model = viewModel { app.maxly.presentation.settings.AccountSettingsViewModel(DemoAccount()) }
                            val state by model.state.collectAsState()
                            SettingsScreen(state.account, onAbout = {}, onLogout = {})
                        }
                        "profile-edit" -> app.maxly.ui.settings.ProfileEditScreen(
                            viewModel { app.maxly.presentation.settings.AccountSettingsViewModel(DemoAccount()) }, onBack = { finish() }, onLogout = { finish() },
                        )
                        "privacy" -> app.maxly.ui.settings.PrivacyScreen(
                            viewModel { app.maxly.presentation.settings.AccountSettingsViewModel(DemoAccount()) }, onBack = { finish() }, onBlocked = {},
                        )
                        "storage" -> app.maxly.ui.settings.StorageScreen(
                            viewModel { app.maxly.presentation.settings.StorageViewModel(DemoStorage()) }, onBack = { finish() },
                        )
                        "blocked" -> app.maxly.ui.settings.BlockedUsersScreen(
                            viewModel { app.maxly.presentation.settings.AccountSettingsViewModel(DemoAccount()) }, onBack = { finish() },
                        )
                        else -> {
                            val model = viewModel { ChatViewModel(
                                "10", DemoMessages(group, channel), voicePlayer = player, files = DemoFiles(applicationContext),
                                stickerRepository = DemoStickers(), stickerRecents = demoRecents, emojiSupported = app.maxly.ui.chat.EmojiSupport::canDraw,
                                comments = DemoComments(), mediaSaver = app.maxly.media.MediaStoreSaver(applicationContext),
                            ) }
                            ChatScreen(model, onBack = { finish() }, forwardTargets = {
                                val formatter = app.maxly.presentation.chatlist.ChatListFormatter()
                                DemoChats().chats.value.orEmpty().filter { it.id != "10" }.map { formatter.item(it, System.currentTimeMillis(), showDraft = false) }
                            })
                        }
                    }
                }
            }
        }
    }
}

private class DemoComments : app.maxly.data.CommentsRepository {
    private val now = System.currentTimeMillis()
    private var next = 900
    private val names = listOf("Мария", "Олег", "Светлана", "Дмитрий")
    private val all = (1..40).map { i ->
        val author = (i % 4) + 2
        Message("c$i".let { (800 + i).toString() }, "10", author.toString(), if (i == 40) "Отличная новость, ждём!" else "Комментарий номер $i", now - (41 - i) * 90_000L,
            MessageStatus.SENT, if (i == 39) MessageContent(reactions = listOf(MessageReaction("👍", 3, false))) else MessageContent.empty, names[i % 4])
    }
    override suspend fun comments(chatId: String, postId: String, beforeMs: Long?, limit: Int): List<Message> {
        kotlinx.coroutines.delay(400)
        return all.filter { beforeMs == null || it.timeMs < beforeMs }.takeLast(limit)
    }
    override suspend fun send(text: String, chatId: String, postId: String): Message {
        kotlinx.coroutines.delay(500)
        return Message((next++).toString(), chatId, "1", text, System.currentTimeMillis())
    }
    override suspend fun counts(chatId: String, postIds: List<String>) = postIds.associateWith { if (it == "9") 40 else (it.toIntOrNull() ?: 0) % 3 }
    override suspend fun setReaction(chatId: String, postId: String, commentId: String, emoji: String?) = null
}

private class DemoMarks : app.maxly.presentation.chatlist.ChatLocalMarks {
    override var markedUnread: Set<String> = setOf("12")
    override fun drafts() = mapOf("13" to app.maxly.domain.ChatDraft("Завтра в десять?", System.currentTimeMillis() - 60_000))
}

private class DemoChats : app.maxly.data.ChatRepository {
    private val now = System.currentTimeMillis()
    override val chats = kotlinx.coroutines.flow.MutableStateFlow<List<app.maxly.domain.Chat>?>(listOf(
        app.maxly.domain.Chat("10", "Анна Смирнова", app.maxly.domain.ChatType.PRIVATE, unreadCount = 2, updatedAtMs = now - 120_000, preview = "Созвонимся вечером?", pinOrder = 0, isOnline = true),
        app.maxly.domain.Chat("11", "Команда проекта", app.maxly.domain.ChatType.GROUP, unreadCount = 14, updatedAtMs = now - 300_000, preview = "Сборка готова", isMuted = true),
        app.maxly.domain.Chat("12", "Пётр", app.maxly.domain.ChatType.PRIVATE, updatedAtMs = now - 3_600_000, preview = "Спасибо!"),
        app.maxly.domain.Chat("13", "Мама", app.maxly.domain.ChatType.PRIVATE, updatedAtMs = now - 7_200_000, preview = "Позвони"),
        app.maxly.domain.Chat("14", "Новости Max", app.maxly.domain.ChatType.CHANNEL, updatedAtMs = now - 86_400_000, preview = "Обновление уже доступно", isVerified = true),
    ))
    override val folders = kotlinx.coroutines.flow.MutableStateFlow<List<app.maxly.domain.ServerFolder>>(emptyList())
    override val typing = kotlinx.coroutines.flow.MutableStateFlow<Map<String, List<app.maxly.domain.Typist>>>(emptyMap())
    override suspend fun refresh() = Unit
    override suspend fun setPinned(chatId: String, pinned: Boolean) {
        chats.value = chats.value?.map { if (it.id == chatId) it.copy(pinOrder = if (pinned) 1 else null) else it }
    }
    override suspend fun setMuted(chatId: String, muted: Boolean) {
        chats.value = chats.value?.map { if (it.id == chatId) it.copy(isMuted = muted) else it }
    }
    override suspend fun markAsRead(chatId: String) {
        chats.value = chats.value?.map { if (it.id == chatId) it.copy(unreadCount = 0) else it }
    }
    override fun clear() = Unit
}

private class DemoMessages(group: Boolean, channel: Boolean = false) : MessageRepository {
    private val now = System.currentTimeMillis()
    override suspend fun forward(chatId: String, messageId: String, targetChatId: String) = Unit
    private val minute = 60_000L
    override val currentUserId = "1"
    private val chat = when {
        channel -> Chat(id = "10", title = "Новости Max", type = ChatType.CHANNEL, updatedAtMs = now, isVerified = true, commentsEnabled = true)
        else -> Chat(id = "10", title = if (group) "Дача 🌲" else "Анна Смирнова", type = if (group) ChatType.GROUP else ChatType.PRIVATE, updatedAtMs = now, isOnline = true)
    }
    private val header = MutableStateFlow<ChatHeaderInfo?>(ChatHeaderInfo(chat, participants = 12))
    private val list = MutableStateFlow(
        listOf(
            msg("1", "2", now - 26 * 60 * minute, "Привет! Как дела? Посмотри https://max.ru", name = "Анна"),
            msg("2", "1", now - 25 * 60 * minute, "Привет, всё отлично 🙂", read = true),
            msg("3", "3", now - 50 * minute, "", name = "Борис", content = MessageContent(attachments = listOf(ChatAttachment.Voice(VoiceContent("301", "asset:///demo-voice.wav", listOf(10, 40, 90, 160, 220, 120, 60, 30, 80, 200, 150, 70), 6_000))))),
            msg("4", "3", now - 49 * minute, "Это голосовое про выходные. А вот отчёт:", name = "Борис"),
            msg("5", "3", now - 48 * minute, "", name = "Борис", content = MessageContent(attachments = listOf(ChatAttachment.File(FileContent("401", "Отчёт за сентябрь.txt", 1_536_000))))),
            msg("51", "2", now - 40 * minute, "Фото с дачи", name = "Анна", content = MessageContent(attachments = listOf(
                ChatAttachment.Photo(PhotoContent("p1", "android.resource://app.orbitle.android.debug/${app.maxly.R.drawable.wallpaper_autumn}", 1080, 1920)),
                ChatAttachment.Photo(PhotoContent("p2", "android.resource://app.orbitle.android.debug/${app.maxly.R.drawable.wallpaper_autumn_dark}", 1080, 1920)),
            ))),
            msg("6", "1", now - 30 * minute, "Отлично, спасибо! Посмотрю вечером и отпишусь", content = MessageContent(reply = MessageReply("4", "Борис", "Это голосовое про выходные. А вот отчёт:", MessageReply.Kind.TEXT), reactions = listOf(MessageReaction("👍", 2, true), MessageReaction("🔥", 1, false))), read = true),
            msg("7", "2", now - 20 * minute, "", name = "Анна", content = MessageContent(attachments = listOf(ChatAttachment.Call(CallContent("c", 0, false, "MISSED"))))),
            msg("8", "2", now - 10 * minute, "Пересылаю важное", name = "Анна", content = MessageContent(forward = MessageForward("Канал новостей", "Пересылаю важное"), edited = true)),
            msg("9", "1", now - 2 * minute, "Уже в пути, буду через 10 минут"),
            msg("95", "2", now - minute, "", name = "Анна", content = MessageContent(attachments = listOf(ChatAttachment.Video(VideoContent(
                "r1", null, "android.resource://app.orbitle.android.debug/${app.maxly.R.drawable.demo_round_poster}", 320, 320, 4_000, isRound = true,
            ))))),
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
    override suspend fun reactionCatalog() = listOf("👍", "❤️", "🔥", "🤣", "😭", "😍", "👏", "😮", "🎉", "🙏", "💯", "😢", "🤔", "😎", "🥰", "👎", "😡", "🤯", "🥳", "💔", "🤝")
    override suspend fun reactionUsers(chatId: String, messageId: String) = listOf(
        app.maxly.domain.ReactionUser("2", "Анна", null, "👍"),
        app.maxly.domain.ReactionUser("3", "Борис", null, "👍"),
        app.maxly.domain.ReactionUser("4", "", null, "🔥"),
    )
    override suspend fun sendMedia(chatId: String, items: List<app.maxly.domain.OutgoingFile>, caption: String, replyTo: String?, progress: (Float) -> Unit) {
        for (step in 1..10) {
            kotlinx.coroutines.delay(200)
            progress(step / 10f)
        }
        val attachments = items.mapIndexed { i, item ->
            when (item.kind) {
                app.maxly.domain.OutgoingFile.Kind.PHOTO -> ChatAttachment.Photo(PhotoContent("s$i", "file://${item.path}", item.width, item.height))
                else -> ChatAttachment.File(FileContent("s$i", item.name, item.size))
            }
        }
        list.update { it + msg("${it.size + 100}", "1", System.currentTimeMillis(), caption, content = MessageContent(attachments = attachments)) }
    }
    override suspend fun mediaLink(chatId: String, messageId: String, attachment: ChatAttachment) =
        if (attachment is ChatAttachment.Video) "asset:///demo-round.mp4" else "demo://${attachment.id}"
    override suspend fun sendSticker(chatId: String, sticker: app.maxly.domain.Sticker, replyTo: String?) {
        val content = MessageContent(attachments = listOf(ChatAttachment.Sticker(app.maxly.domain.StickerContent(sticker.id, sticker.id, sticker.url))))
        list.update { it + msg("${it.size + 100}", "1", System.currentTimeMillis(), "", content = content) }
    }
    override suspend fun transcribe(chatId: String, messageId: String, voiceId: String): String? {
        kotlinx.coroutines.delay(800)
        return "Привет! Давайте в субботу поедем на дачу, я возьму мангал."
    }
}

private class DemoProfiles(private val group: Boolean) : app.maxly.data.ProfileRepository {
    private val card = if (group) {
        app.maxly.domain.ChatProfile(app.maxly.domain.ChatProfile.Kind.GROUP, "10", "Дача 🌲", description = "Планы на выходные и фото с участка", link = "https://max.ru/join/dacha", participants = 12)
    } else {
        app.maxly.domain.ChatProfile(app.maxly.domain.ChatProfile.Kind.USER, "10", "Анна Смирнова", phone = "79001234567", isOnline = true, description = "Дизайнер, люблю осень", link = "https://max.ru/anna")
    }
    override fun cached(chatId: String) = card
    override suspend fun profile(chatId: String) = card
    override suspend fun sharedPage(chatId: String, tab: app.maxly.domain.SharedMediaTab, beforeMessageId: String) = emptyList<Message>()
}

private class DemoStickers : app.maxly.data.StickerRepository {
    private val res = listOf(
        app.maxly.R.drawable.wallpaper_autumn_thumb, app.maxly.R.drawable.wallpaper_autumn_dark_thumb,
        app.maxly.R.drawable.wallpaper_autumn_night_thumb, app.maxly.R.drawable.maxly_mark,
    )
    override suspend fun catalog() = app.maxly.domain.StickerCatalog(
        listOf("1"),
        listOf(app.maxly.domain.StickerSet("s1", "Осень", null, (1..8).map { "$it" })),
    )
    override suspend fun stickers(ids: List<String>) = ids.map {
        app.maxly.domain.Sticker(it, "android.resource://app.orbitle.android.debug/${res[it.toInt() % res.size]}")
    }
}

/** Файлы демо: «скачивание» пишет текст в кэш. */
private class DemoFiles(private val context: android.content.Context) : MessageFiles {
    private fun file(fileId: String, name: String) = java.io.File(java.io.File(context.cacheDir, "files/$fileId"), name)
    override fun cached(fileId: String, name: String) = file(fileId, name).takeIf { it.exists() }?.absolutePath
    override suspend fun download(url: String, fileId: String, name: String, progress: (Float) -> Unit): String {
        for (step in 1..10) {
            kotlinx.coroutines.delay(150)
            progress(step / 10f)
        }
        val target = file(fileId, name)
        target.parentFile?.mkdirs()
        if (url.startsWith("android.resource:")) {
            context.contentResolver.openInputStream(android.net.Uri.parse(url))!!.use { input -> target.outputStream().use { input.copyTo(it) } }
        } else {
            target.writeText("Демо-отчёт Orbitle")
        }
        return target.absolutePath
    }
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
    override suspend fun delete(ids: List<String>) {
        calls.value = calls.value?.filterNot { it.id in ids }
    }
    override suspend fun createLink() = "https://max.ru/call/demo"
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
