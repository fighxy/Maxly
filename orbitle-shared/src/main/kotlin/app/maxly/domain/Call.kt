package app.maxly.domain

/** Сервер ICE для WebRTC: STUN или TURN с логином и паролем. */
data class CallIceServer(val urls: List<String>, val username: String? = null, val credential: String? = null)

/**
 * Куда подключаться к звонку: сигнальный сокет ws2 сервера звонков и свой номер в звонке.
 *
 * Номера участников в звонке ([selfId], id в уведомлениях ws2) — внутренние номера сервера
 * звонков, не id пользователей Max. Id пользователя Max участник несёт в `externalId`.
 */
data class CallConnection(
    val conversationId: String,
    /** Адрес ws2 со всеми параметрами запроса, в нём же токен. */
    val signalingUrl: String,
    val selfId: Long,
    /** Серверы ICE из пуша входящего. У исходящего пусто: их присылает ws2 в `connection`. */
    val iceServers: List<CallIceServer> = emptyList(),
    val isVideo: Boolean = false,
    /** Ссылка группового звонка, которой можно поделиться. */
    val joinLink: String? = null,
)

/** Входящий звонок из пуша сервера. */
data class IncomingCall(
    val conversationId: String,
    /** Id пользователя Max, который звонит. */
    val callerId: String,
    /** Пусто, если звонящего нет в сторе и его профиль не загрузился. */
    val callerName: String,
    val callerAvatarUrl: String? = null,
    val chatId: String? = null,
    val isVideo: Boolean,
    val connection: CallConnection,
    /** После этого времени звонок уже не принять; `null` — сервер не сказал. */
    val expiresAtMs: Long? = null,
)

/** Что за звонок стоит за ссылкой, до входа в него. */
data class CallLinkPreview(val url: String, val name: String? = null, val participants: Int = 0, val isVideo: Boolean = false)

/** Кто мы в звонке. От роли зависит, кто первым шлёт SDP и с какой причиной кладётся трубка. */
enum class CallRole {
    /** Позвонили сами. */
    CALLER,

    /** Ответили на входящий. */
    CALLEE,

    /** Вошли в групповой звонок по ссылке. */
    JOINER,
}

/** Как идут звук и видео: напрямую между двумя участниками или через сервер (SFU). */
enum class CallTopology(val raw: String) {
    DIRECT("DIRECT"),
    SERVER("SERVER"),
    ;

    companion object {
        fun of(raw: String?): CallTopology? = entries.firstOrNull { it.raw == raw }
    }
}

/** Почему звонок закончился. */
sealed interface CallEndReason {
    /** Положили трубку сами. */
    data object HungUp : CallEndReason

    /** Собеседник положил трубку, или сервер закрыл звонок. */
    data object RemoteHungUp : CallEndReason

    /** Собеседник отклонил вызов. */
    data object Declined : CallEndReason

    /** Собеседник занят другим звонком. */
    data object Busy : CallEndReason

    /** Никто не ответил. */
    data object NoAnswer : CallEndReason

    /** Входящий отклонили сами. */
    data object Rejected : CallEndReason

    /** Входящий сбросил звонящий, пока он звонил. */
    data object Missed : CallEndReason

    /** Связь с сервером звонков не восстановилась. */
    data object ConnectionLost : CallEndReason

    /** Звонок не начался: сервер отказал или нет доступа к микрофону. */
    data class Failed(val message: String) : CallEndReason
}

enum class CallCameraPosition { FRONT, BACK }

/** Участник звонка. */
data class CallParticipant(
    /** Номер в звонке (не id Max). */
    val id: Long,
    /** Id пользователя Max; `null`, пока сервер его не прислал. */
    val userId: String? = null,
    val isSelf: Boolean = false,
    /** Состояние на сервере звонков: `CALLED`, `ACCEPTED`, `HUNGUP` и т. п. */
    val state: String = "",
    val audioOn: Boolean = true,
    val videoOn: Boolean = false,
    val screenOn: Boolean = false,
    val handRaised: Boolean = false,
    val speaking: Boolean = false,
    val roles: List<String> = emptyList(),
    /** Видео камеры и экрана для отрисовки: id дорожек WebRTC. */
    val cameraTrack: String? = null,
    val screenTrack: String? = null,
) {
    /** Админ или создатель звонка: может включать запись. */
    val isAdmin: Boolean get() = "ADMIN" in roles || "CREATOR" in roles

    /** Видео, которое стоит показать: экран важнее камеры. */
    val visibleTrack: String?
        get() = when {
            screenOn && screenTrack != null -> screenTrack
            videoOn && cameraTrack != null -> cameraTrack
            else -> null
        }
}

/** Этап звонка. */
sealed interface CallPhase {
    /** Подключаемся к серверу звонков. */
    data object Connecting : CallPhase

    /** Исходящий: у собеседника звонит. Входящий: ждём ответа пользователя. */
    data object Ringing : CallPhase

    /** Разговор идёт. */
    data object Active : CallPhase

    /** Связь пропала, подключаемся заново. */
    data object Reconnecting : CallPhase

    data class Ended(val reason: CallEndReason) : CallPhase
}

/** Состояние звонка для экрана. */
data class CallState(
    val phase: CallPhase = CallPhase.Connecting,
    /** Когда начался разговор: для таймера. */
    val activeSinceMs: Long? = null,
    val muted: Boolean = false,
    val cameraOn: Boolean = false,
    val camera: CallCameraPosition = CallCameraPosition.FRONT,
    val screenSharing: Boolean = false,
    val speakerOn: Boolean = false,
    /** Звук и видео уже идут (WebRTC соединился). */
    val mediaConnected: Boolean = false,
    val topology: CallTopology = CallTopology.DIRECT,
    /** Все участники, свой — с `isSelf`. */
    val participants: List<CallParticipant> = emptyList(),
    /** Своё видео (камера или экран) для превью. */
    val localTrack: String? = null,
    /** Идёт запись звонка. */
    val recording: Boolean = false,
    /** Сообщение для экрана: не включилась камера, не начался показ экрана и т. п. */
    val notice: String? = null,
) {
    val isEnded: Boolean get() = phase is CallPhase.Ended

    /** Остальные участники, без себя. */
    val others: List<CallParticipant> get() = participants.filterNot { it.isSelf }
}
