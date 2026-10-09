package app.maxly.data.calls

import app.maxly.domain.CallCameraPosition
import app.maxly.domain.CallIceServer

/** Тип описания сессии WebRTC. */
enum class SdpType(val raw: String) {
    OFFER("offer"),
    ANSWER("answer"),
    PRANSWER("pranswer"),
    ROLLBACK("rollback"),
    ;

    companion object {
        fun of(raw: String?): SdpType? = entries.firstOrNull { it.raw == raw }
    }
}

/** Описание сессии (SDP) с типом. */
data class SessionDescription(val type: SdpType, val sdp: String)

/** Кандидат ICE. */
data class IceCandidate(val sdp: String, val sdpMid: String?, val sdpMLineIndex: Int)

/** Состояние согласования SDP. */
enum class PeerSignalingState { STABLE, HAVE_LOCAL_OFFER, HAVE_REMOTE_OFFER, OTHER, CLOSED }

/** Состояние соединения WebRTC. */
enum class PeerState { NEW, CONNECTING, CONNECTED, DISCONNECTED, FAILED, CLOSED }

enum class MediaKind { AUDIO, VIDEO }

/** Дорожка собеседника: id и вид. */
data class RemoteTrack(val id: String, val kind: MediaKind)

/** Своё видео: камера или экран. */
enum class LocalVideo { CAMERA, SCREEN }

/** Событие соединения WebRTC. Приходит на главном потоке. */
sealed interface PeerEvent {
    data class Candidate(val candidate: IceCandidate) : PeerEvent

    data object GatheringComplete : PeerEvent

    data class State(val state: PeerState) : PeerEvent

    /** ICE не нашёл путь. В SFU после этого просят у сервера новый (`request-realloc`). */
    data object IceFailed : PeerEvent

    data class Track(val track: RemoteTrack) : PeerEvent
}

/** Соединение WebRTC с собеседником или с SFU сервера. Всё — на главном потоке. */
interface CallPeer {
    var onEvent: ((PeerEvent) -> Unit)?
    val signalingState: PeerSignalingState
    val isGatheringComplete: Boolean
    val localDescription: SessionDescription?

    /** Отправлять микрофон. */
    fun addMicrophone()

    /** Слот только на приём видео (`recvonly`). */
    fun addVideoReceiver()

    /** Начать отправлять видео. `true` — появился новый отправитель: без нового SDP его не увидят. */
    fun sendVideo(video: LocalVideo): Boolean

    /** Перестать отправлять видео: отправитель остаётся, но без дорожки. */
    fun stopVideo(video: LocalVideo)

    /** SFU: отдать видео в слот, который сервер предложил приёмом (`a=recvonly`) с этими `mid`. */
    fun fillVideoSlot(mids: Set<String>, video: LocalVideo): Boolean

    suspend fun makeOffer(iceRestart: Boolean): SessionDescription

    suspend fun makeAnswer(): SessionDescription

    suspend fun setLocal(description: SessionDescription)

    suspend fun setRemote(description: SessionDescription)

    /** Кандидат собеседника. Ошибку WebRTC глотает: битый кандидат не рвёт звонок. */
    suspend fun add(candidate: IceCandidate)

    /** Дорожки всех приёмников. */
    fun remoteTracks(): List<RemoteTrack>

    fun openChannel(label: String): CallDataChannel?

    /** Уровни звука 0…1: своего микрофона и самого громкого входящего; `null` — статистики нет. */
    suspend fun audioLevels(): Pair<Double, Double>?

    fun close()
}

/** Канал данных WebRTC. Всё — на главном потоке. */
interface CallDataChannel {
    val label: String
    val isOpen: Boolean
    var onOpen: (() -> Unit)?
    var onMessage: ((ByteArray) -> Unit)?

    fun send(data: ByteArray): Boolean

    fun close()
}

class CallMediaException(val kind: Kind) : Exception(kind.name) {
    enum class Kind {
        /** Нет разрешения на микрофон, камеру или показ экрана. */
        DENIED,

        /** Устройство недоступно. */
        UNAVAILABLE,
    }
}

/** Свои микрофон, камера и экран и фабрика соединений. Один на звонок. */
interface CallMedia {
    fun makePeer(iceServers: List<CallIceServer>): CallPeer?

    /** Id дорожки своего видео: по нему SDP подписывается `u<id>:sCAMERA` / `u<id>:sSCREEN`. */
    fun trackId(video: LocalVideo): String?

    /** Бросает [CallMediaException]. */
    suspend fun startCamera(position: CallCameraPosition)

    fun stopCamera()

    /** Бросает [CallMediaException]. */
    suspend fun startScreen()

    fun stopScreen()

    fun setMicrophone(enabled: Boolean)

    fun setSpeaker(on: Boolean)

    /** Звонок закончился: остановить захват и освободить всё. */
    fun shutdown()
}
