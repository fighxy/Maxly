package app.maxly.data.calls

import app.maxly.domain.CallCameraPosition
import app.maxly.domain.CallConnection
import app.maxly.domain.CallEndReason
import app.maxly.domain.CallIceServer
import app.maxly.domain.CallParticipant
import app.maxly.domain.CallPhase
import app.maxly.domain.CallRole
import app.maxly.domain.CallState
import app.maxly.domain.CallTopology
import app.maxly.domain.OrbitleError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Один звонок: подключение к серверу звонков, звук и видео. */
interface CallControl {
    val state: StateFlow<CallState>

    /** Подключиться к серверу звонков. Входящий до [accept] только слушает: так видно, что звонящий сбросил. */
    suspend fun start()

    /** Ответить на входящий, сразу с камерой или без. */
    suspend fun accept(video: Boolean)

    /** Положить трубку; у входящего до ответа — отклонить. */
    suspend fun hangUp()

    suspend fun setMuted(muted: Boolean)

    suspend fun setCamera(on: Boolean)

    suspend fun switchCamera()

    suspend fun setScreenSharing(on: Boolean)

    fun setSpeaker(on: Boolean)

    /** Запись звонка на сервере. Включать может админ группового звонка. */
    suspend fun setRecording(on: Boolean)

    /** Позвать в идущий звонок пользователей Max. Бросает [OrbitleError]. */
    suspend fun invite(userIds: List<String>)

    fun dismissNotice()
}

/** Делает звонки: сигнальный сокет и WebRTC. */
fun interface CallEngine {
    fun makeCall(connection: CallConnection, role: CallRole, isGroup: Boolean, expiresAtMs: Long?): CallControl
}

/**
 * Один звонок: сигнальный сокет ws2 сервера звонков и WebRTC. Порт iOS `CallSession`.
 *
 * Протокол звонка, код свой:
 * 1. Сокет ws2 открывается по адресу из ответа на звонок или из пуша входящего.
 * 2. Сервер присылает `connection`: участники, топология и серверы ICE.
 * 3. Напрямую (`DIRECT`): звонящий шлёт офер собеседнику через `transmit-data`, тот отвечает,
 *    кандидаты ICE идут так же. Кандидаты до удалённого SDP придерживаются.
 * 4. Через сервер (`SERVER`, SFU): `allocate-consumer`, сервер шлёт офер в `producer-updated`,
 *    ответ уходит в `accept-producer` вместе с номерами ssrc.
 * 5. `accept-call` — ответить; `hangup` — положить трубку с причиной.
 *
 * Входящий до ответа уже держит сокет открытым: так видно, что звонящий сбросил. Офер,
 * пришедший до ответа, ждёт его. Всё работает в [scope] на одном потоке (главном).
 */
