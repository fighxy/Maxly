package app.maxly.presentation.chat

import app.maxly.data.MessageRepository
import app.maxly.domain.ChatAttachment
import app.maxly.domain.FileContent
import app.maxly.domain.Message
import app.maxly.domain.MessageStatus
import app.maxly.domain.MaxlyError
import app.maxly.domain.VoiceContent
import app.maxly.presentation.media.AvatarPhoto
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
    /** Подпись сообщения под фото или видео; пустая — без подписи. */
    val caption: String = "",
    /** Уже загруженные уменьшенные копии: id вложения → адрес. Видны, пока грузится оригинал. */
    val previews: Map<String, String> = emptyMap(),
    /** Адреса кадра в порядке попыток (фото профиля): id вложения → адреса. */
    val fallbacks: Map<String, List<String>> = emptyMap(),
)

/** Кружок, который играет прямо в ленте. [url] — `null`, пока адрес спрашивается у сервера. */
data class RoundPlayback(val messageId: String, val videoId: String, val url: String?)

/** Скачанный файл, который экран должен открыть системным приложением. */
data class OpenFile(val path: String, val name: String)

/** Скачанное фото или видео, которым делятся из просмотра: файл, имя для получателя и тип. */
data class ShareFile(val path: String, val name: String, val kind: SavedKind)

