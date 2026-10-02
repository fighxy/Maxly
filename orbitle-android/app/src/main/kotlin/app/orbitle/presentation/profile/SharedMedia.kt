package app.orbitle.presentation.profile

import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.FileContent
import app.orbitle.domain.Message
import app.orbitle.domain.SharedMediaTab
import app.orbitle.domain.TextSpan
import app.orbitle.domain.VoiceContent
import app.orbitle.presentation.chat.CallBubbleText
import app.orbitle.presentation.chat.ChatContentFormat
import app.orbitle.presentation.common.PresenceText
import java.net.URI
import java.time.Instant
import java.time.ZoneId

/** Вложения чата по вкладкам, новые первыми. */
data class SharedMedia(
    val media: List<Visual> = emptyList(),
    val files: List<File> = emptyList(),
    val links: List<Link> = emptyList(),
    val voices: List<Voice> = emptyList(),
) {
    data class Visual(val message: Message, val attachment: ChatAttachment, val thumbnailUrl: String?, val duration: String?) {
        val key: String get() = "${message.id}/${attachment.id}"
    }

    data class File(val message: Message, val file: FileContent, val ext: String, val details: String) {
        val key: String get() = "${message.id}/${file.id}"
    }

    data class Link(val message: Message, val url: String, val host: String, val letter: String, val context: String?) {
        val key: String get() = "${message.id}/$url"
    }

    data class Voice(val message: Message, val voice: VoiceContent, val author: String, val details: String) {
        val key: String get() = "${message.id}/${voice.id}"
    }

    val tabs: List<SharedMediaTab> get() = SharedMediaTab.entries.filter { count(it) > 0 }

    fun count(tab: SharedMediaTab): Int = when (tab) {
        SharedMediaTab.MEDIA -> media.size
        SharedMediaTab.FILES -> files.size
        SharedMediaTab.LINKS -> links.size
        SharedMediaTab.VOICE -> voices.size
    }

    companion object {
        private val URL = Regex("""https?://[^\s<>"«»]+""")

        /** Собрать вкладки из сообщений (в любом порядке, повторы по id отбрасываются). */
        fun collect(messages: List<Message>, currentUserId: String?, zone: ZoneId = ZoneId.systemDefault()): SharedMedia {
            val ordered = messages.distinctBy { it.id }.filter { !it.isService }.sortedByDescending { it.timeMs }
            val media = mutableListOf<Visual>()
            val files = mutableListOf<File>()
            val links = mutableListOf<Link>()
            val voices = mutableListOf<Voice>()
            for (message in ordered) {
                for (attachment in message.content.attachments) {
                    when (attachment) {
                        is ChatAttachment.Photo -> media += Visual(message, attachment, attachment.photo.url, null)
                        is ChatAttachment.Video -> media += Visual(
                            message, attachment, attachment.video.posterUrl,
                            CallBubbleText.clock(attachment.video.durationMs),
                        )
                        is ChatAttachment.File -> files += File(
                            message, attachment.file,
                            extension(attachment.file.name),
                            listOf(ChatContentFormat.fileSize(attachment.file.size), date(message.timeMs, zone)).filter { it.isNotEmpty() }.joinToString(" · "),
                        )
                        is ChatAttachment.Voice -> voices += Voice(
                            message, attachment.voice,
                            if (!currentUserId.isNullOrEmpty() && message.authorId == currentUserId) "Вы" else message.authorName.ifEmpty { "Участник" },
                            "${date(message.timeMs, zone)} · ${CallBubbleText.clock(attachment.voice.durationMs)}",
                        )
                        else -> Unit
                    }
                }
                links += linksOf(message)
            }
            return SharedMedia(media, files, links.distinctBy { it.key }, voices)
        }

        private fun linksOf(message: Message): List<Link> {
            val text = message.displayText
            val fromSpans = message.content.formatting.filter { it.kind == TextSpan.Kind.LINK }.mapNotNull { it.url }
            val fromText = URL.findAll(text).map { it.value.trimEnd('.', ',', ')', '!', '?', ';', ':') }.toList()
            return (fromSpans + fromText).distinct().mapNotNull { url ->
                val host = runCatching { URI(url).host }.getOrNull()?.removePrefix("www.") ?: return@mapNotNull null
                val context = text.trim().takeIf { it.isNotEmpty() && it.trimEnd('.', ',', ')', '!', '?', ';', ':') != url }
                Link(message, url, host, host.first().uppercase(), context)
            }
        }

        /** `отчёт.pdf` → `PDF`; без расширения — пусто. */
        fun extension(name: String): String {
            val ext = name.substringAfterLast('.', "")
            return if (ext.isEmpty() || ext.length > 5 || ext == name) "" else ext.uppercase()
        }

        private fun date(ms: Long, zone: ZoneId): String {
            if (ms <= 0) return ""
            val d = Instant.ofEpochMilli(ms).atZone(zone)
            val month = PresenceText.MONTHS_GENITIVE[d.monthValue - 1].take(3)
            return "${d.dayOfMonth} $month"
        }
    }
}
