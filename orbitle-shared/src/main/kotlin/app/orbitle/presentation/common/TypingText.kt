package app.orbitle.presentation.common

import app.orbitle.domain.ChatType
import app.orbitle.domain.Typist
import app.orbitle.domain.TypingKind

/**
 * Строка индикатора «печатает…» и его родни. В группе берётся вид действия того, кто начал
 * раньше всех, и показываются только люди с этим же видом: «Иван печатает…», «Иван и Петя
 * печатают…», «Иван, Петя и Маша печатают…», с четырёх — «Иван и ещё 3 печатают…». Нет имени
 * у кого-то из них — вместо имён число участников. В личке — без имени, в канале — ничего.
 */
object TypingText {

    fun of(typists: List<Typist>, chatType: ChatType): String? {
        if (typists.isEmpty() || chatType == ChatType.CHANNEL) return null
        val kind = typists.minBy { it.sinceMs }.kind
        val same = typists.filter { it.kind == kind }.sortedBy { it.sinceMs }
        if (chatType != ChatType.GROUP) return "${verb(kind, plural = false)}…"
        val names = same.map { it.name?.takeIf(String::isNotBlank) }
        if (names.any { it == null }) return counted(same.size, kind)
        val known = names.filterNotNull()
        val who = when (known.size) {
            1 -> known[0]
            2 -> "${known[0]} и ${known[1]}"
            3 -> "${known[0]}, ${known[1]} и ${known[2]}"
            else -> "${known[0]} и ещё ${known.size - 1}"
        }
        return "$who ${verb(kind, plural = known.size > 1)}…"
    }

    /** «3 участника печатают…»: когда имён нет. Один — просто «печатает…». */
    fun counted(count: Int, kind: TypingKind = TypingKind.TEXT): String {
        if (count <= 1) return "${verb(kind, plural = false)}…"
        val noun = PresenceText.plural(count, "участник", "участника", "участников")
        val tens = count % 100
        val singular = count % 10 == 1 && tens != 11
        return "$count $noun ${verb(kind, plural = !singular)}…"
    }

    fun verb(kind: TypingKind, plural: Boolean): String = when (kind) {
        TypingKind.TEXT -> if (plural) "печатают" else "печатает"
        TypingKind.AUDIO -> if (plural) "записывают аудио" else "записывает аудио"
        TypingKind.VIDEO_MSG -> if (plural) "записывают видеосообщение" else "записывает видеосообщение"
        TypingKind.PHOTO -> if (plural) "отправляют фото" else "отправляет фото"
        TypingKind.VIDEO -> if (plural) "отправляют видео" else "отправляет видео"
        TypingKind.FILE -> if (plural) "отправляют файл" else "отправляет файл"
        TypingKind.STICKER -> if (plural) "выбирают стикер" else "выбирает стикер"
    }
}
