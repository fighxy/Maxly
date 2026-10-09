package app.maxly.data

import app.maxly.domain.MaxlyError
import app.maxly.presentation.chat.ChatViewModel
import com.maxly.core.protocol.CmdType
import com.maxly.core.protocol.Opcode
import com.maxly.core.protocol.PROTOCOL_VERSION
import com.maxly.core.protocol.PacketHeader
import com.maxly.core.transport.ServerErrorException
import com.maxly.core.transport.TransportPacket
import kotlinx.coroutines.CancellationException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Тексты ошибок от сервера идут на экран первыми, свои — запасные. */
class ServerErrorTextsTest {

    private fun serverError(body: Map<String, Any?>): ServerErrorException =
        ServerErrorException.from(TransportPacket(PacketHeader(PROTOCOL_VERSION, CmdType.ERROR.value, 7, Opcode.MSG_SEND.value.toShort(), 0, false), body))

    private fun failure(kind: String, key: String? = null, text: String? = null) = CoreFailure(kind, key, "сырой текст", text)

    @Test
    fun gatewayTakesTheServerText() {
        val both = MaxCoreGateway.failureOf(serverError(mapOf("error" to "chat.denied", "title" to "Нет доступа", "localizedMessage" to "Вас удалили из чата")))
        assertEquals("SERVER", both.kind)
        assertEquals("chat.denied", both.key)
        // Как у сервера: заголовок, иначе локализованный текст.
        assertEquals("Нет доступа", both.serverText)
        val message = MaxCoreGateway.failureOf(serverError(mapOf("error" to "chat.denied", "localizedMessage" to "Вас удалили из чата")))
        assertEquals("Вас удалили из чата", message.serverText)
        val none = MaxCoreGateway.failureOf(serverError(mapOf("error" to "chat.denied", "message" to "denied")))
        assertNull(none.serverText)
        val blank = MaxCoreGateway.failureOf(serverError(mapOf("error" to "chat.denied", "title" to "  ")))
        assertNull(blank.serverText)
        // У сетевых и прочих ошибок текста сервера нет.
        assertNull(MaxCoreGateway.failureOf(IllegalStateException("x")).serverText)
    }

    @Test
    fun serverErrorPrefersItsText() {
        val withText = CoreErrors.map(failure("SERVER", "chat.denied", "Нет доступа"))
        assertEquals(MaxlyError.Server("chat.denied", "Нет доступа"), withText)
        assertEquals("Нет доступа", withText.userMessage)
        assertEquals("Нет доступа", withText.serverText)
        val bare = CoreErrors.map(failure("SERVER", "chat.denied"))
        assertEquals("Ошибка сервера (chat.denied). Попробуйте позже", bare.userMessage)
        assertNull(bare.serverText)
        assertEquals("Сервер долго не отвечает", CoreErrors.map(failure("UPLOAD", text = "Сервер долго не отвечает")).userMessage)
    }

    @Test
    fun rateLimitStaysARateLimitWithTheServerText() {
        val error = CoreErrors.map(failure("SERVER", MaxlyError.RATE_LIMIT_CODE, "Подождите минуту"))
        assertTrue(error.isRateLimit)
        assertTrue(error.isTransient)
        assertEquals("Подождите минуту", error.userMessage)
        assertEquals("Сервер просит подождать: слишком много запросов", CoreErrors.map(failure("SERVER", MaxlyError.RATE_LIMIT_CODE)).userMessage)
    }

    @Test
    fun rejectedRequestShowsTheServerText() {
        assertEquals(MaxlyError.Rejected("Нельзя"), CoreErrors.map(failure("AUTH", text = "Нельзя")))
        assertEquals(MaxlyError.Rejected("Не найдено"), CoreErrors.map(failure("NOT_FOUND", text = "Не найдено")))
        assertEquals(MaxlyError.InvalidRequest, CoreErrors.map(failure("AUTH")))
        assertEquals(MaxlyError.NetworkUnavailable, CoreErrors.map(failure("NETWORK")))
    }

