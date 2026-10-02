package app.orbitle.presentation.settings

import app.orbitle.data.PreferenceStore
import app.orbitle.data.PrivateModeSettings
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatDraft
import app.orbitle.domain.ChatLastMessage
import app.orbitle.domain.ChatType
import app.orbitle.domain.DeliveryState
import app.orbitle.domain.MessageMediaKind
import app.orbitle.domain.PrivateModeDisplay
import app.orbitle.domain.PrivateModePreferences
import app.orbitle.domain.PrivateModeStyle
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.presentation.chatlist.ChatListItem
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
