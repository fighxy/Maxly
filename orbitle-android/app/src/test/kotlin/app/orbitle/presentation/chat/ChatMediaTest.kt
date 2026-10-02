package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.FileContent
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.PhotoContent
import app.orbitle.domain.VideoContent
import app.orbitle.domain.VoiceContent
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private class FakePlayer : VoicePlayer {
    override val playback = MutableStateFlow<VoicePlayback?>(null)
    val calls = mutableListOf<String>()

    override fun play(messageId: String, voiceId: String, url: String, durationMs: Long, from: Float?) {
        calls += "play $messageId ${from ?: "-"}"
        playback.value = VoicePlayback(messageId, voiceId, isPlaying = true, positionMs = 0, durationMs = durationMs)
    }
    override fun pause() {
        calls += "pause"
        playback.value = playback.value?.copy(isPlaying = false)
    }
    override fun seek(fraction: Float) {
        calls += "seek $fraction"
    }
    override fun stop() {
        calls += "stop"
        playback.value = null
    }
}

private class FakeFiles : MessageFiles {
    val stored = mutableMapOf<String, String>()
    var gate: CompletableDeferred<Unit>? = null
    val urls = mutableListOf<String>()
    override fun cached(fileId: String, name: String) = stored[fileId]
    override suspend fun download(url: String, fileId: String, name: String, progress: (Float) -> Unit): String {
        urls += url
        progress(0.5f)
        gate?.await()
        return "/cache/$fileId/$name".also { stored[fileId] = it }
    }
}

class ChatMediaTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeMessages()
    private val player = FakePlayer()
    private val files = FakeFiles()
    private val errors = mutableListOf<Exception>()
    private val scope = TestScope(UnconfinedTestDispatcher())
    private val media = ChatMedia("10", repo, scope, player, files) { errors += it }

    private val voice = VoiceContent("77", "https://cdn/v.ogg", durationMs = 4_000)
    private fun msg(id: String = "5", content: MessageContent = MessageContent(attachments = listOf(ChatAttachment.Voice(voice))), status: MessageStatus = MessageStatus.SENT) =
        Message(id = id, chatId = "10", authorId = "2", text = "", timeMs = 1, status = status, content = content, authorName = "Анна")

    @Test
    fun voiceTogglePlaysPausesAndResumes() {
        val m = msg()
        media.toggleVoice(m, voice)
        media.toggleVoice(m, voice)
        media.toggleVoice(m, voice)
        assertEquals(listOf("play 5 -", "pause", "play 5 -"), player.calls)
    }

    @Test
    fun seekStartsAnotherVoiceFromThePoint() {
        media.toggleVoice(msg("5"), voice)
        media.seekVoice(msg("6"), voice, 0.25f)
        media.seekVoice(msg("6"), voice, 0.5f)
        assertEquals(listOf("play 5 -", "play 6 0.25", "seek 0.5"), player.calls)
    }

    @Test
    fun voiceWithoutUrlIsNotPlayable() {
        val silent = voice.copy(url = null)
        assertFalse(media.canPlay(silent))
        media.toggleVoice(msg(), silent)
        assertTrue(player.calls.isEmpty())
        assertEquals(1, errors.size)
    }

    @Test
    fun transcriptLoadsOnceAndToggles() {
        val m = msg()
        media.toggleTranscript(m, voice)
        assertEquals(TranscriptUi.Text("Привет"), media.state.value.transcripts["5"])
        media.toggleTranscript(m, voice)
        assertNull(media.state.value.transcripts["5"])
        media.toggleTranscript(m, voice)
        assertEquals(1, repo.transcribeCalls.size)
        assertEquals("5" to "77", repo.transcribeCalls.single())
    }

    @Test
    fun knownTranscriptNeedsNoRequest() {
        val ready = voice.copy(transcript = "Готово")
        media.toggleTranscript(msg(), ready)
        assertEquals(TranscriptUi.Text("Готово"), media.state.value.transcripts["5"])
        assertTrue(repo.transcribeCalls.isEmpty())
    }

    @Test
    fun pendingTranscriptArrivesByPush() {
        repo.transcript = null
        media.toggleTranscript(msg(), voice)
        assertEquals(TranscriptUi.Loading, media.state.value.transcripts["5"])
        repo.pushes.tryEmit("5" to "Позже")
        assertEquals(TranscriptUi.Text("Позже"), media.state.value.transcripts["5"])
    }

    @Test
    fun failedTranscriptCollapses() {
        repo.transcribeFailure = OrbitleError.Rejected("нет")
        media.toggleTranscript(msg(), voice)
        assertNull(media.state.value.transcripts["5"])
        assertEquals(1, errors.size)
    }

    @Test
    fun localMessageCannotBeTranscribed() {
        assertFalse(media.canTranscribe(msg("local-1", status = MessageStatus.SENDING), voice))
        assertTrue(media.canTranscribe(msg(), voice))
    }

    @Test
    fun viewerOpensAtTappedItemAndAsksVideoLink() {
        val photo = ChatAttachment.Photo(PhotoContent("p1", "https://img/1"))
        val video = ChatAttachment.Video(VideoContent("v1", null))
        val m = msg(content = MessageContent(attachments = listOf(photo, video)))
        media.openVisual(m, video)
        val viewer = media.state.value.viewer!!
        assertEquals(1, viewer.index)
        assertEquals(2, viewer.items.size)
        assertEquals("https://cdn.example/v.mp4", viewer.videoUrls["v1"])
        media.showPage(0)
        media.showPage(1)
        assertEquals(listOf("v1"), repo.linkCalls)
        media.closeViewer()
        assertNull(media.state.value.viewer)
    }

    @Test
    fun fileDownloadsThenOpensFromCache() {
        val file = FileContent("f1", "отчёт.pdf", 2048)
        val m = msg(content = MessageContent(attachments = listOf(ChatAttachment.File(file))))
        files.gate = CompletableDeferred()
        media.openFile(m, file)
        assertEquals(0.5f, media.state.value.downloads["f1"])
        files.gate!!.complete(Unit)
        assertEquals(OpenFile("/cache/f1/отчёт.pdf", "отчёт.pdf"), media.state.value.openFile)
        assertTrue(media.state.value.downloads.isEmpty())
        media.consumeOpenFile()
        media.openFile(m, file)
        assertEquals(1, files.urls.size)
        assertEquals("/cache/f1/отчёт.pdf", media.state.value.openFile?.path)
    }

    @Test
    fun secondTapCancelsDownload() {
        val file = FileContent("f2", "a.zip", 10)
        val m = msg(content = MessageContent(attachments = listOf(ChatAttachment.File(file))))
        files.gate = CompletableDeferred()
        media.openFile(m, file)
        media.openFile(m, file)
        assertTrue(media.state.value.downloads.isEmpty())
        assertNull(media.state.value.openFile)
    }
}
