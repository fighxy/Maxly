package app.orbitle.presentation.chat

/** Кнопка расшифровки голосового: что она показывает и как звучит для TalkBack. */
object TranscriptToggle {
    /** Кириллическая «Т» — «текст» рядом со стрелкой, пока расшифровка скрыта. */
    const val LETTER = "Т"
    const val COLLAPSED_ALPHA = 0.14f
    const val EXPANDED_ALPHA = 0.3f

    /** [open] — расшифровка показана или загружается. */
    fun description(open: Boolean): String = if (open) "Скрыть расшифровку" else "Показать расшифровку"

    fun backgroundAlpha(open: Boolean): Float = if (open) EXPANDED_ALPHA else COLLAPSED_ALPHA
}
