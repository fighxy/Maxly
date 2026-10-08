package app.orbitle.calls

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
import dev.onvoid.webrtc.CreateSessionDescriptionObserver
import dev.onvoid.webrtc.PeerConnectionFactory
import dev.onvoid.webrtc.PeerConnectionObserver
import dev.onvoid.webrtc.RTCAnswerOptions
import dev.onvoid.webrtc.RTCBundlePolicy
import dev.onvoid.webrtc.RTCConfiguration
import dev.onvoid.webrtc.RTCDataChannel
import dev.onvoid.webrtc.RTCDataChannelBuffer
import dev.onvoid.webrtc.RTCDataChannelInit
import dev.onvoid.webrtc.RTCDataChannelObserver
import dev.onvoid.webrtc.RTCDataChannelState
import dev.onvoid.webrtc.RTCIceCandidate
import dev.onvoid.webrtc.RTCIceConnectionState
import dev.onvoid.webrtc.RTCIceGatheringState
import dev.onvoid.webrtc.RTCIceServer
import dev.onvoid.webrtc.RTCOfferOptions
import dev.onvoid.webrtc.RTCPeerConnection
import dev.onvoid.webrtc.RTCPeerConnectionState
import dev.onvoid.webrtc.RTCRtcpMuxPolicy
import dev.onvoid.webrtc.RTCRtpSender
import dev.onvoid.webrtc.RTCRtpTransceiver
import dev.onvoid.webrtc.RTCRtpTransceiverDirection
import dev.onvoid.webrtc.RTCRtpTransceiverInit
import dev.onvoid.webrtc.RTCSdpType
import dev.onvoid.webrtc.RTCSessionDescription
import dev.onvoid.webrtc.RTCSignalingState
import dev.onvoid.webrtc.RTCStatsType
import dev.onvoid.webrtc.SetSessionDescriptionObserver
import dev.onvoid.webrtc.media.MediaDevices
import dev.onvoid.webrtc.media.MediaStreamTrack
import dev.onvoid.webrtc.media.audio.AudioDeviceModule
import dev.onvoid.webrtc.media.audio.AudioLayer
import dev.onvoid.webrtc.media.audio.AudioOptions
import dev.onvoid.webrtc.media.audio.AudioTrack
import dev.onvoid.webrtc.media.video.CustomVideoSource
import dev.onvoid.webrtc.media.video.VideoCaptureCapability
import dev.onvoid.webrtc.media.video.VideoDesktopSource
import dev.onvoid.webrtc.media.video.VideoDeviceSource
import dev.onvoid.webrtc.media.video.VideoTrack
import dev.onvoid.webrtc.media.video.desktop.ScreenCapturer
import kotlinx.coroutines.suspendCancellableCoroutine
import java.nio.ByteBuffer
import java.util.UUID
import javax.swing.SwingUtilities
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.abs

/** Фабрика WebRTC одна на приложение: нативная библиотека грузится при первом звонке. */
internal object DesktopWebRtc {
    /** Без звуковой системы (сервер, удалённый стол) звук не идёт, но звонок не падает. */
    val factory: PeerConnectionFactory by lazy {
        try {
            PeerConnectionFactory()
        } catch (e: Throwable) {
            CallLog.warning("Звук для звонков недоступен: $e")
            PeerConnectionFactory(AudioDeviceModule(AudioLayer.kDummyAudio))
        }
    }

    fun shortId(): String = UUID.randomUUID().toString().take(8)
}

/** WebRTC зовёт наблюдателей со своих потоков; звонок живёт на потоке окна. */
private fun onMain(block: () -> Unit) = SwingUtilities.invokeLater(block)

