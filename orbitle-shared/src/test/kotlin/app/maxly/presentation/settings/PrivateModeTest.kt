package app.maxly.presentation.settings

import app.maxly.data.PreferenceStore
import app.maxly.data.PrivateModeSettings
import app.maxly.domain.Chat
import app.maxly.domain.ChatDraft
import app.maxly.domain.ChatLastMessage
import app.maxly.domain.ChatType
import app.maxly.domain.DeliveryState
import app.maxly.domain.MessageMediaKind
import app.maxly.domain.PrivateModeDisplay
import app.maxly.domain.PrivateModePreferences
import app.maxly.domain.PrivateModeStyle
import app.maxly.presentation.chatlist.ChatAvatar
import app.maxly.presentation.chatlist.ChatListFormatter
import app.maxly.presentation.chatlist.ChatListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset

private class MapStore(val values: MutableMap<String, String> = mutableMapOf()) : PreferenceStore {
    override fun get(key: String) = values[key]
    override fun put(key: String, value: String) {
        values[key] = value
    }
}

class PrivateModeTest {
    private val formatter = ChatListFormatter(ZoneOffset.UTC)
    private val now = 1_790_000_000_000L

    private fun item(
        id: String = "5",
        type: ChatType = ChatType.GROUP,
        last: ChatLastMessage? = ChatLastMessage(authorId = "7", authorName = "Борис", thumbnailUrl = "https://x/1.jpg", media = MessageMediaKind.PHOTO),
        unread: Int = 3,
        draft: ChatDraft? = null,
    ): ChatListItem = formatter.item(
        Chat(id = id, title = "Семья Петровых", type = type, lastMessageId = "1", unreadCount = unread, updatedAtMs = now - 60_000, preview = "Смотри", lastMessage = last, draft = draft),
        now,
    )

    @Test
    fun `settings default to off with placeholders and the button`() {
        val settings = PrivateModeSettings(MapStore())
        assertEquals(PrivateModePreferences(), settings.state.value)
        assertEquals(PrivateModeDisplay.VISIBLE, PrivateModeSettings.display(settings.state.value))
    }

    @Test
    fun `settings are stored and unknown style reads as placeholders`() {
        val store = MapStore()
        val settings = PrivateModeSettings(store)
        settings.toggle()
        settings.setStyle(PrivateModeStyle.BLUR)
        settings.setQuickToggle(false)
        assertEquals("true", store.values[PrivateModeSettings.KEY_ENABLED])
        assertEquals("blur", store.values[PrivateModeSettings.KEY_STYLE])
        val again = PrivateModeSettings(store).state.value
        assertTrue(again.enabled)
        assertEquals(PrivateModeStyle.BLUR, again.style)
        assertFalse(again.quickToggle)
        assertEquals(PrivateModeDisplay.BLUR, PrivateModeSettings.display(again))
        assertEquals(PrivateModeDisplay.PLACEHOLDER, PrivateModeSettings.display(again, canBlur = false))
        store.values[PrivateModeSettings.KEY_STYLE] = "glass"
        assertEquals(PrivateModeStyle.PLACEHOLDER, PrivateModeSettings(store).state.value.style)
    }

    @Test
    fun `chat row hides the name, author, text and thumbnail`() {
        val masked = PrivateModeMask.item(item())
        assertEquals("Групповой чат", masked.title)
        assertEquals("Вы получили сообщение", masked.preview)
        assertNull(masked.sender)
        assertNull(masked.thumbnailUrl)
        assertNull(masked.media)
        assertEquals(ChatAvatar.Kind.Initials(""), masked.avatar.kind)
        assertEquals(3, masked.unreadCount)
        assertFalse(masked.accessibilityLabel.contains("Петров"))
        assertFalse(masked.accessibilityLabel.contains("Борис"))
    }

    @Test
    fun `own message, draft, call and saved messages`() {
        val own = PrivateModeMask.item(item(type = ChatType.PRIVATE, last = ChatLastMessage(isOutgoing = true, delivery = DeliveryState.READ)))
        assertEquals("Личный чат", own.title)
        assertEquals("Вы отправили сообщение", own.preview)
        assertEquals(DeliveryState.READ, own.delivery)

        val draft = PrivateModeMask.item(item(draft = ChatDraft("секрет", now)))
        assertEquals(ChatListItem.PreviewStyle.DRAFT, draft.previewStyle)
        assertEquals("скрыт", draft.preview)

        val call = PrivateModeMask.item(item(type = ChatType.PRIVATE, last = ChatLastMessage(media = MessageMediaKind.CALL)))
        assertEquals("Звонок", call.preview)

        val saved = PrivateModeMask.item(item(id = Chat.SAVED_MESSAGES_ID, type = ChatType.PRIVATE))
        assertEquals("Избранное", saved.title)
        assertEquals(ChatAvatar.Kind.SavedMessages, saved.avatar.kind)
        assertEquals("Канал", PrivateModeMask.chatTitle(ChatType.CHANNEL))
    }
}

class PrivateModeChatTest {
    private val reaction = app.maxly.domain.MessageContent()

    @Test
    fun `bubble keeps id, time and status but drops content and author`() {
        val message = app.maxly.domain.Message(
            id = "42", chatId = "5", authorId = "7", text = "Пароль от wifi", timeMs = 1_000L,
            status = app.maxly.domain.MessageStatus.SENT, authorName = "Борис", authorAvatarUrl = "https://x/a.jpg", isRead = true,
        )
        val avatar = ChatAvatar(ChatAvatar.Kind.Photo("https://x/a.jpg", "Б"), 3)
        val item = app.maxly.presentation.chat.ChatItem.Bubble(message, false, "12:00", "Борис", 2, true, avatar, false, true, comments = 4)
        val masked = PrivateModeMask.bubble(item)
        assertEquals("42", masked.message.id)
        assertEquals("7", masked.message.authorId)
        assertEquals(1_000L, masked.message.timeMs)
        assertTrue(masked.message.isRead)
        assertEquals("Вы получили сообщение", masked.message.text)
        assertEquals("", masked.message.authorName)
        assertNull(masked.message.authorAvatarUrl)
        assertEquals(reaction, masked.message.content)
        assertNull(masked.authorName)
        assertNull(masked.comments)
        assertEquals(ChatAvatar(ChatAvatar.Kind.Initials(""), 3), masked.avatar)
        assertEquals("12:00", masked.time)
        assertEquals("Вы отправили сообщение", PrivateModeMask.bubble(item.copy(outgoing = true)).message.text)
        assertEquals("Сообщение скрыто", PrivateModeMask.panelText(message, editing = false))
        assertEquals("Вы отправили сообщение", PrivateModeMask.panelText(message, editing = true))
    }

    @Test
    fun `header gets a generic title and keeps the status line`() {
        val header = app.maxly.presentation.chat.ChatHeaderUi(
            "Анна", "в сети", true, ChatAvatar(ChatAvatar.Kind.Initials("А"), 1), isVerified = true, type = ChatType.PRIVATE,
        )
        val masked = PrivateModeMask.header(header)
        assertEquals("Личный чат", masked.title)
        assertEquals("в сети", masked.subtitle)
        assertFalse(masked.isVerified)
        assertEquals(ChatAvatar.Kind.Initials(""), masked.avatar.kind)
        assertEquals("Групповой чат", PrivateModeMask.header(header.copy(type = ChatType.GROUP)).title)
        assertEquals("Избранное", PrivateModeMask.header(header.copy(isSavedMessages = true)).title)
    }
}
