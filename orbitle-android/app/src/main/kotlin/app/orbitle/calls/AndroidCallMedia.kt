package app.orbitle.calls

import android.Manifest
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import app.orbitle.data.calls.CallDataChannel
import app.orbitle.data.calls.CallLog
import app.orbitle.data.calls.CallMedia
import app.orbitle.data.calls.CallMediaException
import app.orbitle.data.calls.CallPeer
import app.orbitle.data.calls.IceCandidate
import app.orbitle.data.calls.LocalVideo
import app.orbitle.data.calls.MediaKind
import app.orbitle.data.calls.PeerEvent
import app.orbitle.data.calls.PeerSignalingState
import app.orbitle.data.calls.PeerState
import app.orbitle.data.calls.RemoteTrack
import app.orbitle.data.calls.SdpType
import app.orbitle.data.calls.SessionDescription
import app.orbitle.domain.CallCameraPosition
import app.orbitle.domain.CallIceServer
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.suspendCancellableCoroutine
import org.webrtc.AudioTrack
import org.webrtc.Camera2Enumerator
import org.webrtc.CameraVideoCapturer
import org.webrtc.DataChannel
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.EglBase
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.MediaStreamTrack
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.RtpSender
import org.webrtc.RtpTransceiver
import org.webrtc.ScreenCapturerAndroid
import org.webrtc.SdpObserver
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoSource
import org.webrtc.VideoTrack
import org.webrtc.audio.JavaAudioDeviceModule
import java.nio.ByteBuffer
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import org.webrtc.IceCandidate as RtcIceCandidate
import org.webrtc.SessionDescription as RtcSessionDescription

/** WebRTC зовёт наблюдателей со своих потоков; звонок живёт на главном. */
private val main = Handler(Looper.getMainLooper())

private fun onMain(block: () -> Unit) {
    main.post(block)
}

/** Фабрика WebRTC и контекст EGL — одни на приложение. */
object AndroidWebRtc {
    private var context: Context? = null
    val egl: EglBase by lazy { EglBase.create() }

    val factory: PeerConnectionFactory by lazy {
        val app = requireNotNull(context) { "AndroidWebRtc.init не вызван" }
        PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(app).createInitializationOptions())
        val audio = JavaAudioDeviceModule.builder(app)
            .setUseHardwareAcousticEchoCanceler(true)
            .setUseHardwareNoiseSuppressor(true)
            .createAudioDeviceModule()
        PeerConnectionFactory.builder()
            .setAudioDeviceModule(audio)
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(egl.eglBaseContext, true, true))
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(egl.eglBaseContext))
            .createPeerConnectionFactory()
    }

    fun init(context: Context) {
        this.context = context.applicationContext
    }

    fun shortId(): String = UUID.randomUUID().toString().take(8)
}

/** Видеодорожки идущего звонка по id: экран звонка рисует их по id из `CallState`. */
object CallVideoRegistry {
    data class Entry(val track: VideoTrack, val mirrored: Boolean)

    private val _tracks = MutableStateFlow<Map<String, Entry>>(emptyMap())
    val tracks: StateFlow<Map<String, Entry>> = _tracks.asStateFlow()

    fun register(track: VideoTrack, mirrored: Boolean) {
        val id = runCatching { track.id() }.getOrNull() ?: return
        _tracks.update { it + (id to Entry(track, mirrored)) }
    }

    fun setMirrored(id: String, mirrored: Boolean) = _tracks.update { map ->
        map[id]?.let { map + (id to it.copy(mirrored = mirrored)) } ?: map
    }

    fun clear() {
        _tracks.value = emptyMap()
    }
}

/** Свои микрофон, камера и экран для одного звонка на Android. */
class AndroidCallMedia(private val context: Context) : CallMedia {
    private val factory = AndroidWebRtc.factory
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val audioSource = factory.createAudioSource(MediaConstraints())
    internal val audioTrack: AudioTrack = factory.createAudioTrack("audio-${AndroidWebRtc.shortId()}", audioSource)
    private val cameras = Camera2Enumerator(context)
    private var cameraCapturer: CameraVideoCapturer? = null
    private var cameraHelper: SurfaceTextureHelper? = null
    private var cameraSource: VideoSource? = null
    private var cameraTrack: VideoTrack? = null
    private var cameraName: String? = null
    private var screenCapturer: ScreenCapturerAndroid? = null
    private var screenHelper: SurfaceTextureHelper? = null
    private var screenSource: VideoSource? = null
    private var screenTrack: VideoTrack? = null
    private val previousMode = audio.mode

