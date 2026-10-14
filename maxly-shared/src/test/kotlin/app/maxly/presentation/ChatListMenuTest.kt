package app.maxly.presentation

import app.maxly.MainDispatcherRule
import app.maxly.data.AccountRepository
import app.maxly.data.FolderRepository
import app.maxly.domain.Chat
import app.maxly.domain.ChatType
import app.maxly.domain.ConnectionState
import app.maxly.domain.ServerFolder
import app.maxly.presentation.chatlist.ChatListFormatter
import app.maxly.presentation.chatlist.ChatListMenu
import app.maxly.presentation.chatlist.ChatListMenu.Entry
import app.maxly.presentation.chatlist.ChatListMenu.MuteFor
import app.maxly.presentation.chatlist.ChatListViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.lang.reflect.Proxy
import java.time.ZoneOffset

class ChatListMenuTest {
    @get:Rule val main = MainDispatcherRule()

    private val now = 1_790_683_200_000L
    private val formatter = ChatListFormatter(ZoneOffset.UTC)

    private fun chat(id: String, type: ChatType = ChatType.PRIVATE, peer: String? = "7$id", unread: Int = 0, pin: Int? = null, muted: Boolean = false, bot: Boolean = false) =
        Chat(id = id, title = "Чат $id", type = type, lastMessageId = "1", unreadCount = unread, updatedAtMs = now, preview = "текст", pinOrder = pin, isMuted = muted, peerId = peer, isBot = bot)

    private fun item(chat: Chat) = formatter.item(chat, now)

    private val work = ServerFolder("f1", "Работа", chatIds = listOf("2"))
    private val all = ServerFolder("all", "Все", isAllChats = true)

    @Test
    fun privateChatHasMaxOrder() {
        val entries = ChatListMenu.entries(item(chat("1")), ChatListMenu.folderChoices("1", listOf(all, work)), hasStories = true)
        assertEquals(
            listOf("Добавить в папку", "Закрепить", "Отметить непрочитанным", "Отключить уведомления", "Стереть переписку", "Скрыть истории автора", "Заблокировать", "Удалить чат"),
            entries.map { it.title },
        )
        assertEquals(listOf(false, false, false, false, false, false, true, true), entries.map { it.isDanger })
    }

    @Test
    fun botHasReportStopAndDeleteAndStop() {
        val folders = ChatListMenu.folderChoices("1", listOf(all, work))
        val entries = ChatListMenu.entries(item(chat("1", bot = true)), folders, hasStories = true)
        assertEquals(
            listOf("Добавить в папку", "Закрепить", "Отметить непрочитанным", "Отключить уведомления", "Стереть переписку", "Скрыть истории автора", "Пожаловаться", "Остановить", "Удалить и остановить"),
            entries.map { it.title },
        )
        assertEquals(listOf(true, true, true), entries.takeLast(3).map { it.isDanger })
        val stopped = ChatListMenu.entries(item(chat("1", bot = true)), null, botStopped = true)
        assertEquals(listOf("Пожаловаться", "Перезапустить", "Удалить чат"), stopped.takeLast(3).map { it.title })
        assertFalse((stopped[stopped.size - 2] as Entry.StopBot).isDanger)
        assertFalse(stopped.any { it is Entry.Block })
    }

    @Test
    fun groupHasNoBlockAndNoFoldersWithoutThem() {
        val entries = ChatListMenu.entries(item(chat("1", type = ChatType.GROUP, peer = null, unread = 2, pin = 0, muted = true)), null)
        assertEquals(listOf("Открепить", "Отметить прочитанным", "Включить уведомления", "Стереть переписку", "Удалить чат"), entries.map { it.title })
        assertTrue((entries[2] as Entry.Mute).choices.isEmpty())
    }

    @Test
    fun savedMessagesAreNotBlockedOrHidden() {
        val entries = ChatListMenu.entries(item(chat(Chat.SAVED_MESSAGES_ID)), null, hasStories = true, savedMessages = true)
        assertFalse(entries.any { it is Entry.Block || it is Entry.HideStories })
    }

    @Test
    fun reorderOnlyForPinnedWhenAllowed() {
        assertTrue(ChatListMenu.entries(item(chat("1", pin = 0)), null, canReorderPins = true).contains(Entry.ReorderPins))
        assertFalse(ChatListMenu.entries(item(chat("1")), null, canReorderPins = true).contains(Entry.ReorderPins))
    }

    @Test
    fun foldersEntryWithoutFoldersStillCreates() {
        val entries = ChatListMenu.entries(item(chat("1")), emptyList())
        assertEquals(Entry.Folders(emptyList()), entries.first())
    }

    @Test
    fun muteDurations() {
        assertEquals(listOf("На 1 час", "На 4 часа", "На 1 день", "Навсегда"), MuteFor.entries.map { it.title })
        assertEquals(now + 3_600_000L, MuteFor.HOUR.until(now))
        assertEquals(now + 14_400_000L, MuteFor.FOUR_HOURS.until(now))
        assertEquals(now + 86_400_000L, MuteFor.DAY.until(now))
        assertEquals(-1L, MuteFor.FOREVER.until(now))
        assertEquals(listOf(MuteFor.FOREVER), MuteFor.entries.filter { it.isDanger })
    }

    @Test
    fun folderChoicesSkipAllAndToggle() {
        assertEquals(listOf(ChatListMenu.FolderChoice("f1", "Работа", contains = false)), ChatListMenu.folderChoices("1", listOf(all, work)))
        assertEquals(listOf(ChatListMenu.FolderChoice("f1", "Работа", contains = true)), ChatListMenu.folderChoices("2", listOf(all, work)))
        assertEquals(listOf("2", "1"), ChatListMenu.toggled(work, "1"))
        assertEquals(emptyList<String>(), ChatListMenu.toggled(work, "2"))
    }

