package app.orbitle.presentation.auth

import app.orbitle.domain.SessionRejection
import app.orbitle.domain.SessionRejection.Reason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LoginNoticesTest {

    @Test
    fun ownTextsWhenTheServerSentNone() {
        val token = LoginNotices.of(SessionRejection(Reason.TOKEN))
        assertEquals("Сессия завершена", token.title)
        assertEquals("Сервер больше не принимает этот вход. Войдите снова по номеру телефона", token.message)
        assertFalse(token.blocking)

        val blocked = LoginNotices.of(SessionRejection(Reason.BLOCKED))
        assertEquals("Аккаунт заблокирован", blocked.title)
        assertEquals("Сервер не пускает в этот аккаунт. Войти можно будет, когда блокировку снимут", blocked.message)
        assertFalse(blocked.blocking)

        val flood = LoginNotices.of(SessionRejection(Reason.FLOOD))
        assertEquals("Слишком много входов", flood.title)
        assertEquals("Сервер временно ограничил вход. Попробуйте позже: сеанс сохранён", flood.message)
        // Токен цел: экран ожидания вместо формы входа.
        assertTrue(flood.blocking)
    }

    @Test
    fun serverTitleAndMessageWin() {
        for (reason in Reason.values()) {
            val notice = LoginNotices.of(SessionRejection(reason, title = "Вход недоступен", localizedMessage = "Подождите 10 минут", description = "Подробнее"))
            assertEquals(reason.name, "Вход недоступен", notice.title)
            assertEquals(reason.name, "Подождите 10 минут", notice.message)
            assertEquals(reason.name, reason == Reason.FLOOD, notice.blocking)
        }
    }

    @Test
    fun descriptionStandsInForAMissingMessage() {
        val notice = LoginNotices.of(SessionRejection(Reason.BLOCKED, title = "Блокировка", description = "За нарушение правил"))
        assertEquals("Блокировка", notice.title)
        assertEquals("За нарушение правил", notice.message)
    }

    @Test
    fun partialServerTextIsCompletedByOurs() {
        // Только пояснение: заголовок свой по причине.
        val body = LoginNotices.of(SessionRejection(Reason.FLOOD, localizedMessage = "Слишком часто"))
        assertEquals("Слишком много входов", body.title)
        assertEquals("Слишком часто", body.message)
        // Только заголовок: своё пояснение не подмешивается к чужому заголовку.
        val title = LoginNotices.of(SessionRejection(Reason.TOKEN, title = "Сессия недействительна"))
        assertEquals("Сессия недействительна", title.title)
        assertNull(title.message)
        // Пустые строки сервера — как отсутствующие.
        val blank = LoginNotices.of(SessionRejection(Reason.TOKEN, title = " ", localizedMessage = ""))
        assertEquals("Сессия завершена", blank.title)
        assertEquals("Сервер больше не принимает этот вход. Войдите снова по номеру телефона", blank.message)
        // Текст, повторяющий заголовок, не дублируется.
        val same = LoginNotices.of(SessionRejection(Reason.BLOCKED, title = "Блокировка", localizedMessage = "Блокировка"))
        assertNull(same.message)
    }

    @Test
    fun keptTokenDecidesBlockingNotTheReason() {
        // Ядро решает, стирать ли токен; экран смотрит на это, а не на код.
        assertTrue(LoginNotices.of(SessionRejection(Reason.TOKEN, tokenCleared = false)).blocking)
        assertFalse(LoginNotices.of(SessionRejection(Reason.FLOOD, tokenCleared = true)).blocking)
    }
}