    init {
        // Разговорный режим: эхоподавление, звук в динамик у уха.
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
    }

    override fun makePeer(iceServers: List<CallIceServer>): CallPeer? = try {
        AndroidCallPeer(factory, iceServers, this)
    } catch (e: Throwable) {
        CallLog.warning("WebRTC не создал соединение: $e")
        null
    }

    override fun trackId(video: LocalVideo): String? = videoTrack(video)?.id()

    internal fun videoTrack(video: LocalVideo): VideoTrack? = when (video) {
        LocalVideo.CAMERA -> cameraTrack
        LocalVideo.SCREEN -> screenTrack
    }

    override suspend fun startCamera(position: CallCameraPosition) {
        if (!CallPermissions.ensure(Manifest.permission.CAMERA)) throw CallMediaException(CallMediaException.Kind.DENIED)
        val names = cameras.deviceNames.toList()
        val front = position == CallCameraPosition.FRONT
        val name = names.firstOrNull { cameras.isFrontFacing(it) == front } ?: names.firstOrNull()
            ?: throw CallMediaException(CallMediaException.Kind.UNAVAILABLE)
        try {
            val capturer = cameraCapturer
            if (capturer != null && cameraName != null) {
                if (name != cameraName) switchTo(capturer, name)
                if (cameraTrack?.enabled() != true) capturer.startCapture(1280, 720, 30)
            } else {
                val source = factory.createVideoSource(false)
                val helper = SurfaceTextureHelper.create("camera", AndroidWebRtc.egl.eglBaseContext)
                val created = cameras.createCapturer(name, null) ?: throw CallMediaException(CallMediaException.Kind.UNAVAILABLE)
                created.initialize(helper, context, source.capturerObserver)
                created.startCapture(1280, 720, 30)
                cameraCapturer = created
                cameraHelper = helper
                cameraSource = source
                cameraTrack = factory.createVideoTrack("camera-${AndroidWebRtc.shortId()}", source)
            }
            cameraName = name
            val track = cameraTrack ?: throw CallMediaException(CallMediaException.Kind.UNAVAILABLE)
            track.setEnabled(true)
            CallVideoRegistry.register(track, mirrored = cameras.isFrontFacing(name))
        } catch (e: CallMediaException) {
            throw e
        } catch (e: Exception) {
            CallLog.warning("Камера не включилась: $e")
            throw CallMediaException(CallMediaException.Kind.UNAVAILABLE)
        }
    }

    private suspend fun switchTo(capturer: CameraVideoCapturer, name: String) = suspendCancellableCoroutine { continuation ->
        capturer.switchCamera(
            object : CameraVideoCapturer.CameraSwitchHandler {
                override fun onCameraSwitchDone(isFrontCamera: Boolean) {
                    if (continuation.isActive) continuation.resume(Unit)
                }

                override fun onCameraSwitchError(error: String?) {
                    if (continuation.isActive) continuation.resumeWithException(IllegalStateException(error))
                }
            },
            name,
        )
    }

    override fun stopCamera() {
        runCatching { cameraCapturer?.stopCapture() }
        cameraTrack?.setEnabled(false)
    }

    /** Весь экран телефона через MediaProjection: 15 кадров в секунду, до 1280×720. */
    override suspend fun startScreen() {
        val permission = CallPermissions.screenCapture() ?: throw CallMediaException(CallMediaException.Kind.DENIED)
        try {
            // С Android 14 показ экрана разрешён только при службе типа mediaProjection.
            CallForegroundService.allowScreenCapture(context)
            screenCapturer?.let { runCatching { it.stopCapture() } }
            val source = screenSource ?: factory.createVideoSource(true).also { screenSource = it }
            val helper = screenHelper ?: SurfaceTextureHelper.create("screen", AndroidWebRtc.egl.eglBaseContext).also { screenHelper = it }
            val capturer = ScreenCapturerAndroid(permission, object : android.media.projection.MediaProjection.Callback() {
                override fun onStop() = Unit
            })
            capturer.initialize(helper, context, source.capturerObserver)
            capturer.startCapture(1280, 720, 15)
            screenCapturer = capturer
            val track = screenTrack ?: factory.createVideoTrack("screen-${AndroidWebRtc.shortId()}", source).also { screenTrack = it }
            track.setEnabled(true)
            CallVideoRegistry.register(track, mirrored = false)
        } catch (e: Exception) {
            CallLog.warning("Показ экрана не начался: $e")
            throw CallMediaException(CallMediaException.Kind.UNAVAILABLE)
        }
    }