/** Свои микрофон, камера и экран для одного звонка на ПК (webrtc-java). */
class DesktopCallMedia : CallMedia {
    private val factory = DesktopWebRtc.factory
    private val audioSource = factory.createAudioSource(
        AudioOptions().apply {
            echoCancellation = true
            autoGainControl = true
            noiseSuppression = true
            highpassFilter = true
        },
    )
    internal val audioTrack: AudioTrack = factory.createAudioTrack("audio-${DesktopWebRtc.shortId()}", audioSource)
    private var cameraSource: VideoDeviceSource? = null
    private var cameraTrack: VideoTrack? = null
    private var screenSource: VideoDesktopSource? = null
    private var screenTrack: VideoTrack? = null

    /** Пустой источник для слотов приёма видео: webrtc-java не создаёт приёмник без дорожки. */
    internal val silentVideo: VideoTrack by lazy {
        factory.createVideoTrack("recv-${DesktopWebRtc.shortId()}", CustomVideoSource())
    }

    override fun makePeer(iceServers: List<CallIceServer>): CallPeer? = try {
        DesktopCallPeer(factory, iceServers, this)
    } catch (e: Throwable) {
        CallLog.warning("WebRTC не создал соединение: $e")
        null
    }

    override fun trackId(video: LocalVideo): String? = videoTrack(video)?.id

    internal fun videoTrack(video: LocalVideo): VideoTrack? = when (video) {
        LocalVideo.CAMERA -> cameraTrack
        LocalVideo.SCREEN -> screenTrack
    }

    /** На ПК «фронтальная» — первая камера, «задняя» — вторая, если есть. */
    override suspend fun startCamera(position: CallCameraPosition) {
        val devices = runCatching { MediaDevices.getVideoCaptureDevices() }.getOrNull().orEmpty()
        val device = (if (position == CallCameraPosition.BACK) devices.getOrNull(1) else null) ?: devices.firstOrNull()
            ?: throw CallMediaException(CallMediaException.Kind.UNAVAILABLE)
        try {
            val source = cameraSource ?: VideoDeviceSource().also { cameraSource = it }
            source.stop()
            source.setVideoCaptureDevice(device)
            bestCapability(runCatching { MediaDevices.getVideoCaptureCapabilities(device) }.getOrNull().orEmpty())
                ?.let(source::setVideoCaptureCapability)
            source.start()
            val track = cameraTrack ?: factory.createVideoTrack("camera-${DesktopWebRtc.shortId()}", source).also {
                cameraTrack = it
                CallVideoRegistry.register(it, mirrored = true)
            }
            track.isEnabled = true
        } catch (e: Exception) {
            CallLog.warning("Камера не включилась: $e")
            throw CallMediaException(CallMediaException.Kind.UNAVAILABLE)
        }
    }

    override fun stopCamera() {
        runCatching { cameraSource?.stop() }
        cameraTrack?.isEnabled = false
    }

    /** Весь первый экран: 15 кадров в секунду, до Full HD. */
    override suspend fun startScreen() {
        try {
            val screen = ScreenCapturer().let { capturer ->
                try {
                    capturer.desktopSources.firstOrNull()
                } finally {
                    capturer.dispose()
                }
            } ?: throw CallMediaException(CallMediaException.Kind.UNAVAILABLE)
            val source = screenSource ?: VideoDesktopSource().also { screenSource = it }
            source.setSourceId(screen.id, false)
            source.setFrameRate(15)
            source.setMaxFrameSize(1920, 1080)
            source.start()
            val track = screenTrack ?: factory.createVideoTrack("screen-${DesktopWebRtc.shortId()}", source).also {
                screenTrack = it
                CallVideoRegistry.register(it, mirrored = false)
            }
            track.isEnabled = true
        } catch (e: CallMediaException) {
            throw e
        } catch (e: Exception) {
            CallLog.warning("Показ экрана не начался: $e")
            throw CallMediaException(CallMediaException.Kind.UNAVAILABLE)
        }
    }

    override fun stopScreen() {
        runCatching { screenSource?.stop() }
        screenTrack?.isEnabled = false
    }

    override fun setMicrophone(enabled: Boolean) {
        audioTrack.isEnabled = enabled
    }