    @Test
    fun loginStepsPreferTheServerText() {
        for (step in AuthStep.values()) {
            assertEquals(step.name, MaxlyError.Rejected("Код неверный, осталось 2 попытки"), AuthErrors.map(failure("SERVER", "verify.code", "Код неверный, осталось 2 попытки"), step))
            assertEquals(step.name, MaxlyError.Rejected("Попробуйте через час"), AuthErrors.map(failure("SERVER", "too.many.attempts", "Попробуйте через час"), step))
            assertEquals(step.name, MaxlyError.Rejected("Начните заново"), AuthErrors.map(failure("SESSION_EXPIRED", "verify.token", "Начните заново"), step))
        }
        // Без текста сервера — свои тексты, как раньше.
        assertEquals(MaxlyError.Rejected("Неверный код"), AuthErrors.map(failure("SERVER", "verify.code"), AuthStep.VERIFY_CODE))
        assertEquals(MaxlyError.Rejected("Неверный пароль"), AuthErrors.map(failure("AUTH"), AuthStep.PASSWORD))
        assertEquals(MaxlyError.Rejected(AuthErrors.TOO_MANY_ATTEMPTS), AuthErrors.map(failure("SERVER", "too.many.attempts"), AuthStep.REQUEST_CODE))
        assertEquals(MaxlyError.Rejected("Код устарел. Запросите новый"), AuthErrors.map(failure("SESSION_EXPIRED"), AuthStep.VERIFY_CODE))
    }

    @Test
    fun recoveryEmailPrefersTheServerText() {
        assertEquals(MaxlyError.Rejected("Адрес занят"), TwoFactorErrors.rejection(failure("SERVER", "email.limit", "Адрес занят"), "Неверный код"))
        assertEquals(MaxlyError.Rejected(AuthErrors.TOO_MANY_ATTEMPTS), TwoFactorErrors.rejection(failure("SERVER", "email.limit"), "Неверный код"))
        assertEquals(MaxlyError.Rejected("Неверный код"), TwoFactorErrors.rejection(failure("SERVER", "email.code"), "Неверный код"))
    }

    @Test
    fun screenTextOrder() {
        // Сервер, затем переведённая ошибка, затем свой текст действия.
        assertEquals("Нет доступа", CoreErrors.text(failure("SERVER", "chat.denied", "Нет доступа"), "Не удалось удалить чат"))
        assertEquals("Нет доступа", CoreErrors.text(MaxlyError.Server("chat.denied", "Нет доступа"), "Не удалось удалить чат"))
        assertEquals("Не удалось удалить чат", CoreErrors.text(failure("SERVER", "chat.denied"), "Не удалось удалить чат"))
        assertEquals("Нет соединения с сервером", CoreErrors.text(MaxlyError.NetworkUnavailable, "Не удалось удалить чат"))
        assertEquals("Не удалось удалить чат", CoreErrors.text(MaxlyError.Cancelled, "Не удалось удалить чат"))
        assertEquals(CoreErrors.UNKNOWN_TEXT, CoreErrors.text(IllegalStateException("x")))
        assertEquals(CoreErrors.UNKNOWN_TEXT, CoreErrors.text(CancellationException("x")))
    }

    @Test
    fun reactionFailureText() {
        assertEquals("Реакции в этом чате выключены", ChatViewModel.reactionFailure(failure("SERVER", "reactions.disabled", "Реакции в этом чате выключены")))
        assertEquals("Слишком много реакций", ChatViewModel.reactionFailure(MaxlyError.Rejected("Слишком много реакций")))
        assertEquals(ChatViewModel.REACTION_FAILURE, ChatViewModel.reactionFailure(failure("SERVER", "reactions.disabled")))
        assertEquals(ChatViewModel.REACTION_FAILURE, ChatViewModel.reactionFailure(failure("NETWORK")))
    }
}
