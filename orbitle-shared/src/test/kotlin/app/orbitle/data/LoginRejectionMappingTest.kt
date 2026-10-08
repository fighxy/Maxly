package app.orbitle.data

import app.orbitle.domain.SessionRejection
import com.max.core.auth.InvalidTokenException
import com.max.core.protocol.CmdType
import com.max.core.protocol.Opcode
import com.max.core.protocol.PROTOCOL_VERSION
import com.max.core.protocol.PacketHeader
import com.max.core.transport.ServerErrorException
import com.max.core.transport.TransportPacket
import com.max.shared.ClientState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Отказ ядра во входе ([ClientState.TokenRejected]) в доменном виде. */
class LoginRejectionMappingTest {

    private fun rejected(body: Map<String, Any?>): ClientState.TokenRejected {
        val packet = TransportPacket(PacketHeader(PROTOCOL_VERSION, CmdType.ERROR.value, 1, Opcode.LOGIN.value.toShort(), 0, false), body)
        return ClientState.TokenRejected(InvalidTokenException(ServerErrorException.from(packet)))
    }

    @Test
    fun everyReasonWithServerTexts() {
        for ((key, reason) in listOf("login.token" to SessionRejection.Reason.TOKEN, "login.blocked" to SessionRejection.Reason.BLOCKED, "login.flood" to SessionRejection.Reason.FLOOD)) {
            val r = MaxCoreGateway.rejectionOf(rejected(mapOf("error" to key, "title" to "Заголовок", "localizedMessage" to "Текст", "description" to "Пояснение")))
            assertEquals(key, reason, r.reason)
            assertEquals(key, "Заголовок", r.title)
            assertEquals(key, "Текст", r.localizedMessage)
            assertEquals(key, "Пояснение", r.description)
            // FLOOD токен оставляет, остальные — стирают.
            assertEquals(key, reason != SessionRejection.Reason.FLOOD, r.tokenCleared)
        }
    }

    @Test
    fun withoutServerTexts() {
        val r = MaxCoreGateway.rejectionOf(rejected(mapOf("error" to "login.flood")))
        assertEquals(SessionRejection.Reason.FLOOD, r.reason)
        assertFalse(r.tokenCleared)
        assertNull(r.title)
        assertNull(r.localizedMessage)
        assertNull(r.description)
        // Старый код в `message` — тоже недействительный токен.
        val legacy = MaxCoreGateway.rejectionOf(rejected(mapOf("message" to "FAIL_LOGIN_TOKEN")))
        assertEquals(SessionRejection.Reason.TOKEN, legacy.reason)
        assertTrue(legacy.tokenCleared)
    }
}