    /** У ПК нет громкой связи: звук идёт в выбранное системой устройство. */
    override fun setSpeaker(on: Boolean) = Unit

    override fun shutdown() {
        runCatching { cameraSource?.stop() }
        runCatching { screenSource?.stop() }
        audioTrack.isEnabled = false
        CallVideoRegistry.clear()
        runCatching { cameraTrack?.dispose() }
        runCatching { screenTrack?.dispose() }
        runCatching { cameraSource?.dispose() }
        runCatching { screenSource?.dispose() }
        cameraTrack = null
        screenTrack = null
        cameraSource = null
        screenSource = null
    }

    /** Ближе всего к 1280×720 и не больше 30 кадров в секунду. */
    private fun bestCapability(list: List<VideoCaptureCapability>): VideoCaptureCapability? {
        val target = 1280 * 720
        return list.filter { it.frameRate in 1..30 }.ifEmpty { list }
            .minWithOrNull(compareBy<VideoCaptureCapability> { abs(it.width * it.height - target) }.thenByDescending { it.frameRate })
            ?.let { VideoCaptureCapability(it.width, it.height, it.frameRate.coerceAtMost(30)) }
    }

    internal companion object {
        const val STREAM_ID = "orbitle"
    }
}

/** Соединение WebRTC (`RTCPeerConnection` из webrtc-java) за [CallPeer]. */
internal class DesktopCallPeer(
    factory: PeerConnectionFactory,
    iceServers: List<CallIceServer>,
    private val media: DesktopCallMedia,
) : CallPeer {
    override var onEvent: ((PeerEvent) -> Unit)? = null
    private val senders = HashMap<LocalVideo, RTCRtpSender>()
    private val channels = mutableListOf<DesktopDataChannel>()

    @Volatile
    private var closed = false

    private val observer = object : PeerConnectionObserver {
        override fun onIceCandidate(candidate: RTCIceCandidate) =
            send(PeerEvent.Candidate(IceCandidate(candidate.sdp, candidate.sdpMid, candidate.sdpMLineIndex)))

        override fun onIceGatheringChange(state: RTCIceGatheringState) {
            if (state == RTCIceGatheringState.COMPLETE) send(PeerEvent.GatheringComplete)
        }

        override fun onIceConnectionChange(state: RTCIceConnectionState) {
            if (state == RTCIceConnectionState.FAILED) send(PeerEvent.IceFailed)
        }

        override fun onConnectionChange(state: RTCPeerConnectionState) = send(
            PeerEvent.State(
                when (state) {
                    RTCPeerConnectionState.NEW -> PeerState.NEW
                    RTCPeerConnectionState.CONNECTING -> PeerState.CONNECTING
                    RTCPeerConnectionState.CONNECTED -> PeerState.CONNECTED
                    RTCPeerConnectionState.DISCONNECTED -> PeerState.DISCONNECTED
                    RTCPeerConnectionState.FAILED -> PeerState.FAILED
                    RTCPeerConnectionState.CLOSED -> PeerState.CLOSED
                },
            ),
        )

        override fun onTrack(transceiver: RTCRtpTransceiver) {
            val track = transceiver.receiver?.track ?: return
            onMain { register(track)?.let { emit(PeerEvent.Track(it)) } }
        }
    }

    private val connection: RTCPeerConnection = factory.createPeerConnection(
        RTCConfiguration().apply {
            this.iceServers = iceServers.map { server ->
                RTCIceServer().apply {
                    urls = server.urls
                    username = server.username
                    password = server.credential
                }
            }
            bundlePolicy = RTCBundlePolicy.MAX_BUNDLE
            rtcpMuxPolicy = RTCRtcpMuxPolicy.REQUIRE
        },
        observer,
    ) ?: error("createPeerConnection вернул null")

    override val signalingState: PeerSignalingState
        get() = when (connection.signalingState) {
            RTCSignalingState.STABLE -> PeerSignalingState.STABLE
            RTCSignalingState.HAVE_LOCAL_OFFER -> PeerSignalingState.HAVE_LOCAL_OFFER
            RTCSignalingState.HAVE_REMOTE_OFFER -> PeerSignalingState.HAVE_REMOTE_OFFER
            RTCSignalingState.CLOSED -> PeerSignalingState.CLOSED
            else -> PeerSignalingState.OTHER
        }

    override val isGatheringComplete: Boolean get() = connection.iceGatheringState == RTCIceGatheringState.COMPLETE

    override val localDescription: SessionDescription? get() = connection.localDescription?.let(::session)

    override fun addMicrophone() {
        connection.addTrack(media.audioTrack, listOf(DesktopCallMedia.STREAM_ID))
    }

    override fun addVideoReceiver() {
        val init = RTCRtpTransceiverInit().apply { direction = RTCRtpTransceiverDirection.RECV_ONLY }
        connection.addTransceiver(media.silentVideo, init)
    }

    override fun sendVideo(video: LocalVideo): Boolean {
        val track = media.videoTrack(video) ?: return false
        senders[video]?.let {
            it.replaceTrack(track)
            return false
        }
        val sender = connection.addTrack(track, listOf(DesktopCallMedia.STREAM_ID)) ?: return false
        senders[video] = sender
        return true
    }

    override fun stopVideo(video: LocalVideo) {
        senders[video]?.replaceTrack(null)
    }

    override fun fillVideoSlot(mids: Set<String>, video: LocalVideo): Boolean {
        val track = media.videoTrack(video) ?: return false
        val transceiver = connection.transceivers.firstOrNull {
            it.mid in mids && it.receiver?.track?.kind == MediaStreamTrack.VIDEO_TRACK_KIND
        } ?: return false
        transceiver.sender.replaceTrack(track)
        transceiver.direction = RTCRtpTransceiverDirection.SEND_ONLY
        senders[video] = transceiver.sender
        return true
    }

    override suspend fun makeOffer(iceRestart: Boolean): SessionDescription = suspendCancellableCoroutine { continuation ->
        connection.createOffer(RTCOfferOptions().apply { this.iceRestart = iceRestart }, describe(continuation))
    }

    override suspend fun makeAnswer(): SessionDescription = suspendCancellableCoroutine { continuation ->
        connection.createAnswer(RTCAnswerOptions(), describe(continuation))
    }

    override suspend fun setLocal(description: SessionDescription) = suspendCancellableCoroutine { continuation ->
        connection.setLocalDescription(rtc(description), applied(continuation))
    }

    override suspend fun setRemote(description: SessionDescription) = suspendCancellableCoroutine { continuation ->
        connection.setRemoteDescription(rtc(description), applied(continuation))
    }

    override suspend fun add(candidate: IceCandidate) {
        runCatching { connection.addIceCandidate(RTCIceCandidate(candidate.sdpMid ?: "0", candidate.sdpMLineIndex, candidate.sdp)) }
    }

    /** Дорожки приёмников, которые по согласованному SDP действительно принимают. */
    override fun remoteTracks(): List<RemoteTrack> = connection.transceivers.mapNotNull { transceiver ->
        val direction = runCatching { transceiver.currentDirection }.getOrNull()
        if (direction != RTCRtpTransceiverDirection.SEND_RECV && direction != RTCRtpTransceiverDirection.RECV_ONLY) return@mapNotNull null
        transceiver.receiver?.track?.let(::register)
    }

    override fun openChannel(label: String): CallDataChannel? {
        val channel = runCatching { connection.createDataChannel(label, RTCDataChannelInit().apply { ordered = true }) }.getOrNull() ?: return null
        return DesktopDataChannel(channel).also { channels += it }
    }

    override suspend fun audioLevels(): Pair<Double, Double>? {
        if (closed) return null
        return suspendCancellableCoroutine { continuation ->
            connection.getStats { report ->
                var local = 0.0
                var remote = 0.0
                for (stat in report.stats.values) {
                    val attributes = stat.attributes
                    val audio = attributes["kind"] == "audio" || attributes["mediaType"] == "audio"
                    val level = (attributes["audioLevel"] as? Number)?.toDouble() ?: continue
                    if (!audio) continue
                    when (stat.type) {
                        RTCStatsType.MEDIA_SOURCE -> local = maxOf(local, level)
                        RTCStatsType.INBOUND_RTP -> remote = maxOf(remote, level)
                        else -> Unit
                    }
                }
                continuation.resume(local to remote)
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
        runCatching { connection.close() }
    }

    private fun send(event: PeerEvent) = onMain { emit(event) }

    private fun emit(event: PeerEvent) {
        if (!closed) onEvent?.invoke(event)
    }

    private fun register(track: MediaStreamTrack): RemoteTrack? {
        val kind = if (track.kind == MediaStreamTrack.VIDEO_TRACK_KIND) MediaKind.VIDEO else MediaKind.AUDIO
        if (track is VideoTrack) CallVideoRegistry.register(track, mirrored = false)
        return RemoteTrack(track.id, kind)
    }

    private fun describe(continuation: kotlinx.coroutines.CancellableContinuation<SessionDescription>) =
        object : CreateSessionDescriptionObserver {
            override fun onSuccess(description: RTCSessionDescription) {
                if (continuation.isActive) continuation.resume(session(description))
            }

            override fun onFailure(error: String) {
                if (continuation.isActive) continuation.resumeWithException(IllegalStateException(error))
            }
        }

    private fun applied(continuation: kotlinx.coroutines.CancellableContinuation<Unit>) = object : SetSessionDescriptionObserver {
        override fun onSuccess() {
            if (continuation.isActive) continuation.resume(Unit)
        }

        override fun onFailure(error: String) {
            if (continuation.isActive) continuation.resumeWithException(IllegalStateException(error))
        }
    }

    private fun session(value: RTCSessionDescription) = SessionDescription(
        when (value.sdpType) {
            RTCSdpType.OFFER -> SdpType.OFFER
            RTCSdpType.ANSWER -> SdpType.ANSWER
            RTCSdpType.PR_ANSWER -> SdpType.PRANSWER
            RTCSdpType.ROLLBACK -> SdpType.ROLLBACK
            else -> SdpType.OFFER
        },
        value.sdp,
    )

    private fun rtc(description: SessionDescription) = RTCSessionDescription(
        when (description.type) {
            SdpType.OFFER -> RTCSdpType.OFFER
            SdpType.ANSWER -> RTCSdpType.ANSWER
            SdpType.PRANSWER -> RTCSdpType.PR_ANSWER
            SdpType.ROLLBACK -> RTCSdpType.ROLLBACK
        },
        description.sdp,
    )
}

/** Канал данных WebRTC за [CallDataChannel]. */
internal class DesktopDataChannel(private val channel: RTCDataChannel) : CallDataChannel {
    override var onOpen: (() -> Unit)? = null
    override var onMessage: ((ByteArray) -> Unit)? = null

    init {
        channel.registerObserver(object : RTCDataChannelObserver {
            override fun onBufferedAmountChange(sentDataSize: Long) = Unit

            override fun onStateChange() {
                onMain { if (isOpen) onOpen?.invoke() }
            }

            override fun onMessage(buffer: RTCDataChannelBuffer) {
                if (!buffer.binary) return
                val data = ByteArray(buffer.data.remaining())
                buffer.data.get(data)
                onMain { onMessage?.invoke(data) }
            }
        })
    }

    override val label: String get() = channel.label
    override val isOpen: Boolean get() = runCatching { channel.state == RTCDataChannelState.OPEN }.getOrDefault(false)

    override fun send(data: ByteArray): Boolean {
        if (!isOpen) return false
        return runCatching { channel.send(RTCDataChannelBuffer(ByteBuffer.wrap(data), true)) }.isSuccess
    }

    override fun close() {
        runCatching { channel.unregisterObserver() }
        runCatching { channel.close() }
    }
}
