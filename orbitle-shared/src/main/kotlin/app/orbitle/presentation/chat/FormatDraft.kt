package app.orbitle.presentation.chat

import app.orbitle.domain.TextSpan
import app.orbitle.domain.TextSpans

/**
 * Разметка текста в поле ввода: жирный, курсив, подчёркнутый, зачёркнутый, моноширинный и
 * ссылки (смещения UTF-16 по тексту поля, как у сервера). Правка текста сдвигает отрезки:
 * вставка до отрезка двигает его, внутри — растягивает, после или вплотную за ним — не трогает;
 * удалённый текст вырезается из отрезков, пустые выпадают. Повторное применение того же вида к
 * уже размеченному выделению снимает разметку, частично размеченное — размечает целиком.
 *
 * Упоминания здесь не хранятся: их ведёт [MentionDraft] по тексту `@имя`. Остальные виды
 * разметки сервера (заголовок, цитата, анимодзи) черновик держит как есть, когда правится
 * сообщение с ними: они сдвигаются вместе с текстом, но панелью не ставятся.
 */
class FormatDraft {
    private var ranges: List<TextSpan> = emptyList()

    /** Отрезки по порядку: по началу, затем по виду. */
    val spans: List<TextSpan> get() = ranges

    fun clear() {
        ranges = emptyList()
    }

    /** Разметка правимого сообщения или сохранённая раньше; упоминания и пустые отрезки отбрасываются. */
    fun restore(spans: List<TextSpan>, textLength: Int = Int.MAX_VALUE) {
        ranges = normalize(spans.filter { it.kind in KEPT }.mapNotNull { clip(it, textLength) })
    }

    /**
     * Текст поля сменился с [old] на [new]. Правка находится по общему началу и концу строк;
     * [cursor] — курсор после правки (`-1` — неизвестен) уточняет место, если правка стоит
     * среди одинаковых знаков («аа» → «ааа»).
     */
    fun edit(old: String, new: String, cursor: Int = -1) {
        if (old == new) return
        val (at, removed, inserted) = diff(old, new, cursor)
        replace(at, removed, inserted)
    }

    /** На месте [at] убрано [removed] знаков и вставлено [inserted]. */
    fun replace(at: Int, removed: Int, inserted: Int) {
        if (removed == 0 && inserted == 0) return
        ranges = normalize(ranges.mapNotNull { shift(it, at, removed, inserted) })
    }

    /** Весь отрезок [start, end) размечен видом [kind] (у ссылки — любой ссылкой). */
    fun isApplied(kind: TextSpan.Kind, start: Int, end: Int): Boolean = covers(ranges, kind, start, end)

    /**
     * Кнопка панели: размеченное целиком [start, end) — снять разметку (отрезок разрежется),
     * иначе — разметить весь [start, end), сливаясь с соседними отрезками того же вида.
     * Ссылки ставит [setLink]. Возвращает, размечен ли отрезок теперь.
     */
    fun toggle(kind: TextSpan.Kind, start: Int, end: Int): Boolean {
        require(kind != TextSpan.Kind.LINK) { "ссылку ставит setLink" }
        if (start >= end || kind !in KEPT) return false
        return if (isApplied(kind, start, end)) {
            ranges = normalize(subtract(ranges, kind, start, end))
            false
        } else {
            ranges = normalize(ranges + TextSpan(kind, start, end - start))
            true
        }
    }

    /** Ссылка [url] на [start, end) вместо прежних ссылок там; `null` — убрать ссылку с отрезка. */
    fun setLink(start: Int, end: Int, url: String?) {
        if (start >= end) return
        val rest = subtract(ranges, TextSpan.Kind.LINK, start, end)
        ranges = normalize(if (url == null) rest else rest + TextSpan(TextSpan.Kind.LINK, start, end - start, url = url))
    }

    /** Адрес ссылки, которая целиком накрывает [start, end), иначе `null`. */
    fun linkAt(start: Int, end: Int): String? =
        ranges.firstOrNull { it.kind == TextSpan.Kind.LINK && it.from <= start && it.from + it.length >= end && start < end }?.url

    /** Отрезки по тексту [text]: всё, что вышло за его конец, обрезано. */
    fun spansFor(text: String): List<TextSpan> = ranges.mapNotNull { clip(it, text.length) }

    /**
     * Что уйдёт на сервер: текст поля без пробелов по краям и отрезки по нему (начало сдвинуто
     * на срезанные пробелы, вышедшее за края обрезано, один вид слит) — [TextSpans.serialize].
     */
    fun trimmed(draft: String): Pair<String, List<TextSpan>> = TextSpans.serialize(draft, ranges)

