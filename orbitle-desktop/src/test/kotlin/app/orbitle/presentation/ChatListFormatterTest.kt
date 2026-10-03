package app.orbitle.presentation

import app.orbitle.domain.Chat
import app.orbitle.domain.ChatDraft
import app.orbitle.domain.ChatLastMessage
import app.orbitle.domain.ChatType
import app.orbitle.domain.DeliveryState
import app.orbitle.domain.MessageMediaKind
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.chatlist.ChatBadge
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.presentation.chatlist.ChatListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

class ChatListFormatterTest {
    private val formatter = ChatListFormatter(ZoneOffset.UTC)

    /** Вторник, 29 сентября 2026, 12:00 UTC. */
    private val now = 1_790_683_200_000L

    private fun ms(text: String) = Instant.parse(text).toEpochMilli()

    private fun chat(
        id: String = "42",
        type: ChatType = ChatType.PRIVATE,
        preview: String? = "Привет",
        last: ChatLastMessage? = null,
        lastId: String? = "1",
        unread: Int = 0,
    ) = Chat(id = id, title = "Анна Петрова", type = type, lastMessageId = lastId, unreadCount = unread, updatedAtMs = now - 60_000, preview = preview, lastMessage = last)

    @Test
    fun savedMessagesWelcomeKeyLooksEmpty() {
        val welcome = chat(
            id = Chat.SAVED_MESSAGES_ID,
            preview = "  ${app.orbitle.domain.SavedMessagesWelcome.KEY} ",
            last = ChatLastMessage(authorId = "1", authorName = "Я", isOutgoing = true),
        )
        val item = formatter.item(welcome, now)
        assertEquals(ChatListFormatter.SAVED_MESSAGES_EMPTY, item.preview)
        assertEquals(ChatListItem.PreviewStyle.EMPTY, item.previewStyle)
        assertNull(item.sender)
        assertNull(item.delivery)
        // В другом чате такой текст — обычное сообщение.
        val other = formatter.item(chat(preview = app.orbitle.domain.SavedMessagesWelcome.KEY), now)
        assertEquals(app.orbitle.domain.SavedMessagesWelcome.KEY, other.preview)
        assertEquals(ChatListItem.PreviewStyle.MESSAGE, other.previewStyle)
        // Черновик в «Избранном» важнее приветствия.
        val drafted = formatter.item(welcome.copy(draft = ChatDraft("заметка", now)), now)
        assertEquals(ChatListItem.PreviewStyle.DRAFT, drafted.previewStyle)
    }

    @Test
    fun timeLabels() {
        assertEquals("09:05", formatter.timeLabel(ms("2026-09-29T09:05:00Z"), now))
        assertEquals("00:00", formatter.timeLabel(ms("2026-09-29T00:00:00Z"), now))
        assertEquals("вчера", formatter.timeLabel(ms("2026-09-28T23:59:00Z"), now))
        assertEquals("вс", formatter.timeLabel(ms("2026-09-27T10:00:00Z"), now))
        assertEquals("ср", formatter.timeLabel(ms("2026-09-23T10:00:00Z"), now))
        assertEquals("22 сен", formatter.timeLabel(ms("2026-09-22T10:00:00Z"), now))
        assertEquals("5 янв", formatter.timeLabel(ms("2026-01-05T10:00:00Z"), now))
        assertEquals("31.12.2025", formatter.timeLabel(ms("2025-12-31T10:00:00Z"), now))
        assertEquals("01.10.2026", formatter.timeLabel(ms("2026-10-01T10:00:00Z"), now))
        assertEquals("", formatter.timeLabel(0, now))
    }

    @Test
    fun timeZoneDecidesToday() {
        val novosibirsk = ChatListFormatter(ZoneId.of("Asia/Novosibirsk"))
        assertEquals("03:00", novosibirsk.timeLabel(ms("2026-09-28T20:00:00Z"), now))
        assertEquals("вчера", formatter.timeLabel(ms("2026-09-28T20:00:00Z"), now))
    }

    @Test
    fun compactCounts() {
        assertEquals("0", ChatListFormatter.compactCount(0))
        assertEquals("999", ChatListFormatter.compactCount(999))
        assertEquals("1K", ChatListFormatter.compactCount(1_000))
        assertEquals("1K", ChatListFormatter.compactCount(1_050))
        assertEquals("68.3K", ChatListFormatter.compactCount(68_349))
        assertEquals("999K", ChatListFormatter.compactCount(999_999))
        assertEquals("2.5M", ChatListFormatter.compactCount(2_500_000))
    }

