package app.maxly.data

import app.maxly.domain.ChatAttachment
import app.maxly.domain.MessageReply
import app.maxly.domain.TextSpan
import com.maxly.core.api.MaxMessage
import com.maxly.core.api.MaxUser
import com.maxly.core.state.MaxState
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
        assertEquals(listOf(TextSpan.Kind.STRONG, TextSpan.Kind.LINK, TextSpan.Kind.UNKNOWN), spans.map { it.kind })
        assertEquals("https://x", spans[1].url)
        assertEquals("UNKNOWN", spans[2].foreign?.type)
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

    @Test
    fun pollNeedsTwoAnswersAndAPollId() {
        val parsed = MessageMapping.poll(
            mapOf(
                "pollId" to 4L,
                "title" to "  ",
                "answers" to listOf(
                    mapOf("answerId" to 1, "text" to "Да"),
                    mapOf("answerId" to 2, "text" to "Нет"),
                ),
                "state" to mapOf(
                    "total" to 3,
                    "result" to listOf(
                        mapOf("answerId" to 1, "voteCount" to 2),
                        mapOf("answerId" to 2, "voteCount" to 1),
                    ),
                ),
            ),
        )!!
        assertEquals("4", parsed.id)
        assertEquals("Опрос", parsed.title)
        assertEquals(2, parsed.answers[0].votes)
        assertEquals(3, parsed.total)
        assertNull(MessageMapping.poll(mapOf("pollId" to 1L, "answers" to listOf(mapOf("answerId" to 1, "text" to "Один")))))
        val shown = MessageMapping.message(
            message(mapOf("attaches" to listOf(mapOf(
                "_type" to "POLL",
                "pollId" to 4L,
                "title" to "Куда",
                "answers" to listOf(mapOf("answerId" to 1, "text" to "Да"), mapOf("answerId" to 2, "text" to "Нет")),
            )))),
            10,
            state,
        )
        assertEquals("Опрос", shown.replySnippet)
        assertEquals("Куда", shown.content.poll!!.title)
    }

    @Test
    fun pinControlReadsThePinnedText() {
        val pin = MessageMapping.pinNotice(
            listOf(mapOf("_type" to "CONTROL", "event" to "pin", "pinnedMessage" to mapOf("id" to 9L, "text" to "важное"))),
        )
        assertEquals("9", pin!!.messageId)
        assertEquals("важное", pin.preview)
        val blank = MessageMapping.pinNotice(
            listOf(mapOf("_type" to "CONTROL", "event" to "pin", "pinnedMessage" to mapOf("id" to 9L, "text" to " "))),
        )
        assertEquals("Сообщение", blank!!.preview)
        val unpin = MessageMapping.pinNotice(listOf(mapOf("_type" to "CONTROL", "event" to "unpin")))
        assertNull(unpin!!.messageId)
        assertNull(MessageMapping.pinNotice(listOf(mapOf("_type" to "CONTROL", "event" to "new"))))
    }

    @Test
    fun commentsAreNotChannelPosts() {
        assertFalse(MessageMapping.isComment(message(emptyMap(), text = "пост")))
        val push = MaxMessage.from(mapOf("chatId" to 10L, "postId" to "55", "message" to mapOf("id" to 78L, "time" to 2_000L, "type" to "USER", "text" to "к")))!!
        assertTrue(MessageMapping.isComment(push))
        val inner = MaxMessage.from(mapOf("chatId" to 10L, "message" to mapOf("id" to 79L, "time" to 2_000L, "type" to "USER", "postId" to 55L)))!!
        assertTrue(MessageMapping.isComment(inner))
        val reply = message(mapOf("link" to mapOf("type" to "REPLY", "messageId" to 78L, "postId" to 55L)))
        assertTrue(MessageMapping.isComment(reply))
        assertFalse(MessageMapping.isComment(message(mapOf("link" to mapOf("type" to "REPLY", "messageId" to 70L)))))
    }

    @Test
    fun sharePreviewFromAttaches() {
        val share = mapOf(
            "_type" to "SHARE", "shareId" to 5L, "url" to "https://www.example.org/a", "title" to " Статья ",
            "description" to "Коротко", "image" to mapOf("_type" to "PHOTO", "baseUrl" to "https://img/1", "width" to 640, "height" to 320),
        )
        val preview = MessageMapping.message(message(mapOf("attaches" to listOf(share)), text = "https://www.example.org/a"), 10, state).content.linkPreview!!
        assertEquals("https://www.example.org/a", preview.url)
        assertEquals("Статья", preview.title)
        assertEquals("Коротко", preview.summary)
        assertEquals("https://img/1", preview.imageUrl)
        assertEquals(640, preview.imageWidth)
        assertEquals("example.org", preview.site)
        assertNull(MessageMapping.linkPreview(listOf(mapOf("_type" to "SHARE", "title" to "без адреса"))))
    }

    @Test
    fun inlineKeyboardFromAttaches() {
        val keyboard = mapOf(
            "_type" to "INLINE_KEYBOARD", "callbackId" to "cb-1",
            "keyboard" to mapOf("buttons" to listOf(
                listOf(mapOf("type" to "callback", "text" to "Да", "payload" to "yes"), mapOf("type" to "LINK", "text" to "Сайт", "url" to "https://a.b")),
                listOf(mapOf("type" to "CALLBACK", "text" to " ")),
                listOf(mapOf("type" to "OPEN_APP", "text" to "Игра", "contactId" to 99L)),
            )),
        )
        val result = MessageMapping.message(message(mapOf("attaches" to listOf(keyboard))), 10, state).content.keyboard!!
        assertEquals("cb-1", result.callbackId)
        assertEquals(2, result.rows.size)
        assertEquals("CALLBACK", result.rows[0][0].type)
        assertEquals("yes", result.rows[0][0].payload)
        assertEquals("https://a.b", result.rows[0][1].url)
        assertEquals("99", result.rows[1][0].contactId)
        assertNull(MessageMapping.keyboard(listOf(mapOf("_type" to "INLINE_KEYBOARD", "keyboard" to mapOf("buttons" to emptyList<Any>())))))
    }
}
