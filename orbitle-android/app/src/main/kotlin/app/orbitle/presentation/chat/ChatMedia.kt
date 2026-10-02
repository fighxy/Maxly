package app.orbitle.presentation.chat

import app.orbitle.data.MessageRepository
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.FileContent
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.VoiceContent
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Расшифровка голосового под пузырём. */
sealed interface TranscriptUi {
    data object Loading : TranscriptUi
    data class Text(val text: String) : TranscriptUi
}

/** Просмотр фото и видео сообщения на весь экран. */
data class MediaViewerState(
    val messageId: String,
    val items: List<ChatAttachment>,
    val index: Int,
    val authorName: String,
    val timeMs: Long,
    /** Прямые адреса видео: id вложения → адрес. */
    val videoUrls: Map<String, String> = emptyMap(),
)

/** Скачанный файл, который экран должен открыть системным приложением. */
data class OpenFile(val path: String, val name: String)

data class ChatMediaState(
    /** id сообщения → расшифровка, которая сейчас раскрыта. */
    val transcripts: Map<String, TranscriptUi> = emptyMap(),
    /** id файла → доля загрузки 0…1. */
    val downloads: Map<String, Float> = emptyMap(),
    val viewer: MediaViewerState? = null,
    val openFile: OpenFile? = null,
    /** Сообщения, вложения которых сейчас сохраняются. */
    val saving: Set<String> = emptySet(),
)

/** Скачанные файлы сообщений. */
interface MessageFiles {
    fun cached(fileId: String, name: String): String?
    suspend fun download(url: String, fileId: String, name: String, progress: (Float) -> Unit): String
}

