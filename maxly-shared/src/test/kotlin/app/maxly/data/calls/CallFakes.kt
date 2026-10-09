package app.maxly.data.calls

import app.maxly.domain.CallCameraPosition
import app.maxly.domain.CallIceServer
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Сервер ws2 в памяти: отвечает на каждую команду по её номеру и шлёт уведомления по команде теста. */
class FakeWs2Server : Ws2Socket {
    private val incoming = Channel<String>(Channel.UNLIMITED)
    private val errors = HashMap<String, String>()
    val frames = mutableListOf<JsonObject>()
    val texts = mutableListOf<String>()
    var isClosed = false
        private set

    /** Команды, на которые сервер отвечает ошибкой. */
    fun fail(command: String, error: String) {
        errors[command] = error
    }

    fun commands(name: String): List<JsonObject> = frames.filter { it["command"].str == name }

    val commandNames: List<String> get() = frames.mapNotNull { it["command"].str }

    override suspend fun send(text: String) {
        if (isClosed) throw Ws2Exception.Closed()
        texts += text
        val frame = runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonObject ?: return
        frames += frame
        val command = frame["command"].str ?: return
        val number = frame["sequence"].long ?: return
        val error = errors[command]
        deliver(
            if (error != null) json("type" to "error", "sequence" to number, "error" to error)
            else json("type" to "response", "sequence" to number, "response" to command),
        )
    }

    override suspend fun receive(): String = try {
        incoming.receive()
    } catch (_: Exception) {
        throw Ws2Exception.Closed()
    }

    override fun close() {
        isClosed = true
        incoming.close()
    }

    fun deliver(value: JsonElement) = deliver(value.toString())

    fun deliver(text: String) {
        if (!isClosed) incoming.trySend(text)
    }

    /** Уведомление сервера. */
    fun notify(name: String, body: Map<String, Any?> = emptyMap()) {
        deliver(JsonObject(element(body).obj!! + mapOf("notification" to JsonPrimitive(name), "type" to JsonPrimitive("notification"))))
    }
}

/** Подключения к фейковым серверам по порядку: первое — первому серверу и т. д. */
class FakeConnector(servers: List<FakeWs2Server>) {
    private val servers = servers.toMutableList()
    val urls = mutableListOf<String>()
    val connections get() = urls.size

    val connector: Ws2Connector = { url ->
        urls += url
        if (this.servers.isEmpty()) throw Ws2Exception.Closed()
        this.servers.removeAt(0)
    }
}

class FakeCallPeer(val iceServers: List<CallIceServer>) : CallPeer {
    override var onEvent: ((PeerEvent) -> Unit)? = null
    override var signalingState = PeerSignalingState.STABLE
    override var isGatheringComplete = false
    override var localDescription: SessionDescription? = null

    var microphone = false
    var receivers = 0
    val sending = mutableListOf<LocalVideo>()
    val stopped = mutableListOf<LocalVideo>()
    val slots = mutableListOf<Pair<Set<String>, LocalVideo>>()
    /** Что сейчас в слоте SFU: последнее `fillVideoSlot`, пока его не сняли `stopVideo`. */
    var slotVideo: LocalVideo? = null
    val offers = mutableListOf<Boolean>()
    val locals = mutableListOf<SessionDescription>()
    val remotes = mutableListOf<SessionDescription>()
    val candidates = mutableListOf<IceCandidate>()
    val tracks = mutableListOf<RemoteTrack>()
    val channels = mutableListOf<FakeCallChannel>()
    var levels: Pair<Double, Double>? = null
    var closed = false
    var videoError: Exception? = null
    var offerSdp = "v=0\r\na=msid:stream cam-track\r\na=ssrc:11 msid:stream cam-track\r\n"
    var answerSdp = "v=0\r\na=msid:stream cam-track\r\n"

    override fun addMicrophone() {
        microphone = true
    }

    override fun addVideoReceiver() {
        receivers += 1
    }

    override fun sendVideo(video: LocalVideo): Boolean {
        videoError?.let { throw it }
        val added = video !in sending
        sending += video
        return added
    }

    override fun stopVideo(video: LocalVideo) {
        videoError?.let { throw it }
        stopped += video
        if (slotVideo == video) slotVideo = null
    }

    override fun fillVideoSlot(mids: Set<String>, video: LocalVideo): Boolean {
        slots += mids to video
        if (mids.isEmpty()) return false
        slotVideo = video
        return true
    }

    override suspend fun makeOffer(iceRestart: Boolean): SessionDescription {
        offers += iceRestart
        return SessionDescription(SdpType.OFFER, offerSdp)
    }

    override suspend fun makeAnswer() = SessionDescription(SdpType.ANSWER, answerSdp)

    override suspend fun setLocal(description: SessionDescription) {
        locals += description
        signalingState = if (description.type == SdpType.OFFER) PeerSignalingState.HAVE_LOCAL_OFFER else PeerSignalingState.STABLE
        if (description.type != SdpType.ROLLBACK) localDescription = description
    }

    override suspend fun setRemote(description: SessionDescription) {
        remotes += description
        signalingState = if (description.type == SdpType.OFFER) PeerSignalingState.HAVE_REMOTE_OFFER else PeerSignalingState.STABLE
    }

    override suspend fun add(candidate: IceCandidate) {
        candidates += candidate
    }

    override fun remoteTracks(): List<RemoteTrack> = tracks.toList()

    override fun openChannel(label: String): CallDataChannel = FakeCallChannel(label).also { channels += it }

    override suspend fun audioLevels() = levels

    override fun close() {
        closed = true
    }

    fun emit(event: PeerEvent) = onEvent?.invoke(event)
}

class FakeCallChannel(override val label: String) : CallDataChannel {
    override var isOpen = false
    override var onOpen: (() -> Unit)? = null
    override var onMessage: ((ByteArray) -> Unit)? = null
    val sent = mutableListOf<ByteArray>()
    var closed = false

    override fun send(data: ByteArray): Boolean {
        if (!isOpen) return false
        sent += data
        return true
    }

    override fun close() {
        closed = true
    }

    fun open() {
        isOpen = true
        onOpen?.invoke()
    }
}

class FakeCallMedia : CallMedia {
    val peers = mutableListOf<FakeCallPeer>()
    var camera: CallCameraPosition? = null
    val cameraStarts = mutableListOf<CallCameraPosition>()
    var screen = false
    var micOn = true
    var speakerOn = false
    var shutDown = false
    var cameraError: CallMediaException.Kind? = null
    /** Новые соединения сразу с собранными кандидатами: SFU не ждёт `timing.gathering`. */
    var gatheringComplete = false

    val peer: FakeCallPeer? get() = peers.lastOrNull()

    override fun makePeer(iceServers: List<CallIceServer>): CallPeer = FakeCallPeer(iceServers).also {
        it.isGatheringComplete = gatheringComplete
        peers += it
    }

    override fun trackId(video: LocalVideo): String? = when (video) {
        LocalVideo.CAMERA -> if (camera == null) null else "cam-track"
        LocalVideo.SCREEN -> if (screen) "screen-track" else null
    }

    override suspend fun startCamera(position: CallCameraPosition) {
        cameraError?.let { throw CallMediaException(it) }
        camera = position
        cameraStarts += position
    }

    override fun stopCamera() {
        camera = null
    }

    override suspend fun startScreen() {
        screen = true
    }

    override fun stopScreen() {
        screen = false
    }

    override fun setMicrophone(enabled: Boolean) {
        micOn = enabled
    }

    override fun setSpeaker(on: Boolean) {
        speakerOn = on
    }

    override fun shutdown() {
        shutDown = true
    }
}
