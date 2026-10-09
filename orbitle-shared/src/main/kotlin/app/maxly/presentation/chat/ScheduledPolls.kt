package app.maxly.presentation.chat

import app.maxly.domain.PollContent
import app.maxly.domain.PollTally
import app.maxly.domain.ScheduledChange
import app.maxly.domain.ScheduledMessage

/** Список отложенных чата и его правка по пушам 154. */
object ScheduledList {
    /** Сначала то, что уйдёт раньше; без времени — в конце. */
    fun sorted(list: List<ScheduledMessage>): List<ScheduledMessage> =
        list.sortedWith(compareBy(nullsLast()) { it.sendAt })

    /** Новый список после пуша; `null` — пуш непонятен, список надо перечитать. */
    fun apply(list: List<ScheduledMessage>, change: ScheduledChange): List<ScheduledMessage>? = when (change) {
        is ScheduledChange.Upsert -> sorted(list.filterNot { it.id == change.message.id } + change.message)
        is ScheduledChange.Removed -> list.filterNot { it.id in change.ids }
        ScheduledChange.Reload -> null
    }
}

/** Голосование в опросе: кто может голосовать, отметки нескольких ответов, свежие счётчики. */
object PollRules {
    /** Особый «ответ» кнопки «Голосовать» у опроса с несколькими ответами. */
    const val SUBMIT = "\u0000submit"

    /** Опрос закрыт или голос уже отдан без права переголосовать — ответы только показывают итог. */
    fun canVote(poll: PollContent): Boolean = !poll.closed && (poll.mine.isEmpty() || poll.revote)

    /** Подпись под опросом: число голосов, «завершён» и подсказка про несколько ответов. */
    fun footer(poll: PollContent): String = buildList {
        add("Голосов: ${poll.total}")
        if (poll.closed) add("опрос завершён")
        else if (poll.multiple && canVote(poll)) add("можно выбрать несколько")
    }.joinToString(" · ")

    /** Касание ответа: в опросе с несколькими ответами — отметка, иначе выбор одного. */
    fun toggle(poll: PollContent, picked: Set<String>, answerId: String): Set<String> = when {
        !poll.multiple -> setOf(answerId)
        answerId in picked -> picked - answerId
        else -> picked + answerId
    }

    /** Счётчики из ответа на голос; ответы без строки в ответе сервера сохраняют прежнее число. */
    fun applyTally(poll: PollContent, tally: PollTally): PollContent = poll.copy(
        total = tally.total,
        answers = poll.answers.map { answer -> tally.votes[answer.id]?.let { answer.copy(votes = it) } ?: answer },
    )

    /**
     * Опрос сообщения с учётом свежего состояния (306), своего голоса и отметок. Свежий опрос
     * заменяет ответы, счётчики и биты; заголовок остаётся прежним, если свежий пуст.
     */
    fun merge(poll: PollContent, fresh: PollContent?, mine: Set<String>?, picked: Set<String>?): PollContent {
        val base = fresh?.let { it.copy(title = it.title.ifBlank { poll.title }) } ?: poll
        return base.copy(mine = mine ?: base.mine, picked = picked ?: emptySet())
    }
}
