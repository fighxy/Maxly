package app.orbitle.data

import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.MessageReply
import app.orbitle.domain.TextSpan
import com.max.core.api.MaxMessage
import com.max.core.api.MaxUser
import com.max.core.state.MaxState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageMappingTest {
    private val me = 1L
    private val anna = MaxUser.from(mapOf("id" to 2L, "names" to listOf(mapOf("name" to "Анна"))))!!
    private val state = MaxState(me = me, users = mapOf(2L to anna))

    private fun message(extra: Map<String, Any?>, sender: Long = 2L, text: String = "") =
        MaxMessage.from(mapOf("id" to 77L, "sender" to sender, "text" to text, "time" to 1_000L, "type" to "USER") + extra, 10L)!!

    @Test
    fun plainTextWithAuthor() {
        val result = MessageMapping.message(message(emptyMap(), text = "Привет"), 10, state)
        assertEquals("77", result.id)
        assertEquals("10", result.chatId)
        assertEquals("2", result.authorId)
        assertEquals("Анна", result.authorName)
        assertEquals("Привет", result.text)
        assertFalse(result.isService)
    }

    @Test
    fun ownMessageReadByPeerMark() {
        val own = message(emptyMap(), sender = me, text = "Ок")
        assertTrue(MessageMapping.message(own, 10, state, peerRead = 1_000).isRead)
        assertFalse(MessageMapping.message(own, 10, state, peerRead = 999).isRead)
        assertFalse(MessageMapping.message(message(emptyMap(), text = "x"), 10, state, peerRead = 5_000).isRead)
    }

    @Test
    fun photoVideoVoiceFile() {
        val attaches = listOf(
            mapOf("_type" to "PHOTO", "photoId" to 5L, "baseUrl" to "https://p/5", "width" to 800, "height" to 600),
            mapOf("_type" to "VIDEO", "videoId" to 6L, "thumbnail" to "https://v/6", "duration" to 12_000, "videoType" to 1),
            mapOf("_type" to "AUDIO", "audioId" to 7L, "url" to "https://a/7", "wave" to listOf(1, 2, 3), "duration" to 3_500, "transcription" to "текст"),
            mapOf("_type" to "FILE", "fileId" to 8L, "name" to "отчёт.pdf", "size" to 2048L),
        )
        val content = MessageMapping.message(message(mapOf("attaches" to attaches)), 10, state).content
        val photo = (content.attachments[0] as ChatAttachment.Photo).photo
        assertEquals("5", photo.id)
        assertEquals("https://p/5", photo.url)
        assertEquals(800, photo.width)
        val video = (content.attachments[1] as ChatAttachment.Video).video
        assertTrue(video.isRound)
        assertEquals(12_000L, video.durationMs)
        assertEquals("https://v/6", video.posterUrl)
        val voice = content.voices.single()
        assertEquals(listOf(1, 2, 3), voice.waveform)
        assertEquals("текст", voice.transcript)
        assertEquals(3_500L, voice.durationMs)
        assertEquals("отчёт.pdf", content.files.single().name)
        assertEquals(2048L, content.files.single().size)
    }

    @Test
    fun waveFromBytesAndBase64() {
        assertEquals(listOf(255, 1), MessageMapping.wave(byteArrayOf(-1, 1)))
        assertEquals((1..8).toList(), MessageMapping.wave(java.util.Base64.getEncoder().encodeToString(ByteArray(8) { (it + 1).toByte() })))
        assertEquals(emptyList<Int>(), MessageMapping.wave(null))
    }

    @Test
    fun contactNameFromParts() {
        val attach = mapOf("_type" to "CONTACT", "contactId" to 9L, "firstName" to "Иван", "lastName" to "Петров", "phone" to 79001234567L)
        val contact = (MessageMapping.attachment(attach) as ChatAttachment.Contact).contact
        assertEquals("Иван Петров", contact.name)
        assertEquals("79001234567", contact.phone)
        assertEquals("contact-9", contact.id)
    }

    @Test
    fun callAttachment() {
        val call = MessageMapping.call(mapOf("_type" to "CALL", "conversationId" to "abc", "duration" to 42_000, "callType" to "VIDEO", "hangupType" to "HUNGUP"))
        assertEquals("call-abc", call.id)
        assertTrue(call.isVideo)
        assertTrue(call.isConnected)
        assertFalse(call.isGroup)
    }

    @Test
    fun replyLinkWithPreview() {
        val link = mapOf("type" to "REPLY", "messageId" to 55L, "message" to mapOf("sender" to 2L, "text" to "", "attaches" to listOf(mapOf("_type" to "PHOTO", "photoId" to 1L))))
        val reply = MessageMapping.message(message(mapOf("link" to link), text = "ответ"), 10, state).content.reply!!
        assertEquals("55", reply.messageId)
        assertEquals("Анна", reply.authorName)
        assertEquals("Фото", reply.preview)
        assertEquals(MessageReply.Kind.PHOTO, reply.kind)
    }

    @Test
    fun forwardTakesOriginalTextAndAttachments() {
        val link = mapOf(
            "type" to "FORWARD",
            "message" to mapOf("sender" to 2L, "text" to "оригинал", "attaches" to listOf(mapOf("_type" to "FILE", "fileId" to 3L, "name" to "a.txt"))),
        )
        val result = MessageMapping.message(message(mapOf("link" to link)), 10, state)
        assertEquals("Анна", result.content.forward?.authorName)
        assertEquals("оригинал", result.displayText)
        assertEquals("a.txt", result.content.files.single().name)
        assertNull(result.content.reply)
    }

    @Test
    fun forwardWithoutAuthorIsUnknown() {
        val link = mapOf("type" to "FORWARD", "message" to mapOf("text" to "x"))
        assertEquals("Неизвестно", MessageMapping.message(message(mapOf("link" to link)), 10, state).content.forward?.authorName)
    }

    @Test
    fun reactionsAndEditedStatus() {
        val info = mapOf("totalCount" to 3, "counters" to listOf(mapOf("reaction" to "👍", "count" to 2), mapOf("reaction" to "🔥", "count" to 1), mapOf("reaction" to "😭", "count" to 0)), "yourReaction" to "🔥")
        val content = MessageMapping.message(message(mapOf("reactionInfo" to info, "status" to "EDITED"), text = "x"), 10, state).content
        assertEquals(listOf("👍", "🔥"), content.reactions.map { it.emoji })
        assertTrue(content.reactions[1].mine)
        assertFalse(content.reactions[0].mine)
        assertTrue(content.edited)
    }

    @Test
    fun formattingSpans() {
        val elements = listOf(
            mapOf("type" to "STRONG", "from" to 0, "length" to 3),
            mapOf("type" to "LINK", "from" to 4, "length" to 2, "attributes" to mapOf("url" to "https://x")),
            mapOf("type" to "UNKNOWN", "from" to 0, "length" to 1),
            mapOf("type" to "EMPHASIZED", "from" to 0, "length" to 0),
        )
        val spans = MessageMapping.spans(elements)
        assertEquals(listOf(TextSpan.Kind.STRONG, TextSpan.Kind.LINK), spans.map { it.kind })
        assertEquals("https://x", spans[1].url)
    }

    @Test
    fun controlMessageBecomesServiceText() {
        val control = mapOf("_type" to "CONTROL", "event" to "add", "userIds" to listOf(2L))
        val result = MessageMapping.message(message(mapOf("attaches" to listOf(control)), sender = 3L), 10, state)
        assertTrue(result.isService)
        assertEquals("Добавил(а) Анна", result.text)
        val created = MessageMapping.message(message(mapOf("attaches" to listOf(mapOf("_type" to "CONTROL", "event" to "new", "title" to "Дача")))), 10, state)
        assertEquals("Создан чат «Дача»", created.text)
    }

    @Test
    fun previewStrings() {
        assertEquals("Голосовое сообщение", MessageMapping.previewOf(listOf(MessageMapping.attachment(mapOf("_type" to "AUDIO"))!!)))
        assertEquals("Стикер", MessageMapping.previewOf(listOf(MessageMapping.attachment(mapOf("_type" to "STICKER", "stickerId" to 1L))!!)))
        assertEquals("Групповой звонок", MessageMapping.previewOf(listOf(MessageMapping.attachment(mapOf("_type" to "CALL", "joinLink" to "https://j"))!!)))
        assertEquals("", MessageMapping.previewOf(emptyList()))
    }
}
