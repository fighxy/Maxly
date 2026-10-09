package app.orbitle.presentation.calls

import app.orbitle.data.CoreErrors
import app.orbitle.data.calls.CallControl
import app.orbitle.data.calls.CallEngine
import app.orbitle.data.calls.CallLog
import app.orbitle.data.calls.CallService
import app.orbitle.domain.CallEndReason
import app.orbitle.domain.CallPhase
import app.orbitle.domain.CallRole
import app.orbitle.domain.CallState
import app.orbitle.domain.CallTopology
import app.orbitle.domain.IncomingCall
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

/** Звонок на экране. */
data class ActiveCall(
    val id: String,
    val conversationId: String,
    val direction: Direction,
    val peer: CallPeerInfo,
    val isVideo: Boolean,
    val joinLink: String? = null,
    val state: CallState,
    /** Входящий: на него уже ответили. */
    val answered: Boolean,
) {
    enum class Direction { OUTGOING, INCOMING, GROUP }

    /** Входящий, на который ещё не ответили: на экране «Ответить» и «Отклонить». */
    val isRinging: Boolean get() = direction == Direction.INCOMING && !answered && !state.isEnded
}

/** С кем звонок: пользователь Max или групповой звонок. */
data class CallPeerInfo(val id: String, val name: String, val avatarUrl: String? = null, val isGroup: Boolean = false)

data class CallCenterState(
    val call: ActiveCall? = null,
    /** Экран звонка развёрнут; свёрнутый — плашка над приложением. */
    val isExpanded: Boolean = true,
    val errorMessage: String? = null,
    /** Имена участников групповых звонков по id пользователя Max. */
    val names: Map<String, CallPeerInfo> = emptyMap(),
) {
    /** Исходящий звонит у собеседника: играют гудки. */
    val playsRingback: Boolean
        get() = call?.direction == ActiveCall.Direction.OUTGOING && call.state.phase == CallPhase.Ringing

    /** Имя для экрана: участник группового звонка или собеседник. */
    fun name(userId: String?): String? {
        userId ?: return null
        val call = call
        if (call?.peer?.id == userId && call.peer.name.isNotEmpty()) return call.peer.name
        return names[userId]?.name
    }
}

/**
 * Центр звонков: один звонок на всё приложение — исходящий, входящий или групповой. Порт iOS
 * `CallCenter` без CallKit: системный экран звонка (уведомление, служба) приложение строит по
 * [state] само.
 */