/** Медиа экрана чата: голосовые, расшифровка, просмотр фото и видео, файлы. */
class ChatMedia(
    private val chatId: String,
    private val repository: MessageRepository,
    private val scope: CoroutineScope,
    private val player: VoicePlayer?,
    private val files: MessageFiles?,
    /** Галерея и «Загрузки»; `null` — сохранять некуда. */
    private val saver: MediaSaver? = null,
    private val onNotice: (String) -> Unit = {},
    private val onError: (Exception) -> Unit,
) {
    private val _state = MutableStateFlow(ChatMediaState())
    val state: StateFlow<ChatMediaState> = _state.asStateFlow()

    val playback: StateFlow<VoicePlayback?> = player?.playback ?: MutableStateFlow(null)

    /** Готовые расшифровки этого экрана, в том числе присланные пушем. */
    private val ready = mutableMapOf<String, String>()
    private val loads = mutableMapOf<String, Job>()

    init {
        scope.launch {
            repository.transcriptions().collect { (messageId, text) ->
                ready[messageId] = text
                if (_state.value.transcripts[messageId] == TranscriptUi.Loading) {
                    _state.update { it.copy(transcripts = it.transcripts + (messageId to TranscriptUi.Text(text))) }
                }
            }
        }
    }

    // Голосовые

    fun canPlay(voice: VoiceContent) = player != null && !voice.url.isNullOrEmpty()

    /** Пуск или пауза; другое голосовое останавливает текущее. */
    fun toggleVoice(message: Message, voice: VoiceContent) {
        val player = player ?: return
        val url = voice.url
        if (url.isNullOrEmpty()) {
            onError(OrbitleError.Rejected("Голосовое ещё не загружено"))
            return
        }
        val current = player.playback.value
        if (current != null && current.matches(message.id, voice.id) && current.isPlaying) {
            player.pause()
        } else {
            player.play(message.id, voice.id, url, voice.durationMs)
        }
    }

    /** Перемотка по дорожке. Не играющее голосовое начинает играть с этого места. */
    fun seekVoice(message: Message, voice: VoiceContent, fraction: Float) {
        val player = player ?: return
        val current = player.playback.value
        if (current != null && current.matches(message.id, voice.id)) {
            player.seek(fraction)
        } else {
            val url = voice.url ?: return
            player.play(message.id, voice.id, url, voice.durationMs, from = fraction.coerceIn(0f, 1f))
        }
    }

    fun stopVoice() = player?.stop()

    /** Расшифровку можно запросить у голосового на сервере. */
    fun canTranscribe(message: Message, voice: VoiceContent): Boolean =
        !voice.transcript.isNullOrBlank() || (message.status == MessageStatus.SENT && message.id.toLongOrNull() != null && voice.id.toLongOrNull() != null)

    /** Показать или скрыть расшифровку. Нет готовой — спросить сервер. */
    fun toggleTranscript(message: Message, voice: VoiceContent) {
        val key = message.id
        when (_state.value.transcripts[key]) {
            is TranscriptUi.Text -> {
                _state.update { it.copy(transcripts = it.transcripts - key) }
                return
            }
            TranscriptUi.Loading -> return
            null -> Unit
        }
        val known = voice.transcript?.takeIf { it.isNotBlank() } ?: ready[key]
        if (known != null) {
            _state.update { it.copy(transcripts = it.transcripts + (key to TranscriptUi.Text(known))) }
            return
        }
        if (!canTranscribe(message, voice)) return
        _state.update { it.copy(transcripts = it.transcripts + (key to TranscriptUi.Loading)) }
        loads[key]?.cancel()
        loads[key] = scope.launch {
            try {
                val text = repository.transcribe(chatId, message.id, voice.id) ?: ready[key]
                if (text != null) {
                    ready[key] = text
                    _state.update { it.copy(transcripts = it.transcripts + (key to TranscriptUi.Text(text.ifBlank { EMPTY_TRANSCRIPT }))) }
                }
                // null: сервер ещё расшифровывает, текст придёт пушем.
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(transcripts = it.transcripts - key) }
                onError(e)
            }
        }
    }

    // Фото и видео

    fun openVisual(message: Message, attachment: ChatAttachment) {
        val items = message.content.visuals
        val index = items.indexOfFirst { it.id == attachment.id }.coerceAtLeast(0)
        if (items.isEmpty()) return
        _state.update { it.copy(viewer = MediaViewerState(message.id, items, index, message.authorName, message.timeMs)) }
        items.getOrNull(index)?.let(::prepare)
    }

    fun showPage(index: Int) {
        val viewer = _state.value.viewer ?: return
        if (index == viewer.index) return
        _state.update { it.copy(viewer = viewer.copy(index = index)) }
        viewer.items.getOrNull(index)?.let(::prepare)
    }

    fun closeViewer() = _state.update { it.copy(viewer = null) }

    /** Видео: заранее спросить прямой адрес. */
    private fun prepare(attachment: ChatAttachment) {
        val viewer = _state.value.viewer ?: return
        if (attachment !is ChatAttachment.Video || attachment.id in viewer.videoUrls) return
        val messageId = viewer.messageId
        scope.launch {
            try {
                val direct = attachment.video.url?.takeIf { it.isNotEmpty() && messageId.toLongOrNull() == null }
                    ?: repository.mediaLink(chatId, messageId, attachment)
                _state.update { state ->
                    val open = state.viewer?.takeIf { it.messageId == messageId } ?: return@update state
                    state.copy(viewer = open.copy(videoUrls = open.videoUrls + (attachment.id to direct)))
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onError(e)
            }
        }
    }

    // Файлы

    /** Открыть файл: скачанный — сразу, иначе скачать с прогрессом. Повторное нажатие отменяет загрузку. */
    fun openFile(message: Message, file: FileContent) {
        val files = files ?: return
        files.cached(file.id, file.name)?.let { path ->
            _state.update { it.copy(openFile = OpenFile(path, file.name)) }
            return
        }
        val key = "file-${file.id}"
        if (loads[key]?.isActive == true) {
            loads.remove(key)?.cancel()
            _state.update { it.copy(downloads = it.downloads - file.id) }
            return
        }
        _state.update { it.copy(downloads = it.downloads + (file.id to 0f)) }
        loads[key] = scope.launch {
            try {
                val url = file.url?.takeIf { it.isNotEmpty() } ?: repository.mediaLink(chatId, message.id, ChatAttachment.File(file))
                val path = files.download(url, file.id, file.name) { fraction ->
                    _state.update { it.copy(downloads = it.downloads + (file.id to fraction)) }
                }
                _state.update { it.copy(downloads = it.downloads - file.id, openFile = OpenFile(path, file.name)) }
            } catch (e: CancellationException) {
                _state.update { it.copy(downloads = it.downloads - file.id) }
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(downloads = it.downloads - file.id) }
                onError(e as? OrbitleError ?: OrbitleError.Rejected("Не удалось скачать файл"))
            } finally {
                loads.remove(key)
            }
        }
    }

    fun consumeOpenFile() = _state.update { it.copy(openFile = null) }

    // Сохранение

    fun canSave(message: Message, target: SaveTarget): Boolean =
        saver != null && files != null && message.id.toLongOrNull() != null && SaveNaming.attachments(message, target).isNotEmpty()

    /** Скачать вложения сообщения и положить их в галерею или «Загрузки». */
    fun save(message: Message, target: SaveTarget) {
        if (!canSave(message, target)) return
        saveItems(message.id, message.timeMs, SaveNaming.attachments(message, target), target)
    }

    /** Сохранить в галерею фото или видео, открытое в просмотре. */
    fun saveViewed() {
        val viewer = _state.value.viewer ?: return
        val item = viewer.items.getOrNull(viewer.index) ?: return
        if (saver == null || files == null || viewer.messageId.toLongOrNull() == null) return
        saveItems(viewer.messageId, viewer.timeMs, listOf(item), SaveTarget.GALLERY, indexBase = viewer.index)
    }

    private fun saveItems(messageId: String, timeMs: Long, items: List<ChatAttachment>, target: SaveTarget, indexBase: Int = 0) {
        val saver = saver ?: return
        val files = files ?: return
        if (messageId in _state.value.saving || items.isEmpty()) return
        _state.update { it.copy(saving = it.saving + messageId) }
        scope.launch {
            try {
                items.forEachIndexed { position, attachment ->
                    val index = indexBase + position
                    val (url, cacheName) = when (attachment) {
                        is ChatAttachment.Photo -> (attachment.photo.url ?: throw OrbitleError.Rejected("Фото недоступно")) to "photo-${attachment.id}"
                        is ChatAttachment.Video -> repository.mediaLink(chatId, messageId, attachment) to "video-${attachment.id}.mp4"
                        is ChatAttachment.File -> (attachment.file.url?.takeIf { it.isNotEmpty() } ?: repository.mediaLink(chatId, messageId, attachment)) to attachment.file.name
                        is ChatAttachment.Voice -> (attachment.voice.url ?: throw OrbitleError.Rejected("Голосовое недоступно")) to "voice-${attachment.id}.m4a"
                        else -> return@forEachIndexed
                    }
                    val path = files.download(url, attachment.id, cacheName) {}
                    val (name, kind) = when (attachment) {
                        is ChatAttachment.Photo -> SaveNaming.name(timeMs, index, SaveNaming.imageExtension(header(path))) to SavedKind.IMAGE
                        is ChatAttachment.Video -> SaveNaming.name(timeMs, index, "mp4") to SavedKind.VIDEO
                        is ChatAttachment.Voice -> SaveNaming.name(timeMs, index, "m4a") to SavedKind.OTHER
                        is ChatAttachment.File -> attachment.file.name.ifBlank { SaveNaming.name(timeMs, index, "bin") } to SavedKind.OTHER
                        else -> return@forEachIndexed
                    }
                    saver.save(path, name, kind)
                }
                onNotice(if (target == SaveTarget.GALLERY) "Сохранено в галерею" else "Сохранено в «Загрузки»")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onError(e as? OrbitleError ?: OrbitleError.Rejected("Не удалось сохранить"))
            } finally {
                _state.update { it.copy(saving = it.saving - messageId) }
            }
        }
    }

    private fun header(path: String): ByteArray = runCatching {
        java.io.File(path).inputStream().use { input -> ByteArray(16).let { buf -> buf.copyOf(maxOf(0, input.read(buf))) } }
    }.getOrDefault(ByteArray(0))

    companion object {
        const val EMPTY_TRANSCRIPT = "Речь не распознана"
    }
}
