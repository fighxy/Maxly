package app.maxly.presentation.profile

import app.maxly.data.ChatMembersSource
import app.maxly.data.ChatPerson
import app.maxly.data.MemberPage
import app.maxly.domain.MaxlyError
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Сервер участников: страницы по два человека, `marker` — номер следующего. */
private class PagedMembers(val people: List<ChatPerson>) : ChatMembersSource {
    val markers = mutableListOf<Long?>()
    val queries = mutableListOf<String>()
    var searchFailure: Exception? = null
    override suspend fun memberPage(chatId: String, marker: Long?): MemberPage {
        markers += marker
        val from = (marker ?: 0L).toInt()
        val page = people.drop(from).take(2)
        val next = (from + 2).takeIf { it < people.size }?.toLong()
        return MemberPage(page, next)
    }
    override suspend fun searchMembers(chatId: String, query: String): List<ChatPerson> {
        queries += query
        searchFailure?.let { throw it }
        return people.filter { it.name.contains(query, ignoreCase = true) }
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class MemberListTest {
    private val scope = TestScope(StandardTestDispatcher())
    private val people = listOf(
        ChatPerson("1", "Иван", ChatPerson.Role.OWNER),
        ChatPerson("2", "Анна", ChatPerson.Role.ADMIN, alias = "модератор"),
        ChatPerson("3", "Пётр"),
        ChatPerson("4", "Мария"),
        ChatPerson("5", "Анатолий"),
    )
    private val source = PagedMembers(people)
    private val list = MemberList(scope, source, "7")

    @Test
    fun pagesFollowTheMarkerUntilTheLast() {
        list.load()
        scope.runCurrent()
        assertEquals(listOf("1", "2"), list.state.value.visible.map { it.id })
        assertTrue(list.state.value.hasMore)
        list.loadMore()
        scope.runCurrent()
        list.loadMore()
        scope.runCurrent()
        assertEquals(listOf("1", "2", "3", "4", "5"), list.state.value.members.map { it.id })
        assertFalse(list.state.value.hasMore)
        list.loadMore()
        scope.runCurrent()
        assertEquals(listOf(null, 2L, 4L), source.markers)
    }

    @Test
    fun reloadStartsFromTheFirstPage() {
        list.load()
        scope.runCurrent()
        list.loadMore()
        scope.runCurrent()
        list.load()
        scope.runCurrent()
        assertEquals(listOf("1", "2"), list.state.value.members.map { it.id })
        assertEquals(listOf(null, 2L, null), source.markers)
    }

    @Test
    fun searchAsksTheServerAfterAPauseAndShowsLoadedMatchesMeanwhile() {
        list.load()
        scope.runCurrent()
        list.search("ан")
        list.search("анн")
        scope.runCurrent()
        assertTrue(list.state.value.searching)
        // Пока сервер не ответил — совпадения среди загруженных.
        assertEquals(listOf("2"), list.state.value.visible.map { it.id })
        scope.advanceTimeBy(400)
        scope.runCurrent()
        assertEquals(listOf("анн"), source.queries)
        assertEquals(listOf("2"), list.state.value.visible.map { it.id })
        list.search("ана")
        scope.advanceTimeBy(400)
        scope.runCurrent()
        assertEquals(listOf("5"), list.state.value.visible.map { it.id })
        list.search("")
        assertEquals(listOf("1", "2"), list.state.value.visible.map { it.id })
        assertFalse(list.state.value.searching)
    }

    @Test
    fun failedSearchKeepsLocalMatchesAndSaysSo() {
        list.load()
        scope.runCurrent()
        source.searchFailure = MaxlyError.Rejected("Сервер занят")
        list.search("иван")
        scope.advanceTimeBy(400)
        scope.runCurrent()
        assertEquals(listOf("1"), list.state.value.visible.map { it.id })
        assertEquals("Сервер занят", list.state.value.error)
        list.search("щ")
        scope.advanceTimeBy(400)
        scope.runCurrent()
        assertEquals("Никого не нашлось", list.state.value.emptyText)
    }

    @Test
    fun fullyLoadedListIsSearchedOnlyLocally() {
        list.load()
        scope.runCurrent()
        list.loadMore()
        scope.runCurrent()
        list.loadMore()
        scope.runCurrent()
        assertFalse(list.state.value.hasMore)
        list.search("ан")
        assertFalse(list.state.value.searching)
        assertEquals(listOf("1", "2", "5"), list.state.value.visible.map { it.id })
        scope.advanceTimeBy(1_000)
        scope.runCurrent()
        assertTrue(source.queries.isEmpty())
        assertEquals(listOf("1", "2", "5"), list.state.value.visible.map { it.id })
    }

    @Test
    fun partlyLoadedListAsksTheServer200msAfterTheLastKey() {
        list.load()
        scope.runCurrent()
        list.search("а")
        scope.advanceTimeBy(100)
        list.search("ан")
        scope.advanceTimeBy(100)
        list.search("ана")
        scope.advanceTimeBy(199)
        scope.runCurrent()
        assertTrue(source.queries.isEmpty())
        assertTrue(list.state.value.searching)
        scope.advanceTimeBy(2)
        scope.runCurrent()
        // Быстрый ввод — один запрос, с последним текстом.
        assertEquals(listOf("ана"), source.queries)
        assertEquals(listOf("5"), list.state.value.visible.map { it.id })
        assertFalse(list.state.value.searching)
    }

    @Test
    fun searchBeforeTheFirstPageAsksTheServer() {
        list.search("пётр")
        scope.advanceTimeBy(250)
        scope.runCurrent()
        assertEquals(listOf("пётр"), source.queries)
        assertEquals(listOf("3"), list.state.value.visible.map { it.id })
    }

    @Test
    fun rolesAreLabelled() {
        assertEquals("владелец", MemberListState.roleLabel(people[0]))
        assertEquals("модератор", MemberListState.roleLabel(people[1]))
        assertEquals("", MemberListState.roleLabel(people[2]))
        assertNull(MemberListState().emptyText)
        assertEquals("Список пуст", MemberListState(loaded = true).emptyText)
    }
}