    override fun stopScreen() {
        runCatching { screenCapturer?.stopCapture() }
        runCatching { screenCapturer?.dispose() }
        screenCapturer = null
        screenTrack?.setEnabled(false)
    }

    override fun setMicrophone(enabled: Boolean) {
        audioTrack.setEnabled(enabled)
    }

    @Suppress("DEPRECATION")
    override fun setSpeaker(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (on) {
                audio.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    ?.let(audio::setCommunicationDevice)
            } else {
                audio.clearCommunicationDevice()
            }
        } else {
            audio.isSpeakerphoneOn = on
        }
    }

    override fun shutdown() {
        runCatching { cameraCapturer?.stopCapture() }
        runCatching { screenCapturer?.stopCapture() }
        audioTrack.setEnabled(false)
        CallVideoRegistry.clear()
        runCatching { cameraCapturer?.dispose() }
        runCatching { screenCapturer?.dispose() }
        runCatching { cameraHelper?.dispose() }
        runCatching { screenHelper?.dispose() }
        runCatching { cameraTrack?.dispose() }
        runCatching { screenTrack?.dispose() }
        runCatching { cameraSource?.dispose() }
        runCatching { screenSource?.dispose() }
        runCatching { audioTrack.dispose() }
        runCatching { audioSource.dispose() }
        cameraCapturer = null
        screenCapturer = null
        cameraTrack = null
        screenTrack = null
        setSpeaker(false)
        audio.mode = previousMode
    }

    internal companion object {
        const val STREAM_ID = "orbitle"
    }
}