    @Test
    fun mediaWithoutTextGetsLabel() {
        val photo = formatter.item(chat(preview = null, last = ChatLastMessage(media = MessageMediaKind.PHOTO)), now)
        assertEquals("Фотография", photo.preview)
        val voice = formatter.item(chat(preview = "", last = ChatLastMessage(media = MessageMediaKind.VOICE)), now)
        assertEquals("Голосовое сообщение", voice.preview)
        assertEquals(MessageMediaKind.VOICE, voice.media)
        val unknown = formatter.item(chat(preview = null, last = null), now)
        assertEquals("Вложение", unknown.preview)
        val empty = formatter.item(chat(preview = null, lastId = null), now)
        assertEquals("Нет сообщений", empty.preview)
        assertEquals(ChatListItem.PreviewStyle.EMPTY, empty.previewStyle)
    }

    @Test
    fun senderOnlyInGroups() {
        val incoming = ChatLastMessage(authorId = "7", authorName = "Борис")
        assertEquals("Борис", formatter.item(chat(type = ChatType.GROUP, last = incoming), now).sender)
        assertEquals("Вы", formatter.item(chat(type = ChatType.GROUP, last = ChatLastMessage(isOutgoing = true)), now).sender)
        assertNull(formatter.item(chat(type = ChatType.PRIVATE, last = incoming), now).sender)
        assertNull(formatter.item(chat(type = ChatType.CHANNEL, last = incoming), now).sender)
    }

    @Test
    fun deliveryTicksOnlyForOwnMessages() {
        val own = ChatLastMessage(isOutgoing = true, delivery = DeliveryState.READ)
        assertEquals(DeliveryState.READ, formatter.item(chat(last = own), now).delivery)
        assertEquals(DeliveryState.SENT, formatter.item(chat(last = ChatLastMessage(isOutgoing = true)), now).delivery)
        assertNull(formatter.item(chat(last = ChatLastMessage(authorId = "1")), now).delivery)
        assertNull(formatter.item(chat(type = ChatType.CHANNEL, last = own), now).delivery)
        assertNull(formatter.item(chat(id = Chat.SAVED_MESSAGES_ID, last = own), now).delivery)
    }

    @Test
    fun savedMessages() {
        val item = formatter.item(chat(id = Chat.SAVED_MESSAGES_ID, preview = null, lastId = null), now)
        assertEquals("Избранное", item.title)
        assertEquals("Сохраните что-нибудь", item.preview)
        assertEquals(ChatAvatar.Kind.SavedMessages, item.avatar.kind)
    }

    @Test
    fun draftAndTyping() {
        val withDraft = chat().copy(draft = ChatDraft("  Черновик\nтекста ", now))
        val draft = formatter.item(withDraft, now)
        assertEquals(ChatListItem.PreviewStyle.DRAFT, draft.previewStyle)
        assertEquals("Черновик текста", draft.preview)
        val typing = formatter.item(chat(type = ChatType.GROUP), now, typing = listOf("1", "2", "3"))
        assertEquals("3 участника печатают…", typing.preview)
        assertEquals("21 участник печатает…", ChatListFormatter.typingText(21, ChatType.GROUP))
        assertEquals("11 участников печатают…", ChatListFormatter.typingText(11, ChatType.GROUP))
        assertEquals("печатает…", ChatListFormatter.typingText(1, ChatType.PRIVATE))
    }

    @Test
    fun badgesAndPin() {
        assertEquals(ChatBadge.Count("5"), formatter.item(chat(unread = 5), now).badge)
        assertEquals(ChatBadge.Dot, formatter.item(chat().copy(isMarkedUnread = true), now).badge)
        val pinned = formatter.item(chat().copy(pinOrder = 0), now)
        assertTrue(pinned.showsPin)
    }

    @Test
    fun avatarInitialsAndColors() {
        assertEquals("АП", ChatAvatar.initials("Анна Петрова"))
        assertEquals("ИК", ChatAvatar.initials("Иван-Кузнецов"))
        assertEquals("1", ChatAvatar.initials("123"))
        assertEquals(6, ChatAvatar.colorIndex("13"))
        assertEquals(6, ChatAvatar.colorIndex("-13"))
        assertTrue(ChatAvatar.colorIndex("abc") in 0 until ChatAvatar.PALETTE_SIZE)
    }

    @Test
    fun unreadPhrases() {
        assertEquals("1 непрочитанное сообщение", ChatListFormatter.unreadPhrase(1))
        assertEquals("3 непрочитанных сообщения", ChatListFormatter.unreadPhrase(3))
        assertEquals("12 непрочитанных сообщений", ChatListFormatter.unreadPhrase(12))
    }
}
