package app.orbitle.presentation.common

import app.orbitle.domain.ChatType
import app.orbitle.domain.Typist
import app.orbitle.domain.TypingKind

/**
 * Строка индикатора «печатает…» и его родни. В группе берётся вид действия того, кто начал
 * раньше всех, и показываются только люди с этим же видом: «Иван печатает…», «Иван и Петя
 * печатают…», «Иван, Петя и Маша печатают…», с четырёх — «Иван и ещё 3 печатают…». Нет нужного
 * имени (до трёх — всех, с четырёх — первого) — вместо имён число участников. В личке — без
 * имени, в канале — ничего. Правила общие с iOS: `test-fixtures/typing`, `texts-*`.
 */
object TypingText {

    fun of(typists: List<Typist>, chatType: ChatType): String? {
        if (typists.isEmpty() || chatType == ChatType.CHANNEL) return null
        val sorted = typists.sortedWith(Typist.ORDER)
        val kind = sorted.first().kind
        val same = sorted.filter { it.kind == kind }
        if (chatType != ChatType.GROUP) return "${verb(kind, plural = false)}…"
        val names = same.map { it.name?.takeIf(String::isNotBlank) }
        val needed = if (names.size >= 4) names.take(1) else names
        if (needed.any { it == null }) return counted(same.size, kind)
        val who = when (names.size) {
            1 -> names[0]
            2 -> "${names[0]} и ${names[1]}"
            3 -> "${names[0]}, ${names[1]} и ${names[2]}"
            else -> "${names[0]} и ещё ${names.size - 1}"
        }
        return "$who ${verb(kind, plural = names.size > 1)}…"
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