/** Соединение WebRTC (`org.webrtc.PeerConnection`) за [CallPeer]. */
internal class AndroidCallPeer(
    factory: PeerConnectionFactory,
    iceServers: List<CallIceServer>,
    private val media: AndroidCallMedia,
) : CallPeer {
    override var onEvent: ((PeerEvent) -> Unit)? = null
    private val senders = HashMap<LocalVideo, RtpSender>()
    private val channels = mutableListOf<AndroidDataChannel>()

    @Volatile
    private var closed = false

    private val observer = object : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState?) = Unit
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {
            if (state == PeerConnection.IceConnectionState.FAILED) send(PeerEvent.IceFailed)
        }

        override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) {
            if (state == PeerConnection.IceGatheringState.COMPLETE) send(PeerEvent.GatheringComplete)
        }

        override fun onIceCandidate(candidate: RtcIceCandidate) =
            send(PeerEvent.Candidate(IceCandidate(candidate.sdp, candidate.sdpMid, candidate.sdpMLineIndex)))

        override fun onIceCandidatesRemoved(candidates: Array<out RtcIceCandidate>?) = Unit
        override fun onAddStream(stream: MediaStream?) = Unit
        override fun onRemoveStream(stream: MediaStream?) = Unit
        override fun onDataChannel(channel: DataChannel?) = Unit
        override fun onRenegotiationNeeded() = Unit
        override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) = Unit

        override fun onConnectionChange(state: PeerConnection.PeerConnectionState) = send(
            PeerEvent.State(
                when (state) {
                    PeerConnection.PeerConnectionState.NEW -> PeerState.NEW
                    PeerConnection.PeerConnectionState.CONNECTING -> PeerState.CONNECTING
                    PeerConnection.PeerConnectionState.CONNECTED -> PeerState.CONNECTED
                    PeerConnection.PeerConnectionState.DISCONNECTED -> PeerState.DISCONNECTED
                    PeerConnection.PeerConnectionState.FAILED -> PeerState.FAILED
                    PeerConnection.PeerConnectionState.CLOSED -> PeerState.CLOSED
                },
            ),
        )

        override fun onTrack(transceiver: RtpTransceiver) {
            val track = transceiver.receiver?.track() ?: return
            onMain { register(track)?.let { emit(PeerEvent.Track(it)) } }
        }
    }

    private val connection: PeerConnection = factory.createPeerConnection(
        PeerConnection.RTCConfiguration(
            iceServers.map { server ->
                PeerConnection.IceServer.builder(server.urls)
                    .setUsername(server.username.orEmpty())
                    .setPassword(server.credential.orEmpty())
                    .createIceServer()
            },
        ).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE
            tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.ENABLED
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
        },
        observer,
    ) ?: error("createPeerConnection вернул null")

    override val signalingState: PeerSignalingState
        get() = when (connection.signalingState()) {
            PeerConnection.SignalingState.STABLE -> PeerSignalingState.STABLE
            PeerConnection.SignalingState.HAVE_LOCAL_OFFER -> PeerSignalingState.HAVE_LOCAL_OFFER
            PeerConnection.SignalingState.HAVE_REMOTE_OFFER -> PeerSignalingState.HAVE_REMOTE_OFFER
            PeerConnection.SignalingState.CLOSED -> PeerSignalingState.CLOSED
            else -> PeerSignalingState.OTHER
        }

    override val isGatheringComplete: Boolean get() = connection.iceGatheringState() == PeerConnection.IceGatheringState.COMPLETE

    override val localDescription: SessionDescription? get() = connection.localDescription?.let(::session)

    override fun addMicrophone() {
        connection.addTrack(media.audioTrack, listOf(AndroidCallMedia.STREAM_ID))
    }

    override fun addVideoReceiver() {
        connection.addTransceiver(
            MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO,
            RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY),
        )
    }

    override fun sendVideo(video: LocalVideo): Boolean {
        val track = media.videoTrack(video) ?: return false
        senders[video]?.let {
            it.setTrack(track, false)
            return false
        }
        val sender = connection.addTrack(track, listOf(AndroidCallMedia.STREAM_ID)) ?: return false
        senders[video] = sender
        return true
    }

    override fun stopVideo(video: LocalVideo) {
        senders[video]?.setTrack(null, false)
    }

    override fun fillVideoSlot(mids: Set<String>, video: LocalVideo): Boolean {
        val track = media.videoTrack(video) ?: return false
        val transceiver = connection.transceivers.firstOrNull {
            it.mediaType == MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO && it.mid in mids
        } ?: return false
        transceiver.sender.setTrack(track, false)
        transceiver.setDirection(RtpTransceiver.RtpTransceiverDirection.SEND_ONLY)
        senders[video] = transceiver.sender
        return true
    }

    override suspend fun makeOffer(iceRestart: Boolean): SessionDescription = suspendCancellableCoroutine { continuation ->
        val constraints = MediaConstraints().apply {
            if (iceRestart) mandatory.add(MediaConstraints.KeyValuePair("IceRestart", "true"))
        }
        connection.createOffer(created(continuation), constraints)
    }

    override suspend fun makeAnswer(): SessionDescription = suspendCancellableCoroutine { continuation ->
        connection.createAnswer(created(continuation), MediaConstraints())
    }

    override suspend fun setLocal(description: SessionDescription) = suspendCancellableCoroutine { continuation ->
        connection.setLocalDescription(applied(continuation), rtc(description))
    }

    override suspend fun setRemote(description: SessionDescription) = suspendCancellableCoroutine { continuation ->
        connection.setRemoteDescription(applied(continuation), rtc(description))
    }

    override suspend fun add(candidate: IceCandidate) {
        runCatching { connection.addIceCandidate(RtcIceCandidate(candidate.sdpMid ?: "0", candidate.sdpMLineIndex, candidate.sdp)) }
    }

    /** Дорожки приёмников, которые по согласованному SDP действительно принимают. */
    override fun remoteTracks(): List<RemoteTrack> = connection.transceivers.mapNotNull { transceiver ->
        val direction = runCatching { transceiver.currentDirection }.getOrNull()
        if (direction != RtpTransceiver.RtpTransceiverDirection.SEND_RECV && direction != RtpTransceiver.RtpTransceiverDirection.RECV_ONLY) {
            return@mapNotNull null
        }
        transceiver.receiver?.track()?.let(::register)
    }

    override fun openChannel(label: String): CallDataChannel? {
        val channel = runCatching { connection.createDataChannel(label, DataChannel.Init().apply { ordered = true }) }.getOrNull() ?: return null
        return AndroidDataChannel(channel).also { channels += it }
    }

    override suspend fun audioLevels(): Pair<Double, Double>? {
        if (closed) return null
        return suspendCancellableCoroutine { continuation ->
            connection.getStats { report ->
                var local = 0.0
                var remote = 0.0
                for (stat in report.statsMap.values) {
                    val members = stat.members
                    val audio = members["kind"] == "audio" || members["mediaType"] == "audio"
                    val level = (members["audioLevel"] as? Number)?.toDouble() ?: continue
                    if (!audio) continue
                    when (stat.type) {
                        "media-source" -> local = maxOf(local, level)
                        "inbound-rtp" -> remote = maxOf(remote, level)
                    }
                }
                if (continuation.isActive) continuation.resume(local to remote)
            }
        }
    }

    override fun close() {
        if (closed) return
        closed = true
        onEvent = null
        channels.forEach { it.close() }
        channels.clear()
        senders.clear()
        runCatching { connection.dispose() }
    }

    private fun send(event: PeerEvent) = onMain { emit(event) }

    private fun emit(event: PeerEvent) {
        if (!closed) onEvent?.invoke(event)
    }

    private fun register(track: MediaStreamTrack): RemoteTrack? {
        val kind = if (track.kind() == MediaStreamTrack.VIDEO_TRACK_KIND) MediaKind.VIDEO else MediaKind.AUDIO
        if (track is VideoTrack) CallVideoRegistry.register(track, mirrored = false)
        return RemoteTrack(track.id(), kind)
    }

    private fun created(continuation: CancellableContinuation<SessionDescription>) = object : SdpObserver {
        override fun onCreateSuccess(description: RtcSessionDescription) {
            if (continuation.isActive) continuation.resume(session(description))
        }

        override fun onSetSuccess() = Unit

        override fun onCreateFailure(error: String?) {
            if (continuation.isActive) continuation.resumeWithException(IllegalStateException(error))
        }

        override fun onSetFailure(error: String?) = Unit
    }

    private fun applied(continuation: CancellableContinuation<Unit>) = object : SdpObserver {
        override fun onCreateSuccess(description: RtcSessionDescription?) = Unit

        override fun onSetSuccess() {
            if (continuation.isActive) continuation.resume(Unit)
        }

        override fun onCreateFailure(error: String?) = Unit

        override fun onSetFailure(error: String?) {
            if (continuation.isActive) continuation.resumeWithException(IllegalStateException(error))
        }
    }

    private fun session(value: RtcSessionDescription) = SessionDescription(
        SdpType.of(value.type.canonicalForm()) ?: SdpType.OFFER,
        value.description,
    )

    private fun rtc(description: SessionDescription) =
        RtcSessionDescription(RtcSessionDescription.Type.fromCanonicalForm(description.type.raw), description.sdp)
}

/** Канал данных WebRTC за [CallDataChannel]. */
internal class AndroidDataChannel(private val channel: DataChannel) : CallDataChannel {
    override var onOpen: (() -> Unit)? = null
    override var onMessage: ((ByteArray) -> Unit)? = null
    override val label: String = channel.label()

    init {
        channel.registerObserver(object : DataChannel.Observer {
            override fun onBufferedAmountChange(previousAmount: Long) = Unit

            override fun onStateChange() {
                onMain { if (isOpen) onOpen?.invoke() }
            }

            override fun onMessage(buffer: DataChannel.Buffer) {
                if (!buffer.binary) return
                val data = ByteArray(buffer.data.remaining())
                buffer.data.get(data)
                onMain { onMessage?.invoke(data) }
            }
        })
    }

    override val isOpen: Boolean get() = runCatching { channel.state() == DataChannel.State.OPEN }.getOrDefault(false)

    override fun send(data: ByteArray): Boolean {
        if (!isOpen) return false
        return runCatching { channel.send(DataChannel.Buffer(ByteBuffer.wrap(data), true)) }.getOrDefault(false)
    }

    override fun close() {
        runCatching { channel.unregisterObserver() }
        runCatching { channel.close() }
        runCatching { channel.dispose() }
    }
}
