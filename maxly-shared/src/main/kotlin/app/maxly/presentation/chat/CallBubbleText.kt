package app.maxly.presentation.chat

import app.maxly.domain.CallContent
import app.maxly.domain.CallOutcome

/** Подписи звонка в ленте. Исход — из [CallContent.outcome], как и во вкладке «Звонки». */
object CallBubbleText {

    /** «Исходящий звонок», «Пропущенный видеозвонок», «Групповой звонок»… */
    fun title(call: CallContent, outgoing: Boolean): String {
        val noun = if (call.isVideo) "видеозвонок" else "звонок"
        if (call.isGroup) return "Групповой $noun"
        val base = when (call.outcome(outgoing)) {
            CallOutcome.ANSWERED -> if (outgoing) "Исходящий" else "Входящий"
            CallOutcome.MISSED -> "Пропущенный"
            CallOutcome.CANCELLED -> "Отменённый"
            CallOutcome.DECLINED -> "Отклонённый"
        }
        return "$base $noun"
    }

    /** Длительность состоявшегося разговора, `null`, если разговора не было. */
    fun duration(call: CallContent): String? = if (call.isConnected) clock(call.durationMs) else null

    /** «0:42», «12:05», «1:02:03». */
    fun clock(ms: Long): String {
        val seconds = maxOf(0L, ms) / 1000
        val hours = seconds / 3600
        val minutes = seconds % 3600 / 60
        return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds % 60) else "%d:%02d".format(minutes, seconds % 60)
    }

    /** Красным — пропущенный входящий. */
    fun isAlert(call: CallContent, outgoing: Boolean): Boolean = call.isMissed(outgoing)

    enum class Icon { PHONE, VIDEO, OUTGOING, INCOMING, PHONE_DOWN, VIDEO_OFF }

    fun icon(call: CallContent, outgoing: Boolean): Icon {
        if (call.isGroup) return if (call.isVideo) Icon.VIDEO else Icon.PHONE
        return when (call.outcome(outgoing)) {
            CallOutcome.ANSWERED -> when {
                call.isVideo -> Icon.VIDEO
                outgoing -> Icon.OUTGOING
                else -> Icon.INCOMING
            }
            else -> if (call.isVideo) Icon.VIDEO_OFF else Icon.PHONE_DOWN
        }
    }

    fun accessibility(call: CallContent, outgoing: Boolean, time: String): String {
        val parts = mutableListOf(title(call, outgoing))
        duration(call)?.let { parts += "длительность $it" }
        if (time.isNotEmpty()) parts += time
        return parts.joinToString(", ")
    }
}