class CallCenter(
    private val service: CallService,
    private val engine: CallEngine,
    private val scope: CoroutineScope,
    private val lookup: suspend (String) -> CallPeerInfo? = { null },
    private val endedDisplayMs: Long = 1_500,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val _state = MutableStateFlow(CallCenterState())
    val state: StateFlow<CallCenterState> = _state.asStateFlow()

    /** Звонок закончился: приложение обновляет журнал звонков. */
    var onCallEnded: (() -> Unit)? = null

    private var control: CallControl? = null
    private var controlWatch: Job? = null
    private var watch: Job? = null
    private var dismissal: Job? = null
    private val lookedUp = HashSet<String>()

    /** Слушать входящие звонки. */
    fun activate() {
        if (watch != null) return
        watch = scope.launch {
            // Сбой в потоке входящих не должен ни ронять приложение, ни глушить следующие звонки.
            while (true) {
                try {
                    service.incomingCalls().collect { receive(it) }
                    break
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    CallLog.error("Входящие оборвались, слушаю заново", e)
                    delay(1_000)
                }
            }
        }
    }

    /** Выход из аккаунта: входящие больше не слушаются, идущий звонок кладётся. */
    suspend fun deactivate() {
        watch?.cancel()
        watch = null
        if (_state.value.call != null) hangUp()
    }

    // region Начать

    /** Позвонить пользователю Max. */
    suspend fun startCall(peer: CallPeerInfo, video: Boolean) {
        if (_state.value.call != null) {
            _state.update { it.copy(errorMessage = "Сначала закончите текущий звонок") }
            return
        }
        val id = UUID.randomUUID().toString()
        CallLog.info("Исходящий звонок пользователю ${peer.id}, видео: $video")
        _state.update {
            it.copy(
                call = ActiveCall(id, "", ActiveCall.Direction.OUTGOING, peer, video, state = CallState(), answered = true),
                isExpanded = true,
                errorMessage = null,
            )
        }
        try {
            val connection = service.startCall(peer.id, video)
            CallLog.info("Сервер начал звонок ${connection.conversationId}, ICE-серверов: ${connection.iceServers.size}")
            val control = engine.makeCall(connection, CallRole.CALLER, isGroup = false, expiresAtMs = null)
            val call = _state.value.call
            if (call?.id != id || call.state.isEnded) {
                // Трубку положили, пока сервер отвечал: звонок у собеседника надо отменить.
                control.start()
                control.hangUp()
                return
            }
            updateCall(id) { it.copy(conversationId = connection.conversationId) }
            attach(control, id)
            if (video) control.setCamera(true)
            control.start()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // Error тоже: без нативной библиотеки WebRTC движок бросает UnsatisfiedLinkError.
            if (!recoverable(e)) throw e
            fail(id, e)
        }
    }

    /** Войти в групповой звонок по ссылке. */
    suspend fun join(link: String, video: Boolean = false) {
        val trimmed = link.trim()
        if (trimmed.isEmpty()) return
        if (_state.value.call != null) {
            _state.update { it.copy(errorMessage = "Сначала закончите текущий звонок") }
            return
        }
        val id = UUID.randomUUID().toString()
        CallLog.info("Вход в групповой звонок по ссылке, видео: $video")
        val peer = CallPeerInfo("", "Групповой звонок", isGroup = true)
        _state.update {
            it.copy(
                call = ActiveCall(id, "", ActiveCall.Direction.GROUP, peer, video, state = CallState(), answered = true),
                isExpanded = true,
                errorMessage = null,
            )
        }
        try {
            val preview = try {
                service.preview(trimmed)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            val connection = service.join(trimmed, video)
            val control = engine.makeCall(connection, CallRole.JOINER, isGroup = true, expiresAtMs = null)
            val call = _state.value.call
            if (call?.id != id || call.state.isEnded) {
                control.start()
                control.hangUp()
                return
            }
            updateCall(id) {
                it.copy(
                    peer = preview?.name?.let { name -> it.peer.copy(name = name) } ?: it.peer,
                    conversationId = connection.conversationId,
                    joinLink = connection.joinLink ?: preview?.url ?: trimmed,
                )
            }
            attach(control, id)
            if (video) control.setCamera(true)
            control.start()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // Error тоже: без нативной библиотеки WebRTC движок бросает UnsatisfiedLinkError.
            if (!recoverable(e)) throw e
            fail(id, e)
        }
    }

    /** Создать групповой звонок со ссылкой. Войти в него — [join]. */
    suspend fun createLink(): String? = try {
        service.createLink().also { _state.update { s -> s.copy(errorMessage = null) } }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        _state.update { it.copy(errorMessage = message(e)) }
        null
    }

    // endregion

    // region Входящий

    internal suspend fun receive(incoming: IncomingCall) {
        if (_state.value.call != null) {
            CallLog.info("Входящий ${incoming.conversationId} во время звонка — не беру")
            return
        }
        val expires = incoming.expiresAtMs
        if (expires != null && expires <= now()) {
            CallLog.info("Входящий ${incoming.conversationId} уже истёк")
            return
        }
        val id = UUID.randomUUID().toString()
        CallLog.info("Входящий ${incoming.conversationId} от ${incoming.callerId}, видео: ${incoming.isVideo}, ICE-серверов: ${incoming.connection.iceServers.size}")
        val peer = CallPeerInfo(incoming.callerId, incoming.callerName, incoming.callerAvatarUrl)
        _state.update {
            it.copy(
                call = ActiveCall(
                    id, incoming.conversationId, ActiveCall.Direction.INCOMING, peer, incoming.isVideo,
                    state = CallState(phase = CallPhase.Ringing), answered = false,
                ),
                isExpanded = true,
            )
        }
        try {
            val control = engine.makeCall(incoming.connection, CallRole.CALLEE, isGroup = false, expiresAtMs = incoming.expiresAtMs)
            attach(control, id)
            if (incoming.callerName.isEmpty()) resolveCaller(incoming.callerId, id)
            control.start()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // Раньше исключение отсюда уходило в корутину входящих и роняло приложение.
            if (!recoverable(e)) throw e
            fail(id, e, text = "Не удалось принять звонок")
        }
    }

    /** Ответить на входящий. */
    suspend fun answer(video: Boolean = false) {
        val call = _state.value.call ?: return
        val control = control ?: return
        if (!call.isRinging) return
        CallLog.info("Ответ на входящий ${call.conversationId}, видео: $video")
        updateCall(call.id) { it.copy(answered = true) }
        _state.update { it.copy(isExpanded = true) }
        control.accept(video)
    }

    /**
     * Отклонить входящий: сначала отбой на сервере (167, `REJECTED`) — так звонок перестаёт звонить
     * на других устройствах и без открытого сокета звонка, — затем трубка кладётся как раньше.
     * Ошибка 167 не мешает отбою через сокет.
     */
    suspend fun decline() {
        val call = _state.value.call
        if (call != null && call.isRinging && call.conversationId.isNotEmpty()) {
            try {
                service.reject(call.conversationId, call.peer.id)?.takeIf { it.isNotBlank() }?.let {
                    CallLog.warning("167 не принят: $it")
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                CallLog.warning("167 не ушёл: $e")
            }
        }
        hangUp()
    }

    /** Положить трубку. */
    suspend fun hangUp() {
        val call = _state.value.call ?: return
        CallLog.info("Положить трубку: ${call.conversationId.ifEmpty { "без номера" }}, фаза ${call.state.phase}")
        if (call.state.isEnded) {
            dismiss(call.id)
            return
        }
        val control = control
        if (control != null) {
            control.hangUp()
        } else {
            // Сервер ещё не ответил на звонок: экран закрывается сразу.
            update(call.id, call.state.copy(phase = CallPhase.Ended(CallEndReason.HungUp)))
        }
    }

    // endregion

    // region Во время звонка

    suspend fun toggleMute() = withLive { call, control -> control.setMuted(!call.state.muted) }

    suspend fun toggleCamera() = withLive { call, control -> control.setCamera(!call.state.cameraOn) }

    suspend fun switchCamera() = withLive { _, control -> control.switchCamera() }

    fun toggleSpeaker() {
        val call = _state.value.call ?: return
        if (!call.state.isEnded) control?.setSpeaker(!call.state.speakerOn)
    }

    suspend fun toggleScreenSharing() = withLive { call, control -> control.setScreenSharing(!call.state.screenSharing) }

    suspend fun toggleRecording() = withLive { call, control -> control.setRecording(!call.state.recording) }

    /** Позвать в идущий звонок пользователей Max. */
    suspend fun invite(userIds: List<String>) {
        val control = control ?: return
        try {
            control.invite(userIds)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            _state.update { it.copy(errorMessage = "Не удалось позвать в звонок") }
        }
    }

    fun dismissNotice() {
        control?.dismissNotice()
    }

    fun expand() = _state.update { it.copy(isExpanded = true) }

    fun minimize() = _state.update { if (it.call == null) it else it.copy(isExpanded = false) }

    fun dismissError() = _state.update { it.copy(errorMessage = null) }

    /** Показать сообщение о звонке (например, нет доступа к микрофону). */
    fun showError(message: String) = _state.update { it.copy(errorMessage = message) }

    // endregion

    // region Внутреннее

    private suspend fun withLive(block: suspend (ActiveCall, CallControl) -> Unit) {
        val call = _state.value.call ?: return
        val control = control ?: return
        if (!call.state.isEnded) block(call, control)
    }

    private fun attach(control: CallControl, id: String) {
        this.control = control
        controlWatch?.cancel()
        controlWatch = scope.launch { control.state.collect { update(id, it) } }
        update(id, control.state.value)
    }

    private fun updateCall(id: String, change: (ActiveCall) -> ActiveCall) {
        _state.update { state ->
            val call = state.call
            if (call?.id == id) state.copy(call = change(call)) else state
        }
    }

    private fun update(id: String, next: CallState) {
        val call = _state.value.call ?: return
        if (call.id != id) return
        val previous = call.state
        if (previous.phase != next.phase) CallLog.info("Фаза звонка: ${previous.phase} → ${next.phase}")
        var updated = call.copy(state = next)
        if (call.direction == ActiveCall.Direction.INCOMING && !call.answered && next.phase != CallPhase.Ringing && !next.isEnded) {
            updated = updated.copy(answered = true)
        }
        _state.update { it.copy(call = updated) }
        resolveParticipants(next)
        val reason = (next.phase as? CallPhase.Ended)?.reason
        if (reason != null && !previous.isEnded) finished(id)
    }

    private fun finished(id: String) {
        control = null
        controlWatch?.cancel()
        controlWatch = null
        onCallEnded?.invoke()
        dismissal?.cancel()
        dismissal = scope.launch {
            delay(endedDisplayMs)
            dismiss(id)
        }
    }

    private fun dismiss(id: String) {
        if (_state.value.call?.id != id) return
        _state.update { it.copy(call = null, isExpanded = true) }
        dismissal?.cancel()
        dismissal = null
    }

    private fun fail(id: String, error: Throwable, text: String = "Не удалось позвонить") {
        CallLog.error("Звонок не начался", error)
        val shown = CoreErrors.text(error, text)
        // Движок мог успеть подключиться: его надо отпустить, иначе он держит микрофон.
        val orphan = control.takeIf { _state.value.call?.id == id }
        if (orphan != null) {
            control = null
            controlWatch?.cancel()
            controlWatch = null
            scope.launch { runCatching { orphan.hangUp() } }
        }
        _state.update { state ->
            if (state.call?.id == id) state.copy(call = null, isExpanded = true, errorMessage = shown) else state.copy(errorMessage = shown)
        }
    }

    /** Что можно пережить: исключения и сбои загрузки классов и нативных библиотек. */
    private fun recoverable(error: Throwable) = error is Exception || error is LinkageError

    private fun message(error: Throwable): String = CoreErrors.text(error)

    private fun resolveCaller(userId: String, id: String) {
        scope.launch {
            val found = lookup(userId) ?: return@launch
            updateCall(id) { call ->
                call.copy(
                    peer = call.peer.copy(
                        name = call.peer.name.ifEmpty { found.name },
                        avatarUrl = call.peer.avatarUrl ?: found.avatarUrl,
                    ),
                )
            }
        }
    }

    private fun resolveParticipants(state: CallState) {
        val peerId = _state.value.call?.peer?.id
        val unknown = state.participants.mapNotNull { it.userId }
            .filter { it !in _state.value.names && it !in lookedUp && it != peerId }
        if (unknown.isEmpty()) return
        lookedUp += unknown
        for (userId in unknown) {
            scope.launch {
                val found = lookup(userId) ?: return@launch
                _state.update { it.copy(names = it.names + (userId to found)) }
            }
        }
    }

    // endregion
}

/** Подписи экрана звонка. */
object CallStatusText {
    /** Строка под именем: «Вызов…», «Входящий видеозвонок», «1:05», «Переподключение…». */
    fun status(call: ActiveCall, nowMs: Long): String = when (val phase = call.state.phase) {
        CallPhase.Connecting ->
            if (call.direction == ActiveCall.Direction.INCOMING && !call.answered) incomingTitle(call.isVideo) else "Соединение…"
        CallPhase.Ringing -> if (call.direction == ActiveCall.Direction.INCOMING) incomingTitle(call.isVideo) else "Вызов…"
        CallPhase.Active -> {
            val since = call.state.activeSinceMs
            if ((!call.state.mediaConnected && call.state.topology != CallTopology.SERVER) || since == null) {
                "Соединение…"
            } else {
                val elapsed = duration(((nowMs - since) / 1000).toInt())
                if (call.direction == ActiveCall.Direction.GROUP || call.state.others.size > 1) {
                    "$elapsed · ${participants(call.state.participants.size)}"
                } else {
                    elapsed
                }
            }
        }
        CallPhase.Reconnecting -> "Переподключение…"
        is CallPhase.Ended -> ended(phase.reason)
    }

    fun incomingTitle(video: Boolean) = if (video) "Входящий видеозвонок" else "Входящий звонок"

    fun ended(reason: CallEndReason): String = when (reason) {
        CallEndReason.HungUp, CallEndReason.RemoteHungUp -> "Звонок завершён"
        CallEndReason.Declined -> "Звонок отклонён"
        CallEndReason.Busy -> "Абонент занят"
        CallEndReason.NoAnswer -> "Нет ответа"
        CallEndReason.Rejected -> "Вы отклонили звонок"
        CallEndReason.Missed -> "Пропущенный звонок"
        CallEndReason.ConnectionLost -> "Связь прервалась"
        is CallEndReason.Failed -> reason.message.ifEmpty { "Не удалось позвонить" }
    }

    /** `0:42`, `12:05`, `1:02:03`. */
    fun duration(seconds: Int): String {
        val total = seconds.coerceAtLeast(0)
        val hours = total / 3600
        val minutes = total % 3600 / 60
        val rest = total % 60
        return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, rest) else "%d:%02d".format(minutes, rest)
    }

    /** «3 участника», «5 участников». */
    fun participants(count: Int): String {
        val mod100 = count % 100
        val mod10 = count % 10
        val word = when {
            mod100 in 11..14 -> "участников"
            mod10 == 1 -> "участник"
            mod10 in 2..4 -> "участника"
            else -> "участников"
        }
        return "$count $word"
    }
}