    private class Folders : FolderRepository {
        override val folders = MutableStateFlow<List<ServerFolder>?>(null)
        val calls = mutableListOf<String>()
        override suspend fun reload() = Unit
        override suspend fun create(title: String, chatIds: List<String>, filters: List<String>) {
            calls += "create $title $chatIds"
        }
        override suspend fun rename(folderId: String, title: String) = Unit
        override suspend fun setChats(folderId: String, chatIds: List<String>) {
            calls += "$folderId $chatIds"
        }
        override suspend fun delete(folderId: String) = Unit
        override suspend fun reorder(order: List<String>) = Unit
    }

    /** Чёрный список: «Заблокировать» и боты, остальное меню не трогает. */
    private class Blocker(base: AccountRepository) : AccountRepository by base {
        val blocked = mutableListOf<String>()
        val unblocked = mutableListOf<String>()
        var list = listOf<app.maxly.domain.BlockedUser>()
        override suspend fun block(userId: String) {
            blocked += userId
        }
        override suspend fun unblock(userId: String) {
            unblocked += userId
        }
        override suspend fun blockedUsers() = list
    }

    private fun unused(): AccountRepository =
        Proxy.newProxyInstance(javaClass.classLoader, arrayOf(AccountRepository::class.java)) { _, method, _ -> error("не нужно: ${method.name}") } as AccountRepository

    private val repo = object : FakeChats() {
        val untils = mutableListOf<Pair<String, Long>>()
        val calls = mutableListOf<String>()
        override suspend fun setMuteUntil(chatId: String, untilMs: Long) {
            untils += chatId to untilMs
        }
        override suspend fun startBot(chatId: String) {
            calls += "start $chatId"
        }
        override suspend fun deleteChat(chatId: String, forEveryone: Boolean) {
            calls += "delete $chatId $forEveryone"
        }
        override suspend fun complaintReasons() = mapOf(6 to listOf(app.maxly.data.ComplaintChoice(3, "Спам")), 2 to listOf(app.maxly.data.ComplaintChoice(9, "Канал")))
        override suspend fun complain(reasonId: Int, typeId: Int, ids: List<String>, parentId: String?): Boolean {
            calls += "complain $reasonId $typeId $ids"
            return true
        }
    }
    private val folders = Folders()
    private val account = Blocker(unused())
    private val vm by lazy {
        ChatListViewModel(repo, MutableStateFlow(ConnectionState.ONLINE), formatter, now = { now }, local = FakeMarks(), folderEditor = folders, account = account)
    }

    private fun shown(id: String) = vm.state.value.items.first { it.id == id }

    @Test
    fun muteForSendsUntilAndMarksMuted() {
        repo.chats.value = listOf(chat("1"))
        vm.muteFor("1", MuteFor.FOUR_HOURS)
        assertEquals(listOf("1" to now + 14_400_000L), repo.untils)
        assertTrue(shown("1").isMuted)
        vm.muteFor("1", MuteFor.FOREVER)
        assertEquals("1" to -1L, repo.untils.last())
    }

    @Test
    fun toggleFolderAddsAndRemoves() {
        repo.chats.value = listOf(chat("1"), chat("2"))
        repo.folders.value = listOf(all, work)
        assertEquals(listOf(ChatListMenu.FolderChoice("f1", "Работа", false)), vm.folderChoices("1"))
        vm.toggleFolder("1", "f1")
        assertEquals("Чат добавлен в «Работа»", vm.messages.value)
        vm.toggleFolder("2", "f1")
        assertEquals(listOf("f1 [2, 1]", "f1 []"), folders.calls)
        assertEquals("Чат убран из «Работа»", vm.messages.value)
        vm.toggleFolder("1", "all")
        assertEquals(2, folders.calls.size)
        vm.createFolder("1", "  Новые ")
        assertEquals("create Новые [1]", folders.calls.last())
        assertEquals("Папка «Новые» создана", vm.messages.value)
    }

    @Test
    fun blockUsesPeer() {
        repo.chats.value = listOf(chat("1", peer = "42"), chat("2", type = ChatType.GROUP, peer = null))
        assertTrue(vm.canBlock)
        vm.block("1")
        vm.block("2")
        assertEquals(listOf("42"), account.blocked)
        assertEquals("Пользователь заблокирован", vm.messages.value)
    }

    @Test
    fun botStopRestartDeleteAndReport() {
        repo.chats.value = listOf(chat("1", peer = "42", bot = true), chat("2", peer = "43"))
        account.list = listOf(app.maxly.domain.BlockedUser("50", "Другой", null, null))
        vm.prepareMenu("2")
        assertEquals(emptySet<String>(), vm.stoppedBots.value)
        vm.prepareMenu("1")
        assertEquals(setOf("50"), vm.stoppedBots.value)
        assertFalse(vm.isBotStopped("1"))
        vm.stopBot("1")
        assertEquals(listOf("42"), account.blocked)
        assertTrue(vm.isBotStopped("1"))
        assertEquals("Бот остановлен", vm.messages.value)
        vm.restartBot("1")
        assertEquals(listOf("42"), account.unblocked)
        assertFalse(vm.isBotStopped("1"))
        assertEquals("Бот запущен", vm.messages.value)
        vm.deleteAndStopBot("1")
        assertEquals(listOf("42", "42"), account.blocked)
        assertEquals(listOf(app.maxly.data.ComplaintChoice(3, "Спам")), kotlinx.coroutines.runBlocking { vm.botReportReasons() })
        vm.reportBot("1", 3)
        assertEquals(listOf("start 1", "delete 1 false", "complain 3 6 [42]"), repo.calls)
        assertEquals("Жалоба отправлена", vm.messages.value)
    }
}