class CallSession(
    private val connection: CallConnection,
    private val role: CallRole,
    isGroup: Boolean = false,
    private val media: CallMedia,
    private val connector: Ws2Connector,
    private val scope: CoroutineScope,
    private val timing: Timing = Timing(),
    private val expiresAtMs: Long? = null,
    private val now: () -> Long = System::currentTimeMillis,
) : CallControl {
    /** Задержки и пределы, мс. Тесты ставят свои, чтобы не ждать. */
    data class Timing(
        /** Сколько ждать `connection`, прежде чем толкнуть сервер командой. */
        val wake: Long = 1_200,
        /** Сколько ждать сбора кандидатов перед ответом SFU. */
        val gathering: Long = 5_000,
        /** Сколько звонить собеседнику без ответа. */
        val outgoingRing: Long = 90_000,
        /** Сколько звонит входящий, если сервер не сказал срок. */
        val incomingRing: Long = 60_000,
        /** Паузы между попытками переподключения. */
        val reconnect: List<Long> = listOf(1, 2, 4, 8, 16, 20, 20, 20, 20, 20, 20, 20).map { it * 1_000L },
        /** Как часто мерить уровень звука для подсветки говорящего. */
        val levels: Long = 400,
        /** Сколько раз перезапускать ICE, пока не сдаться. */
        val iceRestarts: Int = 6,
        /** Сколько ждать ответа сервера на команду. */
        val command: Long = 15_000,
    )

    private val isGroup = isGroup || role == CallRole.JOINER
    private val _state = MutableStateFlow(CallState(phase = if (role == CallRole.CALLEE) CallPhase.Ringing else CallPhase.Connecting))
    override val state: StateFlow<CallState> = _state.asStateFlow()
    private var current: CallState
        get() = _state.value
        set(value) {
            _state.value = value
        }

    private var signaling: Ws2Signaling? = null
    private var listener: Job? = null
    private var peer: CallPeer? = null

    /** `ice-ufrag` последнего SDP собеседника: его смена значит перезапуск ICE с той стороны. */
    private var remoteUfrag: String? = null
    private var target: CallPeerAddress? = null
    private var iceServers: List<CallIceServer> = connection.iceServers
    private var topology = CallTopology.DIRECT
    private var gotConnection = false
    private var acceptSent = false

    /** Входящий: пользователь ответил. */
    private var answered = role != CallRole.CALLEE
    private var remoteSet = false
    private var pendingCandidates = mutableListOf<IceCandidate>()

    /** Входящий до ответа: `transmitted-data`, которое ждёт ответа. */
    private var held = mutableListOf<JsonObject>()
    private val members = HashMap<Long, CallParticipant>()
    private val memberOrder = mutableListOf<Long>()
    private val cameraTracks = HashMap<Long, String>()
    private val screenTracks = HashMap<Long, String>()
    private var speaking: Set<Long> = emptySet()
    private val speakHold = HashMap<Long, Int>()
    private var sfuSession: JsonElement? = null
    private val sfuChannels = mutableListOf<CallDataChannel>()
    private var sfuCommand: CallDataChannel? = null
    private val sfuAliases = HashMap<Int, String>()
    /** SFU: `mid` слота своего видео из последнего офера сервера, если ответ отдал в него видео. Пусто — слот не согласован на отправку, видео попадёт в него со следующим офером. */
    private var slotMids: Set<String> = emptySet()
    /** Что сейчас в слоте: экран, камера или ничего. */
    private var slotVideo: LocalVideo? = null
    /** Под какой подписью сервер знает видео слота (последний `accept-producer`). */
    private var slotLabel: LocalVideo? = null
    /** Номера ssrc из последнего офера сервера: они повторяются в каждом `accept-producer`. */
    private var producerSsrcs: List<String> = emptyList()
    private val slotOwners = HashMap<Int, TrackOwner>()
    private var layoutSequence = 1
    private var lastLayout: List<String>? = null
    private var ended = false
    private var reconnecting = false
    private var iceRestarts = 0
    private var gatherWaiter: CompletableDeferred<Unit>? = null
    private var ringTimer: Job? = null
    private var levelTimer: Job? = null

    init {
        val me = CallParticipant(connection.selfId, isSelf = true)
        members[me.id] = me
        memberOrder += me.id
        publish()
    }

    // region CallControl

    override suspend fun start() {
        if (signaling != null || ended) return
        try {
            openSignaling()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CallLog.warning("ws2 не открылся: $e")
            end(if (role == CallRole.CALLEE && !answered) CallEndReason.Missed else CallEndReason.Failed("Сервер звонков недоступен"))
            return
        }
        armRingTimer()
        startLevels()
    }

    override suspend fun accept(video: Boolean) {
        if (role != CallRole.CALLEE || answered || ended) return
        answered = true
        ringTimer?.cancel()
        current = current.copy(phase = CallPhase.Connecting)
        if (video) turnCamera(on = true, announce = false)
        val signaling = signaling
        if (signaling == null) {
            start()
            return
        }
        if (gotConnection) setUpMedia() else scheduleWake(signaling)
    }

    override suspend fun hangUp() {
        if (ended) return
        val reason = hangupReason()
        val local = if (role == CallRole.CALLEE && !answered) CallEndReason.Rejected else CallEndReason.HungUp
        val signaling = signaling
        end(local, closeSignaling = false)
        val hangup = mapOf("reason" to JsonPrimitive(reason))
        if (signaling != null) {
            runCatching { signaling.send("hangup", hangup) }
            signaling.close()
        } else if (role == CallRole.CALLEE) {
            // Отклонить можно и до того, как сокет открылся: открыть, сказать и закрыть.
            val socket = try {
                Ws2Signaling.connect(connection.signalingUrl, connector, scope, timing.command)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            if (socket != null) {
                runCatching { socket.send("hangup", hangup) }
                socket.close()
            }
        }
    }

    override suspend fun setMuted(muted: Boolean) {
        if (ended) return
        applyMuted(muted)
        sendMediaSettings()
    }

    override suspend fun setCamera(on: Boolean) {
        if (ended || on == current.cameraOn) return
        turnCamera(on, announce = true)
    }

    override suspend fun switchCamera() {
        if (ended) return
        val next = if (current.camera == CallCameraPosition.FRONT) CallCameraPosition.BACK else CallCameraPosition.FRONT
        current = current.copy(camera = next)
        if (!current.cameraOn) return
        try {
            media.startCamera(next)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            current = current.copy(notice = "Не удалось переключить камеру")
        }
    }

    override suspend fun setScreenSharing(on: Boolean) {
        if (ended || on == current.screenSharing) return
        if (on) {
            try {
                media.startScreen()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val denied = (e as? CallMediaException)?.kind == CallMediaException.Kind.DENIED
                current = current.copy(notice = if (denied) "Показ экрана не разрешён" else "Не удалось показать экран")
                return
            }
            current = current.copy(screenSharing = true)
            try {
                if (topology == CallTopology.SERVER) {
                    refillSlot()
                } else {
                    peer?.let { peer -> if (peer.sendVideo(LocalVideo.SCREEN)) sendOffer() }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                CallLog.warning("Показ экрана: дорожка не ушла в соединение ($e)")
                media.stopScreen()
                current = current.copy(screenSharing = false, notice = "Не удалось показать экран")
            }
        } else {
            if (topology != CallTopology.SERVER || slotMids.isEmpty()) detachVideo(LocalVideo.SCREEN)
            media.stopScreen()
            current = current.copy(screenSharing = false)
            // SFU: в освободившийся слот возвращается камера.
            if (topology == CallTopology.SERVER) refillSlot()
        }
        updateLocalTrack()
        sendMediaSettings()
        publishLayout()
    }

    override fun setSpeaker(on: Boolean) {
        if (ended) return
        media.setSpeaker(on)
        current = current.copy(speakerOn = on)
    }

    override suspend fun setRecording(on: Boolean) {
        val signaling = signaling ?: return
        if (ended) return
        try {
            if (on) signaling.send("record-start", Ws2Command.recordStart) else signaling.send("record-stop")
            current = current.copy(recording = on)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CallLog.warning("Запись звонка: $e")
            current = current.copy(notice = if (on) "Запись недоступна" else "Не удалось остановить запись")
        }
    }

    override suspend fun invite(userIds: List<String>) {
        if (userIds.isEmpty()) return
        val signaling = signaling
        if (signaling == null || ended) throw OrbitleError.InvalidRequest
        try {
            signaling.send("add-participant", mapOf("externalIds" to element(userIds)))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CallLog.warning("Не позвали в звонок: $e")
            throw OrbitleError.InvalidRequest
        }
    }

    override fun dismissNotice() {
        current = current.copy(notice = null)
    }

    // endregion

    // region Сигнальный сокет

    private suspend fun openSignaling() {
        val signaling = Ws2Signaling.connect(connection.signalingUrl, connector, scope, timing.command)
        if (ended) {
            signaling.close()
            return
        }
        this.signaling = signaling
        gotConnection = false
        listener = scope.launch {
            for (message in signaling.notifications) {
                // Одно непонятое уведомление не роняет звонок: оно пишется в журнал и пропускается.
                try {
                    handle(message, signaling)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    val name = message["notification"].str ?: message["type"].str
                    CallLog.error("ws2: не обработано уведомление $name", e)
                }
            }
            signalingLost(signaling)
        }
        if (answered) scheduleWake(signaling)
    }

    /** Сервер иногда молчит после рукопожатия. Тогда его будит `change-media-settings`, а если и это не помогло — `accept-call`. */
    private fun scheduleWake(signaling: Ws2Signaling) {
        scope.launch {
            delay(timing.wake)
            if (!isSilent(signaling)) return@launch
            CallLog.info("ws2 молчит — шлю change-media-settings")
            runCatching { signaling.send("change-media-settings", mapOf("mediaSettings" to mediaSettings)) }
            delay(timing.wake)
            if (!isSilent(signaling)) return@launch
            CallLog.info("ws2 всё ещё молчит — шлю accept-call")
            sendAccept(activate = false)
        }
    }

    private fun isSilent(signaling: Ws2Signaling) = !ended && !gotConnection && this.signaling === signaling && answered

    private fun signalingLost(source: Ws2Signaling) {
        if (source !== signaling || ended || reconnecting) return
        if (role == CallRole.CALLEE && !answered) {
            end(CallEndReason.Missed)
            return
        }
        CallLog.warning("ws2 оборвался, переподключаюсь")
        scope.launch { reconnect() }
    }

    private suspend fun reconnect() {
        reconnecting = true
        current = current.copy(phase = CallPhase.Reconnecting)
        for (pause in timing.reconnect) {
            delay(pause)
            if (ended) break
            resetConnection()
            try {
                openSignaling()
                reconnecting = false
                return
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                CallLog.warning("Переподключение не удалось: $e")
            }
        }
        reconnecting = false
        if (!ended) end(CallEndReason.ConnectionLost)
    }

    /** Перед новой попыткой: старый сокет и соединение WebRTC закрываются, свои камера и микрофон остаются. */
    private fun resetConnection() {
        listener?.cancel()
        listener = null
        signaling?.close()
        signaling = null
        closePeer()
        acceptSent = false
        sfuSession = null
        gotConnection = false
    }

    // endregion

    // region Уведомления

    private suspend fun handle(message: JsonObject, source: Ws2Signaling) {
        if (source !== signaling || ended) return
        if (message["type"].str == "error") {
            CallLog.warning("ws2 ошибка: ${message["error"]}")
            if (message["error"].str == "conversation-ended") end(closedReason())
            return
        }
        val name = message["notification"].str.orEmpty()
        if (!answered && name == "transmitted-data") {
            held += message
            return
        }
        if (name != "connection") applyMediaSettings(message)
        when (name) {
            "connection" -> onConnection(message)
            "transmitted-data" -> onTransmittedData(message)
            "accepted-call" -> if (role == CallRole.CALLER) activate()
            "participant-joined", "participant-added" -> onParticipantJoined(message)
            "media-settings-changed" -> onParticipantMedia(message)
            "participant-state-changed" -> onParticipantState(message)
            "roles-changed" -> onRoles(message)
            "participants-state-changed" -> onParticipantsState(message)
            "participant-left", "participant-removed" -> onParticipantLeft(message)
            "force-media-settings-change", "switch-micro" -> onForcedMedia(message)
            "mute-participant" -> onMuteParticipant(message)
            "hungup" -> onHungUp(message)
            "topology-changed" -> onTopologyChanged(message)
            "producer-updated" -> onProducerUpdated(message)
            "closed-conversation" -> end(closedReason())
        }
    }

    private suspend fun onConnection(message: JsonObject) {
        gotConnection = true
        val conversation = message["conversation"]
        iceServers(message["conversationParams"])?.let { iceServers = it }
        resolvePeer(conversation)
        resolveParticipants(conversation)
        conversation["features"].arr?.let { features ->
            current = current.copy(recording = features.any { it.str == "RECORD" })
        }
        CallTopology.of(conversation["topology"].str)?.let {
            topology = it
            current = current.copy(topology = it)
        }
        CallLog.info("connection: роль $role, топология $topology, участников ${members.size}")
        if (!answered) return
        setUpMedia()
    }

    /** После `connection` (а у входящего — после ответа): соединение WebRTC и `accept-call`. */
    private suspend fun setUpMedia() {
        if (ended || peer != null) return
        if (topology == CallTopology.SERVER) {
            sendAccept(activate = role != CallRole.CALLER)
            setUpSfu()
            return
        }
        val peer = makePeer() ?: return
        peer.addMicrophone()
        if (current.cameraOn) peer.sendVideo(LocalVideo.CAMERA)
        if (current.screenSharing) peer.sendVideo(LocalVideo.SCREEN)
        peer.addVideoReceiver()
        if (role == CallRole.CALLER) {
            if (current.activeSinceMs == null) current = current.copy(phase = CallPhase.Ringing)
            sendOffer()
        } else if (role == CallRole.JOINER) {
            sendOffer()
        }
        sendAccept(activate = role != CallRole.CALLER)
        val waiting = held
        held = mutableListOf()
        for (message in waiting) onTransmittedData(message)
    }

    private suspend fun onTransmittedData(message: JsonObject) {
        val peer = peer ?: return
        // Собеседника не было в `connection`: отвечать тому, кто прислал.
        if (target == null) {
            val from = CallSdp.participantId(message["participantId"])
            if (from != null && from != connection.selfId) {
                target = CallPeerAddress(from, message["participantType"].str ?: "USER", message["deviceIdx"].long ?: 0)
            }
        }
        val data = message["data"]
        val sdp = data["sdp"]
        val type = SdpType.of(sdp["type"].str)
        val text = sdp["sdp"].str
        if (type != null && text != null) {
            if (type == SdpType.ANSWER && peer.signalingState != PeerSignalingState.HAVE_LOCAL_OFFER) return
            if (type == SdpType.OFFER && peer.signalingState == PeerSignalingState.HAVE_LOCAL_OFFER) {
                CallLog.info("Встречный офер: откатываю свой")
                runCatching { peer.setLocal(SessionDescription(SdpType.ROLLBACK, "")) }
            }
            val ufrag = CallSdp.iceUfrag(text)
            if (ufrag != null && remoteUfrag != null && ufrag != remoteUfrag) {
                CallLog.info("Собеседник сменил ICE-учётку в $type: транспорт перезапустится")
            }
            try {
                peer.setRemote(SessionDescription(type, text))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                CallLog.warning("Удалённый SDP не принят: $e")
                return
            }
            if (ufrag != null) remoteUfrag = ufrag
            if (peer !== this.peer) return
            remoteSet = true
            flushCandidates()
            val target = target
            if (type == SdpType.OFFER && target != null) {
                try {
                    val answer = peer.makeAnswer()
                    peer.setLocal(answer)
                    if (peer !== this.peer) return
                    runCatching { signaling?.send("transmit-data", Ws2Command.transmit(labeled(answer), target)) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    CallLog.warning("Ответ на офер не собрался: $e")
                }
            }
            collectRemoteTracks()
            return
        }
        val candidate = data["candidate"]
        val line = candidate["candidate"].str ?: return
        val ice = IceCandidate(line, candidate["sdpMid"].str, (candidate["sdpMLineIndex"].long ?: 0).toInt())
        if (remoteSet) peer.add(ice) else pendingCandidates += ice
    }

    private fun onHungUp(message: JsonObject) {
        val raw = message["participantId"] ?: message["participant"]["id"]
        val id = CallSdp.participantId(raw) ?: return
        if (id == connection.selfId) {
            end(CallEndReason.RemoteHungUp)
            return
        }
        removeMember(id)
        if (isGroup) return
        val reason = when (message["reason"].str?.uppercase()) {
            "REJECTED" -> if (role == CallRole.CALLER) CallEndReason.Declined else CallEndReason.RemoteHungUp
            "BUSY" -> CallEndReason.Busy
            "MISSED", "TIMEOUT" -> if (role == CallRole.CALLER) CallEndReason.NoAnswer else CallEndReason.Missed
            "CANCELED" -> if (role == CallRole.CALLEE && current.activeSinceMs == null) CallEndReason.Missed else CallEndReason.RemoteHungUp
            else -> if (role == CallRole.CALLEE && !answered) CallEndReason.Missed else CallEndReason.RemoteHungUp
        }
        end(reason)
    }

    private suspend fun onTopologyChanged(message: JsonObject) {
        val value = CallTopology.of(message["topology"].str) ?: return
        val toServer = value == CallTopology.SERVER && topology != CallTopology.SERVER
        topology = value
        current = current.copy(topology = value)
        if (toServer && answered && (peer != null || gotConnection)) setUpSfu()
    }

    // endregion

    // region SFU

    private suspend fun setUpSfu() {
        // Разговор шёл напрямую и переезжает на сервер — «переподключение»; иначе «соединение».
        val wasConnected = current.mediaConnected
        closePeer()
        current = current.copy(phase = if (wasConnected) CallPhase.Reconnecting else CallPhase.Connecting)
        val peer = makePeer() ?: return
        peer.addMicrophone()
        // Слот своего видео у сервера один: в него идёт экран, иначе камера.
        outgoingVideo?.let { peer.sendVideo(it) }
        openSfuChannels(peer)
        try {
            signaling?.send("allocate-consumer", Ws2Command.allocateConsumer)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CallLog.warning("allocate-consumer: $e")
        }
    }

    private suspend fun onProducerUpdated(message: JsonObject) {
        if (peer == null) return
        val session = message["sessionId"]?.takeUnless { it is JsonNull }
        val previous = sfuSession
        if (session != null && previous != null && session != previous) {
            CallLog.info("SFU сменил сессию — пересобираю соединение")
            closePeer()
            val fresh = makePeer() ?: return
            fresh.addMicrophone()
            outgoingVideo?.let { fresh.sendVideo(it) }
            openSfuChannels(fresh)
        }
        if (session != null) sfuSession = session
        val peer = peer ?: return

        val description = message["description"]
        var type = SdpType.OFFER
        val sdp: String? = when {
            description.str != null -> description.str
            description is JsonObject -> {
                SdpType.of(description["type"].str)?.let { type = it }
                description["sdp"].str ?: description["description"].str
            }
            else -> null
        }
        if (sdp == null) {
            CallLog.warning("producer-updated без SDP")
            return
        }
        val ssrcs = CallSdp.ssrcs(sdp)
        try {
            peer.setRemote(SessionDescription(type, sdp))
            if (peer !== this.peer) return
            remoteSet = true
            flushCandidates()
            for (candidate in CallSdp.candidates(sdp)) peer.add(candidate)
            val mids = CallSdp.receiveOnlyVideoMids(sdp)
            slotMids = emptySet()
            slotVideo = null
            val outgoing = outgoingVideo
            if (outgoing != null && peer.fillVideoSlot(mids, outgoing)) {
                slotMids = mids
                slotVideo = outgoing
            }
            producerSsrcs = ssrcs
            val answer = peer.makeAnswer()
            if (peer !== this.peer) return
            peer.setLocal(answer)
            if (peer !== this.peer) return
            waitForGathering(peer)
            if (peer !== this.peer) return
            val local = peer.localDescription?.sdp ?: answer.sdp
            slotLabel = slotVideo
            signaling?.send("accept-producer", producerAnswer(local))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CallLog.warning("SFU: офер сервера не принят: $e")
            return
        }
        if (acceptSent) sendMediaSettings()
        collectRemoteTracks()
        publishLayout(force = true)
    }

    /** Тело `accept-producer`: свой ответ с подписями, ssrc и сессия из офера сервера. */
    private fun producerAnswer(sdp: String): Map<String, JsonElement> {
        val body = LinkedHashMap<String, JsonElement>()
        body["description"] = JsonPrimitive(labeled(SessionDescription(SdpType.ANSWER, sdp)).sdp)
        if (producerSsrcs.isNotEmpty()) body["ssrcs"] = element(producerSsrcs)
        sfuSession?.let { body["sessionId"] = it }
        return body
    }

    /**
     * SFU: в единственный слот своего видео кладётся то, что сейчас главное (экран, иначе камера).
     * Новый отправитель не добавляется: дорожка меняется в отправителе слота, согласование не нужно.
     * Но сервер узнаёт видео по подписи в SDP (`u<id>:sCAMERA` / `u<id>:sSCREEN`), а она осталась от
     * прежней дорожки, поэтому тот же ответ уходит ещё раз `accept-producer` с новой подписью. Слот
     * не согласован на отправку — видео ляжет в него со следующим офером сервера.
     */
    private suspend fun refillSlot() {
        val peer = peer ?: return
        if (topology != CallTopology.SERVER || slotMids.isEmpty()) return
        val wanted = outgoingVideo
        if (wanted != slotVideo) {
            if (wanted != null) {
                peer.fillVideoSlot(slotMids, wanted)
            } else {
                slotVideo?.let(::detachVideo)
            }
            slotVideo = wanted
        }
        val local = peer.localDescription
        if (wanted == null || wanted == slotLabel || local == null || local.type != SdpType.ANSWER) return
        slotLabel = wanted
        CallLog.info("SFU: в слоте своего видео теперь $wanted, шлю новую подпись")
        try {
            signaling?.send("accept-producer", producerAnswer(local.sdp))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CallLog.warning("accept-producer с новой подписью: $e")
        }
    }

    private val outgoingVideo: LocalVideo?
        get() = when {
            current.screenSharing -> LocalVideo.SCREEN
            current.cameraOn -> LocalVideo.CAMERA
            else -> null
        }

    private fun openSfuChannels(peer: CallPeer) {
        closeSfuChannels()
        for (label in listOf(SfuChannel.COMMAND_LABEL, SfuChannel.NOTIFICATION_LABEL)) {
            val channel = peer.openChannel(label) ?: continue
            if (label == SfuChannel.COMMAND_LABEL) {
                sfuCommand = channel
                channel.onOpen = { publishLayout(force = true) }
            } else {
                channel.onMessage = { onSfuNotification(it) }
            }
            sfuChannels += channel
        }
    }

    private fun closeSfuChannels() {
        sfuChannels.forEach { it.close() }
        sfuChannels.clear()
        sfuCommand = null
        sfuAliases.clear()
        slotOwners.clear()
        lastLayout = null
    }

    private fun onSfuNotification(data: ByteArray) {
        if (ended) return
        when (val notification = SfuChannel.parse(data, sfuAliases) ?: return) {
            is SfuChannel.Notification.Aliases -> sfuAliases.putAll(notification.map)
            is SfuChannel.Notification.Slots -> {
                if (notification.map.isEmpty()) return
                slotOwners.clear()
                for ((key, slot) in notification.map) {
                    if (slot < 0) continue
                    val owner = CallSdp.owner(key).copy(slot = slot)
                    if (owner.participant != null) slotOwners[slot] = owner
                }
                cameraTracks.clear()
                screenTracks.clear()
                collectRemoteTracks()
            }
            is SfuChannel.Notification.Levels -> {
                val loud = notification.map.filterValues { it >= 50 }.keys.mapNotNull { CallSdp.owner(it).participant }.toSet()
                if (loud != speaking) {
                    speaking = loud
                    publish()
                }
            }
        }
    }

    /** Какие видео присылать: камера или экран каждого, у кого они включены, до 10 окон. */
    private fun publishLayout(force: Boolean = false) {
        val channel = sfuCommand
        if (topology != CallTopology.SERVER || ended || channel == null || !channel.isOpen) return
        val items = others.filter { it.videoOn || it.screenOn }.take(10)
            .map { SfuChannel.LayoutItem(CallSdp.layoutKey(it.id, it.screenOn)) }
        val keys = items.map { it.trackKey }
        if (!force && lastLayout?.toSet() == keys.toSet()) return
        if (channel.send(SfuChannel.displayLayout(items, layoutSequence))) {
            layoutSequence += 1
            lastLayout = keys
        }
    }

    // endregion

    // region WebRTC

    private fun makePeer(): CallPeer? {
        val peer = media.makePeer(iceServers)
        if (peer == null) {
            end(CallEndReason.Failed("Не удалось начать звонок"))
            return null
        }
        peer.onEvent = { event -> handlePeer(event, peer) }
        this.peer = peer
        remoteSet = false
        remoteUfrag = null
        pendingCandidates = mutableListOf()
        return peer
    }

    private fun closePeer() {
        closeSfuChannels()
        slotMids = emptySet()
        slotVideo = null
        slotLabel = null
        producerSsrcs = emptyList()
        resumeGathering()
        peer?.onEvent = null
        peer?.close()
        peer = null
        remoteSet = false
        remoteUfrag = null
        pendingCandidates = mutableListOf()
        cameraTracks.clear()
        screenTracks.clear()
        current = current.copy(mediaConnected = false)
    }

    private fun handlePeer(event: PeerEvent, source: CallPeer) {
        if (source !== peer || ended) return
        when (event) {
            is PeerEvent.Candidate -> {
                if (" typ relay" in event.candidate.sdp) resumeGathering()
                val target = target
                val signaling = signaling
                if (topology != CallTopology.DIRECT || target == null || signaling == null) return
                scope.launch { runCatching { signaling.send("transmit-data", Ws2Command.transmit(event.candidate, target)) } }
            }
            PeerEvent.GatheringComplete -> resumeGathering()
            is PeerEvent.State -> onPeerState(event.state)
            PeerEvent.IceFailed -> {
                val signaling = signaling
                if (topology != CallTopology.SERVER || signaling == null) return
                CallLog.warning("SFU: ICE не прошёл — request-realloc")
                scope.launch { runCatching { signaling.send("request-realloc") } }
            }
            is PeerEvent.Track -> bind(event.track)
        }
    }

    private fun onPeerState(peerState: PeerState) {
        val connected = peerState == PeerState.CONNECTED
        if (connected != current.mediaConnected) {
            current = current.copy(mediaConnected = connected)
            if (connected) {
                iceRestarts = 0
                if (role != CallRole.CALLER || topology == CallTopology.SERVER || current.activeSinceMs != null) activate()
                collectRemoteTracks()
            }
        }
        if (topology != CallTopology.DIRECT) return
        when (peerState) {
            PeerState.FAILED -> scope.launch { restartIce() }
            PeerState.CLOSED -> end(CallEndReason.ConnectionLost)
            else -> Unit
        }
    }

    private suspend fun restartIce() {
        if (ended || topology != CallTopology.DIRECT) return
        if (iceRestarts >= timing.iceRestarts) {
            CallLog.warning("ICE не восстановился")
            end(CallEndReason.ConnectionLost)
            return
        }
        iceRestarts += 1
        if (current.activeSinceMs != null) current = current.copy(phase = CallPhase.Reconnecting)
        pendingCandidates = mutableListOf()
        sendOffer(iceRestart = true)
    }

    private suspend fun sendOffer(iceRestart: Boolean = false) {
        val peer = peer ?: return
        val target = target ?: return
        try {
            val offer = peer.makeOffer(iceRestart)
            CallLog.info(if (iceRestart) "Офер собеседнику: с перезапуском ICE" else "Офер собеседнику: без перезапуска ICE")
            if (peer !== this.peer) return
            peer.setLocal(offer)
            if (peer !== this.peer) return
            signaling?.send("transmit-data", Ws2Command.transmit(labeled(offer), target))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CallLog.warning("Офер не ушёл: $e")
        }
    }

    private suspend fun flushCandidates() {
        val peer = peer ?: return
        if (pendingCandidates.isEmpty()) return
        val waiting = pendingCandidates
        pendingCandidates = mutableListOf()
        for (candidate in waiting) peer.add(candidate)
    }

    /** SFU ждёт ответ со всеми кандидатами: ждём конца сбора или кандидата TURN, но не дольше `timing.gathering`. */
    private suspend fun waitForGathering(peer: CallPeer) {
        if (peer.isGatheringComplete) return
        resumeGathering()
        val waiter = CompletableDeferred<Unit>()
        gatherWaiter = waiter
        withTimeoutOrNull(timing.gathering) { waiter.await() }
        if (gatherWaiter === waiter) gatherWaiter = null
    }

    private fun resumeGathering() {
        val waiter = gatherWaiter
        gatherWaiter = null
        waiter?.complete(Unit)
    }

    /**
     * Свои видеодорожки в SDP подписываются так, как их ищет сервер. В SFU слот своего видео
     * подписывается по `mid` тем, что в нём сейчас: id дорожки в SDP мог остаться от прежней.
     */
    private fun labeled(description: SessionDescription): SessionDescription {
        val names = HashMap<String, String>()
        media.trackId(LocalVideo.CAMERA)?.let { names[it] = CallSdp.layoutKey(connection.selfId, screen = false) }
        media.trackId(LocalVideo.SCREEN)?.let { names[it] = CallSdp.layoutKey(connection.selfId, screen = true) }
        var sdp = CallSdp.label(description.sdp, names)
        val video = slotVideo
        if (topology == CallTopology.SERVER && video != null) {
            sdp = CallSdp.label(sdp, slotMids, CallSdp.layoutKey(connection.selfId, screen = video == LocalVideo.SCREEN))
        }
        return description.copy(sdp = sdp)
    }

    private fun collectRemoteTracks() {
        val peer = peer ?: return
        peer.remoteTracks().forEach(::bind)
    }

    /** Видео собеседника — к участнику: по id дорожки, по слоту SFU или, напрямую, к собеседнику. */
    private fun bind(track: RemoteTrack) {
        if (track.kind != MediaKind.VIDEO) return
        var owner = CallSdp.owner(track.id)
        owner.slot?.let { slot -> owner = slotOwners[slot] ?: return }
        val peerId = target?.id
        if (owner.participant == null && topology == CallTopology.DIRECT && peerId != null) {
            val camera = cameraTracks[peerId]
            owner = owner.copy(participant = peerId, screen = owner.screen || (camera != null && camera != track.id))
        }
        val id = owner.participant ?: return
        if (id == connection.selfId) return
        val tracks = if (owner.screen) screenTracks else cameraTracks
        if (tracks[id] == track.id) return
        tracks[id] = track.id
        publish()
    }

    // endregion

    // region Участники

    private fun resolvePeer(conversation: JsonElement?) {
        if (isGroup && target != null) return
        for (participant in conversation["participants"].arr.orEmpty()) {
            val id = CallSdp.participantId(participant["id"]) ?: continue
            if (id == connection.selfId) continue
            target = CallPeerAddress(
                id = id,
                type = participant["responderTypes"].arr?.firstOrNull().str ?: target?.type ?: "USER",
                deviceIdx = participant["responderDeviceIdxs"].arr?.firstOrNull().long ?: target?.deviceIdx ?: 0,
            )
            return
        }
    }

    private fun resolveParticipants(conversation: JsonElement?) {
        val list = conversation["participants"].arr ?: return
        val seen = hashSetOf(connection.selfId)
        for (participant in list) {
            val id = CallSdp.participantId(participant["id"]) ?: continue
            seen += id
            upsert(id, participant)
        }
        memberOrder.filterNot { it in seen }.forEach { members.remove(it) }
        memberOrder.retainAll { it in seen }
        publish()
    }

    private fun upsert(id: Long, source: JsonElement?, roles: JsonElement? = null, hand: Boolean? = null) {
        var member = members[id] ?: CallParticipant(id, isSelf = id == connection.selfId)
        if (members[id] == null) memberOrder += id
        if (source != null) {
            source["externalId"]?.let { external ->
                val value = if (external is JsonObject) external["id"] else external
                val userId = value.long?.toString() ?: value.str?.takeIf { it.isNotEmpty() }
                if (userId != null) member = member.copy(userId = userId)
            }
            source["state"].str?.let { member = member.copy(state = it) }
            val settings = source["mediaSettings"]
            if (settings is JsonObject) {
                member = member.copy(
                    audioOn = settings["isAudioEnabled"].bool == true,
                    videoOn = settings["isVideoEnabled"].bool == true,
                    screenOn = settings["isScreenSharingEnabled"].bool == true,
                )
            }
            val mutes = source["muteStates"]
            if (mutes is JsonObject) {
                if (mutes["AUDIO"].str.let { it != null && it != "UNMUTE" }) member = member.copy(audioOn = false)
                if (mutes["VIDEO"].str.let { it != null && it != "UNMUTE" }) member = member.copy(videoOn = false)
                if (mutes["SCREEN_SHARING"].str.let { it != null && it != "UNMUTE" }) member = member.copy(screenOn = false)
            }
            source["roles"].arr?.let { list -> member = member.copy(roles = list.mapNotNull { it.str }) }
            hand(source["participantState"])?.let { member = member.copy(handRaised = it) }
        }
        roles.arr?.let { list -> member = member.copy(roles = list.mapNotNull { it.str }) }
        if (hand != null) member = member.copy(handRaised = hand)
        members[id] = member
    }

    private fun removeMember(id: Long) {
        if (id == connection.selfId || members[id] == null) return
        members.remove(id)
        memberOrder.remove(id)
        cameraTracks.remove(id)
        screenTracks.remove(id)
        publish()
        publishLayout()
    }

    private fun onParticipantJoined(message: JsonObject) {
        val source = message["participant"] as? JsonObject ?: message
        val id = CallSdp.participantId(source["id"] ?: source["participantId"] ?: message["participantId"]) ?: return
        upsert(id, source)
        adoptPeer(id, source)
        publish()
        publishLayout()
    }

    /** Вошедший по ссылке в звонок на двоих находит собеседника и шлёт ему офер. */
    private fun adoptPeer(id: Long, source: JsonElement) {
        if (role != CallRole.JOINER || target != null || peer == null || topology != CallTopology.DIRECT || id == connection.selfId) return
        target = CallPeerAddress(id, (source["participantType"] ?: source["idType"]).str ?: "USER", source["deviceIdx"].long ?: 0)
        scope.launch { sendOffer() }
    }

    private fun onParticipantMedia(message: JsonObject) {
        val id = CallSdp.participantId(message["participantId"]) ?: return
        upsert(id, message)
        adoptPeer(id, message)
        publish()
        publishLayout()
    }

    private fun onParticipantState(message: JsonObject) {
        val id = CallSdp.participantId(message["participantId"]) ?: return
        upsert(id, null, hand = hand(message["participantState"]))
        publish()
    }

    private fun onRoles(message: JsonObject) {
        val id = CallSdp.participantId(message["participantId"]) ?: return
        upsert(id, null, roles = message["roles"])
        publish()
    }

    private fun onParticipantsState(message: JsonObject) {
        for (participant in message["participants"].arr.orEmpty()) {
            val id = CallSdp.participantId(participant["participantId"] ?: participant["id"]) ?: continue
            upsert(id, participant)
        }
        publish()
        publishLayout()
    }

    private fun onParticipantLeft(message: JsonObject) {
        val id = CallSdp.participantId(message["participantId"]) ?: return
        removeMember(id)
        if (!isGroup && id == target?.id) end(CallEndReason.RemoteHungUp)
    }

    /** `mediaSettings` в любом уведомлении — о собеседнике (или об участнике из `participantId`). */
    private fun applyMediaSettings(message: JsonObject) {
        val settings = message["mediaSettings"] as? JsonObject ?: return
        val id = CallSdp.participantId(message["participantId"]) ?: target?.id ?: return
        if (id == connection.selfId) return
        val before = members[id]
        upsert(id, json("mediaSettings" to settings))
        val after = members[id]
        if (after != before) {
            publish()
            if (after?.videoOn == true || after?.screenOn == true) collectRemoteTracks()
        }
    }

    /** Админ включил или выключил наш микрофон. */
    private fun onForcedMedia(message: JsonObject) {
        var audioOn: Boolean? = null
        message["mediaSettings"]["isAudioEnabled"].bool?.let { audioOn = it }
        message["muteStates"]["AUDIO"].str?.let { audioOn = it == "UNMUTE" }
        message["mute"].bool?.let { audioOn = !it }
        val on = audioOn ?: return
        applyMuted(!on)
    }

    private fun onMuteParticipant(message: JsonObject) {
        val audio = message["muteStates"]["AUDIO"].str ?: return
        val audioOn = audio == "UNMUTE"
        val subject = CallSdp.participantId(message["participantId"])
        val member = subject?.let { members[it] }
        if (member != null && !member.isSelf) {
            members[member.id] = member.copy(audioOn = audioOn)
            publish()
        }
        if (message["muteAll"].bool == true || subject == null || subject == connection.selfId) applyMuted(!audioOn)
    }

    private fun hand(participantState: JsonElement?): Boolean? {
        val hand = participantState["state"]["hand"] ?: return null
        return hand.str == "1" || hand.bool == true
    }

    private val others: List<CallParticipant> get() = current.participants.filterNot { it.isSelf }

    /** Собирает участников для экрана: свой — по своему состоянию. */
    private fun publish() {
        val state = current
        current = state.copy(
            participants = memberOrder.mapNotNull { id ->
                val member = members[id] ?: return@mapNotNull null
                val shown = if (member.isSelf) {
                    member.copy(
                        audioOn = !state.muted,
                        videoOn = state.cameraOn,
                        screenOn = state.screenSharing,
                        cameraTrack = media.trackId(LocalVideo.CAMERA),
                        screenTrack = media.trackId(LocalVideo.SCREEN),
                    )
                } else {
                    member.copy(cameraTrack = cameraTracks[id], screenTrack = screenTracks[id])
                }
                shown.copy(speaking = id in speaking)
            },
        )
    }

    // endregion

    // region Своё медиа

    private suspend fun turnCamera(on: Boolean, announce: Boolean) {
        if (on) {
            try {
                media.startCamera(current.camera)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val denied = (e as? CallMediaException)?.kind == CallMediaException.Kind.DENIED
                current = current.copy(notice = if (denied) "Нет доступа к камере" else "Камера недоступна")
                return
            }
            current = current.copy(cameraOn = true)
            try {
                if (topology == CallTopology.SERVER) {
                    refillSlot()
                } else {
                    peer?.let { peer -> if (peer.sendVideo(LocalVideo.CAMERA)) sendOffer() }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                CallLog.warning("Камера: дорожка не ушла в соединение ($e)")
                media.stopCamera()
                current = current.copy(cameraOn = false, notice = "Не удалось включить камеру")
            }
        } else {
            if (topology != CallTopology.SERVER || slotMids.isEmpty()) detachVideo(LocalVideo.CAMERA)
            media.stopCamera()
            current = current.copy(cameraOn = false)
            if (topology == CallTopology.SERVER) refillSlot()
        }
        updateLocalTrack()
        publish()
        if (announce) sendMediaSettings()
    }

    /** Выключение не должно застревать: сбой соединения пишем в журнал, а захват всё равно останавливаем. */
    private fun detachVideo(video: LocalVideo) {
        try {
            peer?.stopVideo(video)
        } catch (e: Exception) {
            CallLog.warning("Видео $video: дорожка не снята с соединения ($e)")
        }
    }

    private fun updateLocalTrack() {
        val track = when {
            current.screenSharing -> media.trackId(LocalVideo.SCREEN)
            current.cameraOn -> media.trackId(LocalVideo.CAMERA)
            else -> null
        }
        current = current.copy(localTrack = track)
    }

    private fun applyMuted(muted: Boolean) {
        current = current.copy(muted = muted)
        media.setMicrophone(!muted)
        publish()
    }

    /**
     * В SFU слот своего видео один, и при показе экрана в нём экран: камера тогда только своё
     * превью, и серверу говорится `video: false`, иначе другие ждут камеру, которой нет.
     */
    private val mediaSettings: JsonObject
        get() {
            val screen = current.screenSharing
            val video = current.cameraOn && !(topology == CallTopology.SERVER && screen)
            return Ws2Command.mediaSettings(audio = !current.muted, video = video, screen = screen)
        }

    private suspend fun sendMediaSettings() {
        val signaling = signaling ?: return
        try {
            signaling.send("change-media-settings", mapOf("mediaSettings" to mediaSettings))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Ws2Exception.Command) {
            if (e.error == "conversation-ended") end(closedReason())
        } catch (_: Exception) {
        }
    }

    private suspend fun sendAccept(activate: Boolean) {
        val signaling = signaling
        if (!acceptSent && signaling != null) {
            acceptSent = true
            try {
                signaling.send("accept-call", mapOf("mediaSettings" to mediaSettings))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                CallLog.warning("accept-call: $e")
            }
        }
        if (activate) activate()
    }

    private fun activate() {
        if (ended) return
        ringTimer?.cancel()
        current = current.copy(activeSinceMs = current.activeSinceMs ?: now(), phase = CallPhase.Active)
    }

    // endregion

    // region Таймеры

    private fun armRingTimer() {
        ringTimer?.cancel()
        val limit = when {
            role == CallRole.CALLER -> timing.outgoingRing
            role == CallRole.CALLEE && !answered -> expiresAtMs?.let { (it - now()).coerceAtLeast(1_000) } ?: timing.incomingRing
            else -> return
        }
        ringTimer = scope.launch {
            delay(limit)
            if (ended || current.activeSinceMs != null) return@launch
            // Таймер больше не нужен: `end` не должен отменить этот же код посреди `hangup`.
            ringTimer = null
            if (role == CallRole.CALLER) {
                CallLog.info("Собеседник не ответил")
                val signaling = signaling
                end(CallEndReason.NoAnswer, closeSignaling = false)
                runCatching { signaling?.send("hangup", mapOf("reason" to JsonPrimitive("CANCELED"))) }
                signaling?.close()
            } else if (!answered) {
                end(CallEndReason.Missed)
            }
        }
    }

    /** Подсветка говорящего напрямую — по уровням звука WebRTC. В SFU уровни шлёт сервер. */
    private fun startLevels() {
        levelTimer?.cancel()
        levelTimer = scope.launch {
            while (isActive && !ended) {
                delay(timing.levels)
                sampleLevels()
            }
        }
    }

    private suspend fun sampleLevels() {
        val peer = peer ?: return
        if (topology != CallTopology.DIRECT || !current.mediaConnected) return
        val (local, remote) = peer.audioLevels() ?: return
        val loud = HashSet<Long>()
        if (!current.muted && local > 0.05) loud += connection.selfId
        val peerId = target?.id
        if (remote > 0.05 && peerId != null) loud += peerId
        loud.forEach { speakHold[it] = 3 }
        for ((id, ticks) in speakHold.toMap()) {
            if (id in loud) continue
            if (ticks > 1) speakHold[id] = ticks - 1 else speakHold.remove(id)
        }
        val next = speakHold.keys.toSet()
        if (next != speaking) {
            speaking = next
            publish()
        }
    }

    // endregion

    // region Конец

    private fun hangupReason(): String {
        if (current.activeSinceMs == null) {
            if (role == CallRole.CALLER) return "CANCELED"
            if (role == CallRole.CALLEE && !answered) return "REJECTED"
        }
        return "HUNGUP"
    }

    private fun closedReason(): CallEndReason {
        if (current.activeSinceMs != null) return CallEndReason.RemoteHungUp
        return when (role) {
            CallRole.CALLER -> CallEndReason.NoAnswer
            CallRole.CALLEE -> if (answered) CallEndReason.RemoteHungUp else CallEndReason.Missed
            CallRole.JOINER -> CallEndReason.RemoteHungUp
        }
    }

    private fun end(reason: CallEndReason, closeSignaling: Boolean = true) {
        if (ended) return
        ended = true
        CallLog.info("Звонок закончен: $reason")
        ringTimer?.cancel()
        levelTimer?.cancel()
        listener?.cancel()
        closePeer()
        media.shutdown()
        if (closeSignaling) signaling?.close()
        current = current.copy(phase = CallPhase.Ended(reason))
    }

    // endregion

    companion object {
        /** Серверы ICE из `conversationParams` уведомления `connection`: они главнее тех, что в пуше. */
        fun iceServers(params: JsonElement?): List<CallIceServer>? {
            if (params !is JsonObject) return null
            val servers = mutableListOf<CallIceServer>()
            urls(params["stun"]["urls"])?.takeIf { it.isNotEmpty() }?.let { servers += CallIceServer(it) }
            val turn = params["turn"]
            urls(turn["urls"])?.takeIf { it.isNotEmpty() }?.let {
                servers += CallIceServer(it, turn["username"].str, turn["credential"].str)
            }
            return servers.ifEmpty { null }
        }

        private fun urls(value: JsonElement?): List<String>? = value.str?.let(::listOf) ?: value.arr?.mapNotNull { it.str }
    }
}
