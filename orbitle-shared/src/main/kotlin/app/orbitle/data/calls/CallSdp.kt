package app.orbitle.data.calls

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/** Хозяин дорожки: участник, слот SFU и экран ли это. */
data class TrackOwner(val participant: Long? = null, val slot: Int? = null, val screen: Boolean = false)

/** Разбор SDP и идентификаторов сервера звонков. */
object CallSdp {
    /** Номера `a=ssrc:` по порядку, без повторов: их сервер ждёт в `accept-producer`. */
    fun ssrcs(sdp: String): List<String> {
        val result = LinkedHashSet<String>()
        for (line in lines(sdp)) {
            if (!line.startsWith("a=ssrc:")) continue
            val number = line.removePrefix("a=ssrc:").takeWhile { it.isDigit() }
            if (number.isNotEmpty()) result += number
        }
        return result.toList()
    }

    /** Первый `a=ice-ufrag:` в SDP; с BUNDLE он один на все секции. */
    fun iceUfrag(sdp: String): String? =
        lines(sdp).firstOrNull { it.startsWith("a=ice-ufrag:") }?.removePrefix("a=ice-ufrag:")?.takeIf { it.isNotEmpty() }

    /** Кандидаты прямо в SDP сервера (SFU не шлёт их отдельно) с `mid` первой секции. */
    fun candidates(sdp: String): List<IceCandidate> {
        val all = lines(sdp)
        val mid = all.firstOrNull { it.startsWith("a=mid:") }?.removePrefix("a=mid:") ?: return emptyList()
        return all.filter { it.startsWith("a=candidate:") }
            .map { it.substring(2) }
            .distinct()
            .map { IceCandidate(it, mid, 0) }
    }

    /** `mid` видеосекций, которые сервер предлагает только на приём (`a=recvonly`): слоты под своё видео в SFU. */
    fun receiveOnlyVideoMids(sdp: String): Set<String> {
        val mids = LinkedHashSet<String>()
        var kind: String? = null
        var mid: String? = null
        var receiveOnly = false
        fun flush() {
            if (kind == "video" && receiveOnly) mid?.let { mids += it }
        }
        for (line in lines(sdp)) {
            when {
                line.startsWith("m=") -> {
                    flush()
                    kind = line.substring(2).split(' ').firstOrNull()
                    mid = null
                    receiveOnly = false
                }
                line.startsWith("a=mid:") -> mid = line.removePrefix("a=mid:")
                line == "a=recvonly" -> receiveOnly = true
            }
        }
        flush()
        return mids
    }

    /**
     * Подписывает свои видеодорожки так, как их ищет сервер: id дорожки в `a=msid` и
     * `a=ssrc … msid/label` заменяется на `u<свой номер>:sCAMERA` или `:sSCREEN`.
     */
    fun label(sdp: String, names: Map<String, String>): String {
        if (names.isEmpty()) return sdp
        val separator = if ("\r\n" in sdp) "\r\n" else "\n"
        return sdp.split(separator).joinToString(separator) { line ->
            val fields = line.split(' ')
            when {
                line.startsWith("a=msid:") && fields.size == 2 -> names[fields[1]]?.let { "${fields[0]} $it" } ?: line
                line.startsWith("a=ssrc:") && fields.size == 3 && fields[1].startsWith("msid:") ->
                    names[fields[2]]?.let { "${fields[0]} ${fields[1]} $it" } ?: line
                line.startsWith("a=ssrc:") && fields.size == 2 && fields[1].startsWith("label:") ->
                    names[fields[1].removePrefix("label:")]?.let { "${fields[0]} label:$it" } ?: line
                else -> line
            }
        }
    }

    /**
     * Номер участника из `participantId`: число или строка вида `u123:d0` (`u` — пользователь,
     * `g` — группа, `d` — номер устройства).
     */
    fun participantId(raw: JsonElement?): Long? {
        val primitive = raw as? JsonPrimitive ?: return null
        if (!primitive.isString) return raw.long
        for (segment in primitive.content.split(':')) {
            if (segment.isEmpty()) continue
            val head = segment.first()
            if (head == 'u' || head == 'g') {
                segment.drop(1).toLongOrNull()?.let { return it }
            } else if (head != 'd') {
                segment.toLongOrNull()?.let { return it }
            }
        }
        return null
    }

    /**
     * Чья видеодорожка и что в ней, по её id: `u123:sSCREEN` / `u123:sCAMERA`, слот SFU
     * `video-pat-3`, `video-123` / `audio-123`.
     */
    fun owner(trackId: String): TrackOwner {
        if (trackId.startsWith("video-pat-")) {
            trackId.removePrefix("video-pat-").toIntOrNull()?.let { return TrackOwner(slot = it) }
        }
        if (trackId.startsWith("u")) {
            val parts = trackId.split(':')
            parts.first().drop(1).toLongOrNull()?.let { participant ->
                return TrackOwner(participant = participant, screen = parts.drop(1).any { it == "sSCREEN" })
            }
        }
        for (prefix in listOf("video-", "audio-")) {
            if (trackId.length > prefix.length && trackId.startsWith(prefix)) {
                participantId(JsonPrimitive(trackId.removePrefix(prefix)))?.let { return TrackOwner(participant = it) }
            }
        }
        return TrackOwner()
    }

    /** Ключ видео участника в раскладке SFU. */
    fun layoutKey(participant: Long, screen: Boolean): String = "u$participant:${if (screen) "sSCREEN" else "sCAMERA"}"

    private fun lines(sdp: String): List<String> = sdp.split('\n', '\r').map { it.trim() }.filter { it.isNotEmpty() }
}