data class ChatMediaState(
    /** id сообщения → расшифровка, которая сейчас раскрыта. */
    val transcripts: Map<String, TranscriptUi> = emptyMap(),
    /** id файла → доля загрузки 0…1. */
    val downloads: Map<String, Float> = emptyMap(),
    val viewer: MediaViewerState? = null,
    val openFile: OpenFile? = null,
    /** Файл для окна «Поделиться» (Android) или буфера обмена (компьютер). */
    val shareFile: ShareFile? = null,
    /** Сообщения, вложения которых сейчас сохраняются. */
    val saving: Set<String> = emptySet(),
    val round: RoundPlayback? = null,
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
    /** Часы для имени сохранённого фото профиля. */
    private val now: () -> Long = System::currentTimeMillis,
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
        _state.value.round?.let { stopRound(it.videoId) }
        val player = player ?: return
        val url = voice.url
        if (url.isNullOrEmpty()) {
            onError(MaxlyError.Rejected("Голосовое ещё не загружено"))
            return
        }
        val current = player.playback.value
        if (current != null && current.matches(message.id, voice.id) && current.isPlaying) {
            player.pause()
        } else {
            player.play(message.id, voice.id, url, voice.durationMs, meta = meta(message))
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
            player.play(message.id, voice.id, url, voice.durationMs, from = fraction.coerceIn(0f, 1f), meta = meta(message))
        }
    }

    /** Для полосы «играет голосовое»: чат, автор и время сообщения. */
    private fun meta(message: Message) = VoiceMeta(chatId = message.chatId.ifEmpty { chatId }, author = message.authorName, sentAtMs = message.timeMs)

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

    // Кружки

    /** Касание кружка: играть в ленте, повторное — остановить. Голосовое при этом замолкает. */
    fun toggleRound(message: Message, video: app.maxly.domain.VideoContent) {
        if (_state.value.round?.videoId == video.id) {
            stopRound(video.id)
            return
        }
        player?.stop()
        val local = video.url?.takeIf { it.isNotEmpty() && message.id.toLongOrNull() == null }
        _state.update { it.copy(round = RoundPlayback(message.id, video.id, local)) }
        if (local != null) return
        scope.launch {
            try {
                val url = video.url?.takeIf { it.isNotEmpty() } ?: repository.mediaLink(chatId, message.id, ChatAttachment.Video(video))
                _state.update { state -> if (state.round?.videoId == video.id) state.copy(round = state.round.copy(url = url)) else state }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                stopRound(video.id)
                onError(e)
            }
        }
    }

    /** Кружок доиграл или его остановили. */
    fun stopRound(videoId: String) = _state.update { if (it.round?.videoId == videoId) it.copy(round = null) else it }

    fun openVisual(message: Message, attachment: ChatAttachment) {
        if (attachment is ChatAttachment.Video && attachment.video.isRound) {
            toggleRound(message, attachment.video)
            return
        }
        val items = message.content.visuals
        val index = items.indexOfFirst { it.id == attachment.id }.coerceAtLeast(0)
        if (items.isEmpty()) return
        _state.update { it.copy(viewer = MediaViewerState(message.id, items, index, message.authorName, message.timeMs, caption = message.text.trim())) }
        items.getOrNull(index)?.let(::prepare)
    }

    fun showPage(index: Int) {
        val viewer = _state.value.viewer ?: return
        if (index == viewer.index) return
        _state.update { it.copy(viewer = viewer.copy(index = index)) }
        viewer.items.getOrNull(index)?.let(::prepare)
        resolveAvatarAround(index)
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
                onError(e as? MaxlyError ?: MaxlyError.Rejected("Не удалось скачать файл"))
            } finally {
                loads.remove(key)
            }
        }
    }

    fun consumeOpenFile() = _state.update { it.copy(openFile = null) }

    // Сохранение

    fun canSave(message: Message, target: SaveTarget): Boolean =
        saver != null && files != null && message.id.toLongOrNull() != null && SaveNaming.attachments(message, target).isNotEmpty()

    /**
     * Скачать вложения сообщения и положить их в общую папку (галерея или «Загрузки», как решит
     * платформа) или в выбранную [directory] (компьютер: «Сохранить как…»).
     */
    fun save(message: Message, target: SaveTarget, directory: String? = null) {
        if (!canSave(message, target)) return
        saveItems(message.id, message.timeMs, SaveNaming.attachments(message, target), directory)
    }

    /** Сохранить фото или видео, открытое в просмотре. */
    fun saveViewed(directory: String? = null) {
        val viewer = _state.value.viewer ?: return
        val item = viewer.items.getOrNull(viewer.index) ?: return
        if (saver == null || files == null || viewer.messageId.toLongOrNull() == null) return
        saveItems(viewer.messageId, viewer.timeMs, listOf(item), directory, indexBase = viewer.index)
    }

    // Фото профиля

    private var avatarRefresh: (suspend () -> List<AvatarPhoto.Frame>)? = null
    private var avatarRefreshed = false
    private val avatarJobs = mutableMapOf<String, Job>()

    /**
     * Открыть фото профиля [ownerId] в просмотре: [frames], текущее первым. Без кадров ничего не
     * открывается. [refresh] перечитывает контакт или чат и отдаёт кадры заново: зовётся один раз
     * за просмотр, если адрес протух или ни один размер не загрузился.
     */
    fun openAvatar(ownerId: String, frames: List<AvatarPhoto.Frame>, title: String, refresh: (suspend () -> List<AvatarPhoto.Frame>)? = null) {
        val viewer = AvatarPhoto.viewer(ownerId, frames, title) ?: return
        avatarJobs.values.forEach { it.cancel() }
        avatarJobs.clear()
        avatarRefresh = refresh
        avatarRefreshed = false
        _state.update { it.copy(viewer = if (files != null) viewer.withoutRemoteUrls() else viewer) }
        resolveAvatarAround(0)
    }

    /** Дописать к открытому фото профиля [ownerId] прошлые фото [frames] (после текущего). */
    fun addAvatarFrames(ownerId: String, frames: List<AvatarPhoto.Frame>) {
        val key = AvatarPhoto.VIEWER_PREFIX + ownerId
        var added = false
        _state.update { state ->
            val viewer = state.viewer?.takeIf { it.messageId == key } ?: return@update state
            val known = viewer.items.map { it.id }.toSet()
            val fresh = frames.filter { it.id !in known }
            if (fresh.isEmpty()) return@update state
            added = true
            val extra = AvatarPhoto.viewer(ownerId, fresh, viewer.authorName)!!.let { if (files != null) it.withoutRemoteUrls() else it }
            state.copy(viewer = viewer.copy(
                items = viewer.items + extra.items,
                previews = viewer.previews + extra.previews,
                fallbacks = viewer.fallbacks + extra.fallbacks,
            ))
        }
        if (added) resolveAvatarAround(_state.value.viewer?.index ?: 0)
    }

    private fun MediaViewerState.withoutRemoteUrls(): MediaViewerState = copy(items = items.map { item ->
        val photo = (item as? ChatAttachment.Photo)?.photo ?: return@map item
        if (photo.url != null && isLocalUrl(photo.url)) item else ChatAttachment.Photo(photo.copy(url = null))
    })

    private fun isLocalUrl(url: String) = app.maxly.presentation.media.ImageRequests.isLocal(url)

    /** Кадр [index] и соседи: найти загружаемый адрес. */
    private fun resolveAvatarAround(index: Int) {
        val viewer = _state.value.viewer?.takeIf(AvatarPhoto::isAvatar) ?: return
        if (files == null) return
        for (i in listOf(index, index + 1, index - 1)) {
            val item = viewer.items.getOrNull(i) as? ChatAttachment.Photo ?: continue
            if (item.photo.url != null || avatarJobs[item.id]?.isActive == true) continue
            avatarJobs[item.id] = scope.launch { resolveAvatar(viewer.messageId, item.id) }
        }
    }

    private suspend fun resolveAvatar(key: String, id: String) {
        val files = files ?: return
        val owner = key.removePrefix(AvatarPhoto.VIEWER_PREFIX)
        var urls = _state.value.viewer?.takeIf { it.messageId == key }?.fallbacks?.get(id) ?: return
        if (AvatarPhoto.isExpired(urls, now())) urls = refreshAvatar(key, id) ?: urls
        val load: suspend (String) -> String = { url -> files.download(url, AvatarPhoto.cacheId(owner, url), "avatar") {} }
        var found = AvatarPhoto.firstLoaded(urls, load)
        if (found == null) found = refreshAvatar(key, id)?.let { AvatarPhoto.firstLoaded(it, load) }
        val local = found?.second?.let { java.io.File(it).toURI().toString() } ?: return
        _state.update { state ->
            val viewer = state.viewer?.takeIf { it.messageId == key } ?: return@update state
            state.copy(viewer = viewer.copy(items = viewer.items.map { item ->
                if (item.id == id && item is ChatAttachment.Photo) ChatAttachment.Photo(item.photo.copy(url = local)) else item
            }))
        }
    }

    /** Перечитать контакт или чат один раз за просмотр; адреса кадра [id] после этого. */
    private suspend fun refreshAvatar(key: String, id: String): List<String>? {
        val refresh = avatarRefresh ?: return null
        if (avatarRefreshed) return _state.value.viewer?.takeIf { it.messageId == key }?.fallbacks?.get(id)
        avatarRefreshed = true
        val frames = try {
            refresh()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return null
        }
        val fresh = frames.associate { it.id to it.urls }
        _state.update { state ->
            val viewer = state.viewer?.takeIf { it.messageId == key } ?: return@update state
            state.copy(viewer = viewer.copy(fallbacks = viewer.fallbacks + fresh.filterKeys { it in viewer.fallbacks }))
        }
        return fresh[id]
    }

    /** Открытое фото профиля можно сохранить: в общую папку или в выбранный файл. */
    fun canSaveAvatar(toFile: Boolean = false): Boolean =
        AvatarPhoto.isAvatar(_state.value.viewer) && files != null && (toFile || saver != null)

    /**
     * Сохранить показанное фото профиля в полном качестве: в [file] («Сохранить как…» на
     * компьютере) или в папку фото платформы ([MediaSaver.savePicture]).
     */
    fun saveAvatar(file: String? = null) = saveAvatar(_state.value.viewer, file)

    /** Сохранить фото профиля [photo] ([AvatarPhoto.viewer]) без открытого просмотра: меню шапки. */
    fun saveAvatar(photo: MediaViewerState?, file: String?) {
        val viewer = photo?.takeIf(AvatarPhoto::isAvatar) ?: return
        val content = (viewer.items.getOrNull(viewer.index) as? ChatAttachment.Photo)?.photo ?: return
        val files = files ?: return
        val saver = saver
        if (file == null && saver == null) return
        val key = viewer.messageId
        if (key in _state.value.saving) return
        _state.update { it.copy(saving = it.saving + key) }
        scope.launch {
            try {
                val owner = key.removePrefix(AvatarPhoto.VIEWER_PREFIX)
                val shown = content.url?.takeIf(::isLocalUrl)
                val path = if (shown != null) {
                    java.io.File(java.net.URI(shown)).path
                } else {
                    val urls = viewer.fallbacks[content.id] ?: listOfNotNull(content.url)
                    AvatarPhoto.firstLoaded(urls) { url -> files.download(url, AvatarPhoto.cacheId(owner, url), "avatar") {} }?.second
                        ?: throw MaxlyError.Rejected(AvatarPhoto.FAILED)
                }
                val ext = SaveNaming.imageExtension(header(path))
                if (file != null) {
                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                        java.io.File(path).copyTo(java.io.File(AvatarPhoto.chosenFile(file, ext)), overwrite = true)
                    }
                } else {
                    saver!!.savePicture(path, AvatarPhoto.fileName(viewer.authorName, now(), ext))
                }
                onNotice(AvatarPhoto.SAVED)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onError(e as? MaxlyError ?: MaxlyError.Rejected("Не удалось сохранить фото"))
            } finally {
                _state.update { it.copy(saving = it.saving - key) }
            }
        }
    }

    /** Поделиться фото или видео, открытым в просмотре: файл скачивается и уходит экрану. */
    fun shareViewed() {
        val viewer = _state.value.viewer ?: return
        val item = viewer.items.getOrNull(viewer.index) ?: return
        val files = files ?: return
        if (viewer.messageId.toLongOrNull() == null || viewer.messageId in _state.value.saving) return
        _state.update { it.copy(saving = it.saving + viewer.messageId) }
        scope.launch {
            try {
                val (path, name, kind) = local(viewer.messageId, viewer.timeMs, item, viewer.index, files) ?: return@launch
                _state.update { it.copy(shareFile = ShareFile(path, name, kind)) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onError(e as? MaxlyError ?: MaxlyError.Rejected("Не удалось поделиться"))
            } finally {
                _state.update { it.copy(saving = it.saving - viewer.messageId) }
            }
        }
    }

    fun consumeShareFile() = _state.update { it.copy(shareFile = null) }

    /** Вложение на устройстве (скачанное в кэш), его имя для сохранения и тип. */
    private suspend fun local(messageId: String, timeMs: Long, attachment: ChatAttachment, index: Int, files: MessageFiles): Triple<String, String, SavedKind>? {
        val (url, cacheName) = when (attachment) {
            is ChatAttachment.Photo -> (attachment.photo.url ?: throw MaxlyError.Rejected("Фото недоступно")) to "photo-${attachment.id}"
            is ChatAttachment.Video -> repository.mediaLink(chatId, messageId, attachment) to "video-${attachment.id}.mp4"
            is ChatAttachment.File -> (attachment.file.url?.takeIf { it.isNotEmpty() } ?: repository.mediaLink(chatId, messageId, attachment)) to attachment.file.name
            is ChatAttachment.Voice -> (attachment.voice.url ?: throw MaxlyError.Rejected("Голосовое недоступно")) to "voice-${attachment.id}.m4a"
            else -> return null
        }
        val path = files.download(url, attachment.id, cacheName) {}
        val (name, kind) = when (attachment) {
            is ChatAttachment.Photo -> SaveNaming.name(timeMs, index, SaveNaming.imageExtension(header(path))) to SavedKind.IMAGE
            is ChatAttachment.Video -> SaveNaming.name(timeMs, index, "mp4") to SavedKind.VIDEO
            is ChatAttachment.Voice -> SaveNaming.name(timeMs, index, "m4a") to SavedKind.OTHER
            is ChatAttachment.File -> attachment.file.name.ifBlank { SaveNaming.name(timeMs, index, "bin") } to SavedKind.OTHER
            else -> return null
        }
        return Triple(path, name, kind)
    }

    private fun saveItems(messageId: String, timeMs: Long, items: List<ChatAttachment>, directory: String?, indexBase: Int = 0) {
        val saver = saver ?: return
        val files = files ?: return
        if (messageId in _state.value.saving || items.isEmpty()) return
        _state.update { it.copy(saving = it.saving + messageId) }
        scope.launch {
            try {
                val places = mutableSetOf<String>()
                items.forEachIndexed { position, attachment ->
                    val (path, name, kind) = local(messageId, timeMs, attachment, indexBase + position, files) ?: return@forEachIndexed
                    saver.save(path, name, kind, directory)
                    places += saver.place(kind)
                }
                onNotice(
                    when {
                        directory != null -> "Сохранено в папку «${java.io.File(directory).name.ifEmpty { directory }}»"
                        else -> places.singleOrNull()?.let { "Сохранено в $it" } ?: "Сохранено"
                    },
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onError(e as? MaxlyError ?: MaxlyError.Rejected("Не удалось сохранить"))
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