    companion object {
        /** Виды кнопок панели форматирования, по порядку. */
        val TOOLBAR: List<TextSpan.Kind> = listOf(
            TextSpan.Kind.STRONG,
            TextSpan.Kind.EMPHASIZED,
            TextSpan.Kind.UNDERLINE,
            TextSpan.Kind.STRIKETHROUGH,
            TextSpan.Kind.MONOSPACED,
            TextSpan.Kind.LINK,
        )

        /** Что держит черновик: всё, кроме упоминаний ([MentionDraft]). */
        private val KEPT: Set<TextSpan.Kind> = TextSpan.Kind.entries.toSet() - TextSpan.Kind.MENTION

        /** Весь [start, end) накрыт отрезками вида [kind] из [spans]. Пустой отрезок не накрыт. */
        fun covers(spans: List<TextSpan>, kind: TextSpan.Kind, start: Int, end: Int): Boolean {
            if (start >= end) return false
            var reached = start
            for (span in spans.filter { it.kind == kind }.sortedBy { it.from }) {
                if (span.from > reached) break
                reached = maxOf(reached, span.from + span.length)
                if (reached >= end) return true
            }
            return false
        }

        /**
         * Адрес из поля диалога ссылки: без пробелов по краям; без схемы — `https://`.
         * `null` — пусто или в адресе пробелы.
         */
        fun normalizeUrl(raw: String): String? {
            val url = raw.trim()
            if (url.isEmpty() || url.any { it.isWhitespace() }) return null
            val schemed = url.contains("://") || url.startsWith("mailto:", true) || url.startsWith("tel:", true)
            return if (schemed) url else "https://$url"
        }

        /**
         * Где правка: общее начало и конец строк, место — по курсору после правки, если он
         * известен. Возвращает (место, сколько убрано, сколько вставлено).
         */
        internal fun diff(old: String, new: String, cursor: Int): Triple<Int, Int, Int> {
            val shorter = minOf(old.length, new.length)
            var prefix = 0
            while (prefix < shorter && old[prefix] == new[prefix]) prefix++
            var suffixLimit = shorter - prefix
            if (cursor in 0..new.length) {
                // Вставленное кончается у курсора: общее начало не заходит за вставку, общий конец — за курсор.
                val grown = (new.length - old.length).coerceAtLeast(0)
                prefix = minOf(prefix, (cursor - grown).coerceAtLeast(0))
                suffixLimit = minOf(shorter - prefix, new.length - cursor)
            }
            var suffix = 0
            while (suffix < suffixLimit && old[old.length - 1 - suffix] == new[new.length - 1 - suffix]) suffix++
            return Triple(prefix, old.length - prefix - suffix, new.length - prefix - suffix)
        }

        private fun shift(span: TextSpan, at: Int, removed: Int, inserted: Int): TextSpan? {
            val start = span.from
            val end = span.from + span.length
            val cut = at + removed
            val delta = inserted - removed
            val (from, to) = when {
                // Вставка: до отрезка или в его начало — сдвиг, внутри — растёт, в конце и дальше — как был.
                removed == 0 -> when {
                    at <= start -> start + delta to end + delta
                    at < end -> start to end + delta
                    else -> start to end
                }
                cut <= start -> start + delta to end + delta
                at >= end -> start to end
                // Заменён кусок внутри отрезка (или весь он): новый текст размечен так же.
                at >= start && cut <= end -> start to end + delta
                // Удаление захватило весь отрезок.
                at <= start && cut >= end -> return null
                // Захвачено начало: остаётся хвост после правки.
                at < start -> at + inserted to at + inserted + (end - cut)
                // Захвачен конец: остаётся голова до правки.
                else -> start to at
            }
            return if (to > from) span.copy(from = from, length = to - from) else null
        }

        private fun clip(span: TextSpan, length: Int): TextSpan? {
            val from = span.from.coerceIn(0, length)
            val to = (span.from + span.length).coerceIn(from, length)
            return if (to > from) span.copy(from = from, length = to - from) else null
        }

        /** Убрать [start, end) из отрезков вида [kind]: накрытые выпадают, задетые режутся. */
        private fun subtract(spans: List<TextSpan>, kind: TextSpan.Kind, start: Int, end: Int): List<TextSpan> = spans.flatMap { span ->
            val from = span.from
            val to = span.from + span.length
            if (span.kind != kind || to <= start || from >= end) return@flatMap listOf(span)
            buildList {
                if (from < start) add(span.copy(length = start - from))
                if (to > end) add(span.copy(from = end, length = to - end))
            }
        }

        /** Пересекающиеся и смежные отрезки одного вида сливаются (ссылки — только с тем же адресом). */
        private fun normalize(spans: List<TextSpan>): List<TextSpan> = TextSpans.normalize(spans)
    }
}
