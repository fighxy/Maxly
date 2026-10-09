package app.maxly.presentation.profile

import app.maxly.SharedFixtures
import app.maxly.SharedFixtures.Companion.array
import app.maxly.SharedFixtures.Companion.obj
import app.maxly.SharedFixtures.Companion.raw
import app.maxly.SharedFixtures.Companion.str
import app.maxly.data.ChatMembersSource
import app.maxly.data.ChatPerson
import app.maxly.data.CoreChatMembers
import app.maxly.data.MemberPage
import com.max.core.api.ChatMembersResult
import com.max.core.api.ChatRoles
import com.max.core.api.MaxApi
import com.max.core.auth.RequestSink
import com.max.core.protocol.CmdType
import com.max.core.protocol.Opcode
import com.max.core.protocol.PROTOCOL_VERSION
import com.max.core.protocol.PacketHeader
import com.max.core.transport.TransportPacket
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Общие с iOS сценарии участников из `test-fixtures/members` (правила — в README каталога).
 * Источник страниц — шаги `CoreChatMembers` / `MaxClient.loadChatMembers` без клиента:
 * `CHAT_MEMBERS` ядра ([MaxApi]), [ChatMembersResult.of] с ролями [ChatRoles] карточки чата и
 * [CoreChatMembers.person]; листает [MemberList] (`load`, затем `loadMore`, пока есть ещё).
 * Значки — [MemberListState.roleLabel], поиск — [MemberListState.visible].
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MembersFixtureTest {
    private val fixtures = SharedFixtures("members")

    @Test
    fun everyFixtureIsPlayed() {
        val files = fixtures.files()
        for (file in files) play(file.nameWithoutExtension, fixtures.read(file))
        assertTrue("сыграно ${fixtures.played} случаев", fixtures.played >= files.size)
        fixtures.finish("MembersFixtureTest", files.size)
    }

    private fun play(file: String, fixture: JsonObject) {
        val kind = fixture["kind"].str
        for (case in fixtures.cases(fixture)) {
            fixtures.case("$file / ${case["name"].str}") {
                when (kind) {
                    "paging" -> paging(case)
                    "roles" -> roles(case)
                    "search" -> search(case)
                    else -> error("$file: незнакомый kind $kind")
                }
            }
        }
    }

    // ---- kind: paging ----------------------------------------------------------------------------

    private fun SharedFixtures.Case.paging(case: JsonObject) {
        val pages = case["pages"].array.map { it as JsonObject }
        val sink = PagesSink(pages.map(::reply))
        val people = list(sink, emptyMap(), pages.size)
        val expect = case["expect"].obj!!
        check("requests", expect["requests"].array.map { it.raw() }, sink.markers)
        check("ids", expect["ids"].array.map { it.str }, people.map { it.id })
    }

    // ---- kind: roles -----------------------------------------------------------------------------

    private fun SharedFixtures.Case.roles(case: JsonObject) {
        val sink = PagesSink(listOf(mapOf("members" to members(case["members"]))))
        val chat = LinkedHashMap<String, Any?>(mapOf("id" to CHAT_ID, "type" to "CHAT")).apply { putAll((case["chat"]!!.raw() as Map<*, *>).mapKeys { it.key.toString() }) }
        val people = list(sink, chat, 1)
        val expected = case["expect"].array.map { (it as JsonObject).let { e -> e["id"].str to e["badge"].str } }
        check("значки", expected, people.map { it.id to MemberListState.roleLabel(it).ifEmpty { null } })
    }

    // ---- kind: search ----------------------------------------------------------------------------

    private fun SharedFixtures.Case.search(case: JsonObject) {
        val members = case["members"].array.map {
            it as JsonObject
            ChatPerson(it["id"].str!!, it["name"].str!!, ChatPerson.Role.MEMBER, alias = null, mentionName = it["mentionName"].str)
        }
        // Список загружен весь: сервер не спрашивается, видны совпадения среди загруженных.
        val state = MemberListState(members = members, query = case["query"].str!!, loaded = true)
        check("ids", case["expect"].array.map { it.str }, state.visible.map { it.id })
    }

    // ---- клиент и ядро ---------------------------------------------------------------------------

    /** Весь список, как его долистает экран: [MemberList.load], затем [MemberList.loadMore], пока есть ещё. */
    private fun list(sink: PagesSink, chat: Map<String, Any?>, pages: Int): List<ChatPerson> {
        val scope = TestScope(StandardTestDispatcher())
        val list = MemberList(scope, SinkMembers(sink, ChatRoles.of(chat)), CHAT_ID.toString())
        list.load()
        scope.runCurrent()
        // Запасной предел: лишний запрос всё равно попадёт в sink.markers и разойдётся с ожидаемым.
        repeat(pages + 1) {
            if (!list.state.value.hasMore) return@repeat
            list.loadMore()
            scope.runCurrent()
        }
        return list.state.value.members
    }

    /** `CoreChatMembers.memberPage` над `MaxClient.loadChatMembers`: те же шаги ядра, роли из карточки. */
    private class SinkMembers(sink: RequestSink, private val roles: ChatRoles) : ChatMembersSource {
        private val api = MaxApi(sink).chats

        override suspend fun memberPage(chatId: String, marker: Long?): MemberPage {
            val requested = marker ?: 0L
            val page = api.getChatMembers(chatId.toLong(), requested, CoreChatMembers.PAGE)
            val result = ChatMembersResult.of(page, requested, roles)
            val names = result.members.mapNotNull { entry -> entry.userId?.let { it to entry.user?.displayName.orEmpty() } }.toMap()
            return MemberPage(result.members.mapNotNull { CoreChatMembers.person(it, name = { id -> names[id].orEmpty() }) }, result.nextMarker)
        }

        override suspend fun searchMembers(chatId: String, query: String): List<ChatPerson> = error("поиск на сервере в сценарии не нужен")
    }

    /** Ответы `CHAT_MEMBERS` по порядку; маркеры запросов — как ушли. */
    private class PagesSink(private val replies: List<Map<String, Any?>>) : RequestSink {
        val markers = mutableListOf<Any?>()

        override suspend fun request(opcode: Opcode, payload: Any?): TransportPacket {
            check(opcode == Opcode.CHAT_MEMBERS) { "неожиданный запрос $opcode" }
            val map = payload as Map<*, *>
            check(map["query"] == null) { "поиск на сервере в сценарии не нужен" }
            markers += (map["marker"] as? Number)?.toLong()
            val body = replies.getOrNull(markers.size - 1) ?: error("лишний запрос с marker ${map["marker"]}")
            return TransportPacket(PacketHeader(PROTOCOL_VERSION, CmdType.OK.value, 1, opcode.value.toShort(), 0, false), body)
        }
    }

    /** Ответ сервера из страницы сценария: `marker` как есть (нет, `null`, число или строка). */
    private fun reply(page: JsonObject): Map<String, Any?> = buildMap {
        put("members", members(page["members"]))
        if (page.containsKey("marker")) put("marker", page["marker"]!!.raw())
    }

    private fun members(value: JsonElement?): List<Map<String, Any?>> = value.array.map {
        it as JsonObject
        mapOf("contact" to mapOf("id" to it["id"].str!!.toLong(), "names" to listOf(mapOf("name" to it["name"].str, "type" to "ONEME"))))
    }

    private companion object {
        const val CHAT_ID = -100L
    }
}
