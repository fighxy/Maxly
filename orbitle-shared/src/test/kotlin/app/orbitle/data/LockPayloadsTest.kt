package app.orbitle.data

import app.orbitle.domain.TextSpan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LockPayloadsTest {
    @Test
    fun searchAndComplaintKeepTheKnownShape() {
        val search = LockPayloads.inChatSearch(7L, "  привет ")
        assertEquals(7L, search["chatId"])
        assertEquals("привет", search["query"])
        assertEquals(30, search["count"])
        val plain = LockPayloads.complaint(3, LockPayloads.COMPLAINT_CHANNEL, listOf(9L))
        assertFalse(plain.containsKey("parentId"))
        assertEquals(4L, LockPayloads.complaint(3, LockPayloads.COMPLAINT_USER, listOf(9L), 4L)["parentId"])
        assertEquals(0, LockPayloads.complaintReasons()["complainSync"])
        assertEquals(listOf(5L), LockPayloads.commonChats(5L)["userIds"])
    }

    @Test
    fun clearHistoryUsesTheSameThreeFieldsAsDelete() {
        val body = LockPayloads.clearHistory(4L, 90L, false)
        assertEquals(linkedMapOf<String, Any?>("chatId" to 4L, "lastEventTime" to 90L, "forAll" to false), body)
        assertEquals(true, LockPayloads.clearHistory(4L, 90L, true)["forAll"])
    }

    @Test
    fun blankContactNameIsOmitted() {
        assertFalse(LockPayloads.addContact(5L, "  ").containsKey("firstName"))
        assertEquals("ADD", LockPayloads.addContact(5L)["action"])
        assertEquals("Анна", LockPayloads.addContact(5L, " Анна ")["firstName"])
    }

    @Test
    fun callParamsMatchTheKometString() {
        assertEquals(
            """{"platform":"ANDROID","sdkVersion":"0.2.1.3","clientAppKey":"CGPGAGLGDIHBABABA","deviceId":"dev","protocolVersion":5,"onlyAdminCanRecord":false,"isWaitForAdminEnabled":false,"hexCapability":"3c02f"}""",
            LockPayloads.callInternalParams("dev"),
        )
        val call = LockPayloads.initiateCall("cid", 8L, "dev", true)
        assertEquals(listOf(8L), call["calleeIds"])
        assertEquals(true, call["isVideo"])
        assertEquals("wss://x", LockPayloads.endpointOf("""{"endpoint":"wss://x"}"""))
        assertNull(LockPayloads.endpointOf("""{"endpoint":""}"""))
        assertNull(LockPayloads.endpointOf(null))
    }

    @Test
    fun mentionsSkipBadSpans() {
        val text = "@anna"
        val elements = LockPayloads.mentionElements(
            text,
            listOf(
                TextSpan(TextSpan.Kind.MENTION, 0, 5, userId = "12"),
                TextSpan(TextSpan.Kind.ANIMOJI, 0, 2, userId = "1"),
                TextSpan(TextSpan.Kind.MENTION, 0, 3, userId = "no"),
                TextSpan(TextSpan.Kind.MENTION, 8, 1, userId = "3"),
            ),
        )
        assertEquals(1, elements.size)
        assertEquals("USER_MENTION", elements[0]["type"])
        assertEquals(12L, elements[0]["entityId"])
        assertEquals(0, elements[0]["from"])
        assertEquals(5, elements[0]["length"])
    }

    @Test
    fun parsersSkipEmptyIds() {
        val hits = LockPayloads.foundMessages(
            10L,
            listOf(mapOf("chatId" to 10L, "message" to mapOf("id" to 4L, "sender" to 1L, "text" to "да", "time" to 9L))),
            1L,
        )
        assertEquals("4", hits.single().messageId)
        assertTrue(hits.single().isOutgoing)
        assertEquals("да", hits.single().text)
        val choices = LockPayloads.complaintChoices(
            mapOf("complains" to listOf(mapOf(
                "typeId" to 2,
                "reasons" to listOf(mapOf("reasonId" to 0, "reasonTitle" to "нет"), mapOf("reasonId" to 7, "reasonTitle" to "спам")),
            ))),
        )
        assertEquals("спам", choices[2]!!.single().title)
        val shared = LockPayloads.sharedChats(mapOf("commonChats" to listOf(mapOf("id" to 0L), mapOf("id" to 3L, "title" to "Дача"))))
        assertEquals("Дача", shared.single().title)
    }
}
