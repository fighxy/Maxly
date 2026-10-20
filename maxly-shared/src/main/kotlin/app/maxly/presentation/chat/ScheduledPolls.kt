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
    /** Текст отказа `poll.already.voted`: код сервера пользователю не показывается. */
    const val ALREADY_VOTED_TEXT = "Вы уже проголосовали"

    /** Особый «ответ» кнопки «Голосовать» у опроса с несколькими ответами. */
    const val SUBMIT = "\u0000submit"

    /** Опрос закрыт или голос уже отдан без права переголосовать — ответы только показывают итог. */
    fun canVote(poll: PollContent): Boolean = !poll.closed && (!hasVoted(poll) || poll.revote)

    /** Голос уже отдан: есть свои ответы или сервер ответил `poll.already.voted`. */
    fun hasVoted(poll: PollContent): Boolean = poll.voted || poll.mine.isNotEmpty()

    /** Итоги видны: опрос закрыт или голос отдан. */
    fun showsResults(poll: PollContent): Boolean = poll.closed || hasVoted(poll)

    /** Доля ответа в процентах: от сервера, иначе из счётчиков. */
    fun percent(poll: PollContent, answer: app.maxly.domain.PollAnswer): Int =
        answer.rate ?: if (poll.total <= 0) 0 else (answer.votes * 100 + poll.total / 2) / poll.total

    /** Текст счётчика ответа: при видимых итогах — проценты, иначе число голосов. */
    fun counter(poll: PollContent, answer: app.maxly.domain.PollAnswer): String =
        if (showsResults(poll)) "${percent(poll, answer)}%" else answer.votes.toString()

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

    /**
     * Состояние из ответа на голос целиком: счётчики, проценты и свои ответы ([sent] — если сервер
     * их не отметил). Ответы без строки в ответе сервера сохраняют прежнее число.
     */
    fun applyTally(poll: PollContent, tally: PollTally, sent: Collection<String> = emptyList()): PollContent = poll.copy(
        total = tally.total,
        answers = poll.answers.map { answer ->
            answer.copy(votes = tally.votes[answer.id] ?: answer.votes, rate = tally.rates[answer.id] ?: answer.rate)
        },
        mine = tally.mine.ifEmpty { sent.toSet() }.ifEmpty { poll.mine },
        picked = emptySet(),
    )

    /**
     * Опрос сообщения с учётом свежего состояния (306), своего голоса и отметок. Свежий опрос
     * заменяет ответы, счётчики и биты; заголовок остаётся прежним, если свежий пуст.
     */
    fun merge(poll: PollContent, fresh: PollContent?, mine: Set<String>?, picked: Set<String>?, voted: Boolean = false): PollContent {
        val base = fresh?.let { it.copy(title = it.title.ifBlank { poll.title }) } ?: poll
        return base.copy(mine = mine ?: base.mine.ifEmpty { poll.mine }, picked = picked ?: emptySet(), voted = voted || base.voted)
    }
}
