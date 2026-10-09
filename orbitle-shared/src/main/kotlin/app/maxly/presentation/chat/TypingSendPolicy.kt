package app.maxly.presentation.chat

import app.maxly.domain.TypingKind

/**
 * Когда отправлять свой кадр «печатает…» (команда 65). Ядро частоту не ограничивает, правила
 * общие с iOS (`test-fixtures/typing`, `sending-*`):
 *
 * - порог один на чат для всех видов: кадр не уходит, если в чат что-то ушло меньше [thresholdMs]
 *   назад; пропущенный кадр порог не сдвигает;
 * - `TEXT` на каждую правку текста, `PHOTO`/`VIDEO`/`FILE` на каждый шаг загрузки, `STICKER` при
 *   открытии панели;
 * - запись (`AUDIO`, `VIDEO_MSG`) — в начале и каждые [repeatMs] от её начала, пока она идёт,
 *   каждый повтор тоже проходит порог; повторы делает [tick];
 * - куда писать нельзя, ничего не уходит и запись не запоминается.
 *
 * Время передаёт вызывающий, поэтому правила проверяются без таймеров.
 */
class TypingSendPolicy(
    private val thresholdMs: Long = THRESHOLD_MS,
    private val repeatMs: Long = REPEAT_MS,
) {
    data class Frame(val chatId: String, val kind: TypingKind, val postId: String? = null)

    private class Recording(val kind: TypingKind, val postId: String?, var nextAt: Long)

    private val lastSent = HashMap<String, Long>()
    /** Идущие записи по чатам; повторы — по порядку `chatId`. */
    private val recordings = sortedMapOf<String, Recording>()

    @Synchronized
    fun editText(chatId: String, now: Long, postId: String? = null, canWrite: Boolean = true): Frame? =
        attempt(chatId, TypingKind.TEXT, postId, now, canWrite)

    @Synchronized
    fun uploadProgress(chatId: String, kind: TypingKind, now: Long, postId: String? = null, canWrite: Boolean = true): Frame? =
        attempt(chatId, kind, postId, now, canWrite)

    @Synchronized
    fun openStickers(chatId: String, now: Long, postId: String? = null, canWrite: Boolean = true): Frame? =
        attempt(chatId, TypingKind.STICKER, postId, now, canWrite)

    @Synchronized
    fun startRecording(chatId: String, kind: TypingKind, now: Long, postId: String? = null, canWrite: Boolean = true): Frame? {
        if (!canWrite) return null
        recordings[chatId] = Recording(kind, postId, now + repeatMs)
        return attempt(chatId, kind, postId, now, canWrite = true)
    }

    @Synchronized
    fun stopRecording(chatId: String) {
        recordings.remove(chatId)
    }

    /** Повторы записей, чьё время пришло: несколько пропущенных шагов дают один кадр. */
    @Synchronized
    fun tick(now: Long): List<Frame> = recordings.mapNotNull { (chatId, recording) ->
        if (now < recording.nextAt) return@mapNotNull null
        while (recording.nextAt <= now) recording.nextAt += repeatMs
        attempt(chatId, recording.kind, recording.postId, now, canWrite = true)
    }

    /** Когда звать [tick] в следующий раз; `null` — записей нет. */
    @Synchronized
    fun nextTickAt(): Long? = recordings.values.minOfOrNull { it.nextAt }

    private fun attempt(chatId: String, kind: TypingKind, postId: String?, now: Long, canWrite: Boolean): Frame? {
        if (!canWrite) return null
        lastSent[chatId]?.let { if (now - it < thresholdMs) return null }
        lastSent[chatId] = now
        return Frame(chatId, kind, postId)
    }

    companion object {
        /** Не чаще раза в 6 с на чат: у собеседника отметка живёт 8 с. */
        const val THRESHOLD_MS = 6_000L
        /** Повтор записи от её начала. */
        const val REPEAT_MS = 5_000L
    }
}
